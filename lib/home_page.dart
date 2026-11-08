// Home: centered balance under a teal glow, payment list, fixed bottom bar [Enviar] [QR] [Receber] (layout after Glow).
import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'chain_balances.dart';
import 'onchain.dart';
import 'pending_sends.dart';
import 'pending_sheet.dart';
import 'secret_store.dart';
import 'receive_sheet.dart';
import 'send_sheet.dart';
import 'stable_send.dart';
import 'stable_send_sheet.dart';
import 'stable_sheet.dart';
import 'theme.dart';
import 'wallet.dart';
import 'wallet_info_page.dart';
import 'wipe.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.sdk, required this.wallet, required this.words, required this.version, required this.lock, required this.ops});
  final breez.BreezSdk sdk;
  final DerivedWallet wallet;
  final List<String> words;
  final String version;
  final AppLock lock;
  final WalletOps ops;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int? _sats;
  List<breez.Payment> _payments = const [];
  List<StableBalance>? _stable;
  List<GasBalance>? _gas;
  List<PendingSend> _pending = const [];
  bool _reconciling = false;
  final _pendingStore = SecretPendingStore(SecretStore());
  late final _sender = StableSender(store: _pendingStore);
  final _onchainPending = OnchainPendingStore(SecretStore());
  String? _error;
  bool _syncing = true;
  Timer? _timer;

  /// What the delete screen lists as cut off. A notifier, not a snapshot: opened while the first sync is still running it says
  /// "carregando..." and fills in by itself when the balances arrive.
  final _lines = ValueNotifier<List<String>>(const []);

  @override
  void initState() {
    super.initState();
    _lines.value = _balanceLines();
    _reconcilePending();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lines.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (!quiet) setState(() => _syncing = true);
    try {
      await widget.sdk.syncWallet(request: const breez.SyncWalletRequest());
      final info = await widget.sdk.getInfo(request: const breez.GetInfoRequest(ensureSynced: false));
      final list = await widget.sdk.listPayments(request: const breez.ListPaymentsRequest(limit: 30));
      _reconcilePending();
      final (stable, gas) = await (
        readStableBalances(polygon: widget.wallet.polygon, solana: widget.wallet.solana),
        readGasBalances(polygon: widget.wallet.polygon, solana: widget.wallet.solana),
      ).wait;
      if (!mounted) return;
      setState(() {
        _sats = info.balanceSats.toInt();
        _payments = list.payments;
        _stable = stable;
        _gas = gas;
        _error = null;
        _syncing = false;
        _lines.value = _balanceLines();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _syncing = false;
        });
      }
    }
  }

  /// Settles the stablecoin sends left open (by this run or an earlier one): certain outcomes are told and forgotten, the rest stay.
  Future<void> _reconcilePending() async {
    if (_reconciling) return;
    _reconciling = true;
    try {
      for (final r in await _pendingStore.all()) {
        final o = await _sender.reconcile(r);
        if (o == null) continue;
        await _pendingStore.remove(r.id);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(settledText(r, o))));
      }
      final left = await _pendingStore.all();
      if (mounted) setState(() => _pending = left);
    } catch (_) {
      // an unreadable record is not an empty one: the sender refuses new sends until it can be read
    } finally {
      _reconciling = false;
    }
  }

  Future<void> _openPending(PendingSend r) async {
    final told = await showAppSheet<String>(context, (_) => PendingSheet(record: r, sender: _sender, words: widget.words, confirmPin: () => _confirmPin('Confirme o PIN para cancelar o envio')));
    if (told != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(told)));
    await _reconcilePending();
  }

  /// The PIN again, on top of everything, for what moves money or shows the words.
  Future<bool> _confirmPin(String why) => widget.lock.confirm(context, reason: why);

  /// What is on this wallet now, for the delete confirmation: sats, USDT/USDC, and the POL/SOL kept for gas.
  List<String> _balanceLines() {
    final out = <String>[];
    out.add(_sats == null ? 'sats: carregando...' : (_sats! > 0 ? '${fmtSats(_sats!)} sats' : ''));
    for (final sym in const ['USDT', 'USDC']) {
      final rows = _stable?.where((b) => b.symbol == sym || (sym == 'USDC' && b.symbol == 'USDC.e'));
      if (rows == null) {
        out.add('$sym: carregando...');
        continue;
      }
      var sum = BigInt.zero;
      var unknown = false;
      for (final r in rows) {
        final v = r.raw;
        if (v == null) {
          unknown = true;
        } else {
          sum += v;
        }
      }
      out.add(unknown ? '$sym: não consegui ler' : (sum > BigInt.zero ? '$sym ${fmtUnits(sum, stableDecimals6)}' : ''));
    }
    for (final g in _gas ?? const <GasBalance>[]) {
      final v = g.raw;
      out.add(v == null ? '${g.symbol}: não consegui ler' : (v > BigInt.zero ? '${g.symbol} ${g.text}' : ''));
    }
    return out.where((l) => l.isNotEmpty).toList();
  }

  Future<void> _send() async {
    final what = await showAppSheet<String>(context, (_) => const SendChooser());
    if (what == null || !mounted) return;
    if (what == 'ln') {
      await _openSendSheet();
    } else {
      await _sendStable(what == 'Polygon' ? Net.polygon : Net.solana);
    }
    _refresh(quiet: true);
  }

  Future<void> _openSendSheet({String? initial}) =>
      showSendSheet(context, sdk: widget.sdk, pending: _onchainPending, initial: initial, confirmPin: () => _confirmPin('Confirme o PIN para enviar'));

  /// The sheet cannot be swiped away: a send walked away from mid-way would hide its outcome and invite a second payment.
  Future<void> _sendStable(Net net, {String? address}) async {
    // a send still open on this network comes first: sending again before it is settled can pay twice
    final open = _pending.where((r) => r.net == net.name).firstOrNull;
    if (open != null) return _openPending(open);
    await showAppSheet<bool>(
      context,
      (_) => StableSendSheet(
        net: net,
        from: net == Net.polygon ? widget.wallet.polygon : widget.wallet.solana,
        words: widget.words,
        balances: _stable,
        initialAddress: address,
        sender: _sender,
        confirmPin: () => _confirmPin('Confirme o PIN para enviar'),
      ),
      dismissible: false,
    );
  }

  Future<void> _receive() async {
    final what = await showAppSheet<String>(context, (_) => const ReceiveChooser());
    if (what == null || !mounted) return;
    if (what == 'ln') {
      final got = await showAppSheet<int>(context, (_) => ReceiveSheet(sdk: widget.sdk));
      _refresh(quiet: true);
      if (got != null && mounted) _celebrate(got);
    } else {
      final a = what == 'Polygon' ? widget.wallet.polygon : widget.wallet.solana;
      await showAppSheet<void>(context, (_) => StableReceive(network: what, address: a));
      _refresh(quiet: true);
    }
  }

  static final _evm = RegExp(r'^(ethereum:|polygon:)?0x[0-9a-fA-F]{40}', caseSensitive: false);
  static final _sol = RegExp(r'^(solana:)?[1-9A-HJ-NP-Za-km-z]{32,44}$');

  /// The main QR button: a Lightning invoice, voucher or address opens the send sheet already read;
  /// a stablecoin address opens the USDT/USDC send for its network (a 0x address is Polygon here: the sheet says so before sending).
  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (code == null || !mounted) return;
    final t = code.trim();
    if (_evm.hasMatch(t) || (_sol.hasMatch(t) && !t.toLowerCase().startsWith('ln'))) {
      await _sendStable(_evm.hasMatch(t) ? Net.polygon : Net.solana, address: t);
      _refresh(quiet: true);
      return;
    }
    await _openSendSheet(initial: t);
    _refresh(quiet: true);
  }

  void _celebrate(int sats) {
    showDialog<void>(
      context: context,
      barrierColor: C.voidBg.withValues(alpha: .92),
      builder: (ctx) {
        Timer(const Duration(seconds: 4), () {
          if (ctx.mounted) Navigator.of(ctx).maybePop();
        });
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.success.withValues(alpha: .15),
                      border: Border.all(color: C.success, width: 2),
                      boxShadow: [BoxShadow(color: C.success.withValues(alpha: .4), blurRadius: 40)],
                    ),
                    child: const Icon(Icons.arrow_downward, size: 44, color: C.success),
                  ),
                  const SizedBox(height: 24),
                  const Text('Pagamento recebido', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(
                    '+${fmtSats(sats)} sats',
                    style: const TextStyle(fontFamily: monoFamily, fontSize: 48, fontWeight: FontWeight.w700, color: C.primaryLight),
                  ),
                  const SizedBox(height: 28),
                  const Text('Toque para fechar', style: TextStyle(color: C.muted, fontSize: 13)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu, color: C.textSec),
                      onPressed: () {
                        _refresh(quiet: true); // fresh balances for the delete screen
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WalletInfoPage(
                              wallet: widget.wallet,
                              words: widget.words,
                              version: widget.version,
                              lock: widget.lock,
                              ops: widget.ops,
                              balanceLines: _lines,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              _Balance(sats: _sats, syncing: _syncing),
              _StableCard(balances: _stable),
              _GasCard(balances: _gas),
              for (final r in _pending) _PendingNotice(r, onTap: () => _openPending(r)),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: C.warn, fontSize: 12)),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: RefreshIndicator(
                  color: C.primaryLight,
                  backgroundColor: C.surface,
                  onRefresh: _refresh,
                  child: _payments.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Column(
                                children: [
                                  Text(_syncing ? 'Sincronizando...' : 'Nenhum pagamento ainda', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 40),
                                    child: Text(
                                      'Seu histórico aparece aqui depois do primeiro pagamento enviado ou recebido.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: C.muted, fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _payments.length,
                          itemBuilder: (_, i) => _PaymentRow(_payments[i]),
                        ),
                ),
              ),
              _BottomBar(onSend: _send, onScan: _scan, onReceive: _receive),
            ],
          ),
        ),
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.sats, required this.syncing});
  final int? sats;
  final bool syncing;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (syncing) ...[
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: C.primaryLight, shape: BoxShape.circle)),
            const SizedBox(width: 8),
          ],
          Text(syncing ? 'SINCRONIZANDO' : 'SALDO', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 2.4, color: C.muted)),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('₿ ', style: TextStyle(fontSize: 30, color: C.textSec.withValues(alpha: .7), fontFamily: monoFamily)),
          Text(
            sats == null ? '...' : fmtSats(sats!),
            style: TextStyle(
              fontFamily: monoFamily,
              fontSize: 44,
              fontWeight: FontWeight.w600,
              letterSpacing: -.9,
              shadows: [Shadow(color: C.primary.withValues(alpha: .5), blurRadius: 40)],
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text('sats', style: TextStyle(color: C.textSec, fontSize: 14, fontFamily: monoFamily)),
    ],
  );
}

String _ago(int ts) {
  final s = DateTime.now().millisecondsSinceEpoch ~/ 1000 - ts;
  if (s < 60) return 'agora';
  if (s < 3600) return '${s ~/ 60} min';
  if (s < 86400) return '${s ~/ 3600} h';
  if (s < 86400 * 30) return '${s ~/ 86400} d';
  return '${s ~/ (86400 * 30)} mes';
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow(this.p);
  final breez.Payment p;
  @override
  Widget build(BuildContext context) {
    final recv = p.paymentType == breez.PaymentType.receive;
    final color = recv ? C.success : C.electric;
    final failed = p.status == breez.PaymentStatus.failed;
    final pending = p.status == breez.PaymentStatus.pending;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
            child: Icon(recv ? Icons.arrow_downward : Icons.arrow_upward, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(recv ? 'Recebido' : 'Enviado', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 4),
                    Icon(p.method == breez.PaymentMethod.deposit || p.method == breez.PaymentMethod.withdraw ? Icons.link : Icons.bolt, size: 14, color: C.muted),
                    if (pending) ...[
                      const SizedBox(width: 6),
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: C.warn, shape: BoxShape.circle)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _ago(p.timestamp.toInt()),
                    if (!recv && p.fees > BigInt.zero) 'taxa ${p.fees}',
                    if (pending) 'PROCESSANDO',
                    if (failed) 'FALHOU',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: C.muted),
                ),
              ],
            ),
          ),
          Text(
            '${recv ? '+' : '−'}${fmtSats(p.amount.toInt())}',
            style: TextStyle(
              fontFamily: monoFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: failed ? C.muted : color,
              decoration: failed ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onSend, required this.onScan, required this.onReceive});
  final VoidCallback onSend;
  final VoidCallback onScan;
  final VoidCallback onReceive;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: C.surface.withValues(alpha: .85),
      border: const Border(top: BorderSide(color: C.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: GradientButton(label: 'Enviar', icon: Icons.arrow_upward, colors: const [C.electric, Color(0xFF0099CC)], onPressed: onSend),
        ),
        const SizedBox(width: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onScan,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(border: Border.all(color: C.primaryLight, width: 1.5), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.qr_code_scanner, color: C.primaryLight, size: 26),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GradientButton(label: 'Receber', icon: Icons.arrow_downward, colors: const [C.success, Color(0xFF059669)], onPressed: onReceive),
        ),
      ],
    ),
  );
}

/// USDT and USDC under the sats balance, summed over Polygon and Solana; '?' when no node answered.
class _StableCard extends StatelessWidget {
  const _StableCard({required this.balances});
  final List<StableBalance>? balances;

  BigInt? _sum(String symbol) {
    final rows = balances?.where((b) => b.symbol == symbol || (symbol == 'USDC' && b.symbol == 'USDC.e'));
    if (rows == null) return null;
    var sum = BigInt.zero;
    for (final r in rows) {
      if (r.raw == null) return null;
      sum += r.raw!;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    Widget cell(String symbol) {
      final v = _sum(symbol);
      return Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icons/${symbol.toLowerCase()}.png', width: 22, height: 22),
            const SizedBox(width: 8),
            Text(symbol, style: const TextStyle(fontSize: 13, color: C.textSec)),
            const SizedBox(width: 8),
            Text(v == null ? '...' : StableBalance('', symbol, v).text, style: const TextStyle(fontFamily: monoFamily, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Panel(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(children: [cell('USDT'), Container(width: 1, height: 24, color: C.border), cell('USDC')]),
      ),
    );
  }
}

/// POL and SOL under the stablecoins: the gas the user pays for a USDT/USDC send on each network.
class _GasCard extends StatelessWidget {
  const _GasCard({required this.balances});
  final List<GasBalance>? balances;

  @override
  Widget build(BuildContext context) {
    Widget cell(String symbol, String icon) {
      final b = balances?.where((g) => g.symbol == symbol).firstOrNull;
      return Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icons/$icon.png', width: 18, height: 18),
            const SizedBox(width: 6),
            Text('$symbol gás', style: const TextStyle(fontSize: 12, color: C.muted)),
            const SizedBox(width: 6),
            Text(b == null ? '...' : b.text, style: const TextStyle(fontFamily: monoFamily, fontSize: 13, fontWeight: FontWeight.w600, color: C.textSec)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Panel(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(children: [cell('POL', 'polygon'), Container(width: 1, height: 18, color: C.border), cell('SOL', 'solana')]),
      ),
    );
  }
}

/// An open stablecoin send, on the home screen until its outcome is certain.
class _PendingNotice extends StatelessWidget {
  const _PendingNotice(this.record, {required this.onTap});
  final PendingSend record;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Panel(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top, size: 18, color: C.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Envio em aberto: ${pendingAmount(record)} na ${pendingNetName(record)}. Toque para ver',
                style: const TextStyle(color: C.warn, fontSize: 13),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: C.muted),
          ],
        ),
      ),
    ),
  );
}
