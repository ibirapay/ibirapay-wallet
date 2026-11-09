// Send USDT / USDC on one network: form -> quote -> confirm -> sending -> result. The network is chosen before this sheet opens and is
// shown in large type on the confirm step, because an address alone does not say which chain it is for.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chain_balances.dart';
import 'send_sheet.dart' show ScanPage;
import 'i18n.dart';
import 'stable_send.dart';
import 'theme.dart';

enum _Step { form, confirm, busy, done }

class StableSendSheet extends StatefulWidget {
  const StableSendSheet({super.key, required this.net, required this.from, required this.words, required this.balances, this.initialAddress, required this.sender, required this.confirmPin});
  final Net net;

  /// The wallet's own address on [net].
  final String from;
  final List<String> words;
  final List<StableBalance>? balances;
  final String? initialAddress;

  /// The app's one sender (its store is what remembers an open send); a test passes one that talks to a fake node.
  final StableSender sender;

  /// Asks the PIN before anything is signed; false (wrong, cancelled) leaves the confirm step as it is.
  final Future<bool> Function() confirmPin;
  @override
  State<StableSendSheet> createState() => _StableSendSheetState();
}

class _StableSendSheetState extends State<StableSendSheet> {
  StableSender get _sender => widget.sender;
  final _to = TextEditingController();
  final _amount = TextEditingController();
  late final List<StableToken> _tokens;
  late StableToken _token;
  _Step _step = _Step.form;
  Quote? _quote;
  Outcome? _outcome;
  String? _failure; // set when submit refused before broadcasting: nothing was sent
  String? _error;
  bool _working = false;
  bool _copied = false;

  bool get _poly => widget.net == Net.polygon;
  String get _netName => _poly ? 'Polygon' : 'Solana';

  BigInt? _bal(StableToken t) => widget.balances?.where((b) => b.network == t.netName && b.symbol == t.symbol).firstOrNull?.raw;

  @override
  void initState() {
    super.initState();
    const rank = {'USDT': 0, 'USDC': 1, 'USDC.e': 2};
    _tokens = (_poly ? polygonSendTokens : solanaSendTokens).where((t) => t.symbol != 'USDC.e' || (_bal(t) ?? BigInt.zero) > BigInt.zero).toList()
      ..sort((a, b) => rank[a.symbol]!.compareTo(rank[b.symbol]!));
    _token = _tokens.firstWhere((t) => (_bal(t) ?? BigInt.zero) > BigInt.zero, orElse: () => _tokens.first);
    if (widget.initialAddress != null) _to.text = widget.initialAddress!;
  }

  @override
  void dispose() {
    _to.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _to.text = d!.text!.trim());
  }

  Future<void> _scan() async {
    final v = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (v != null && mounted) setState(() => _to.text = v.trim());
  }

  Future<void> _continue() async {
    final BigInt amount;
    try {
      amount = parseStableAmount(_amount.text);
    } on SendError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final q = await _sender.quote(token: _token, from: widget.from, to: _to.text, amount: amount);
      if (!mounted) return;
      setState(() {
        _quote = q;
        _step = _Step.confirm;
      });
    } on SendError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = tr('sts.unexpected', {'e': e}));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool _asking = false;

  Future<void> _send() async {
    final q = _quote;
    if (q == null || _step != _Step.confirm || _asking) return;
    _asking = true;
    final ok = await widget.confirmPin();
    _asking = false;
    if (!ok || !mounted) return;
    setState(() => _step = _Step.busy);
    try {
      final o = await _sender.submit(q, widget.words);
      if (mounted) {
        setState(() {
          _outcome = o;
          _step = _Step.done;
        });
      }
    } on SendError catch (e) {
      if (mounted) {
        setState(() {
          _failure = e.message;
          _step = _Step.done;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failure = tr('sts.unexpectedCheck', {'e': e});
          _step = _Step.done;
        });
      }
    }
  }

  Widget _netRow({double size = 22, double font = 15}) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Image.asset('assets/icons/${_poly ? 'polygon' : 'solana'}.png', width: size, height: size),
      const SizedBox(width: 8),
      Text(tr('ss.network', {'net': _netName}), style: TextStyle(fontSize: font, fontWeight: FontWeight.w700)),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step != _Step.busy,
    child: switch (_step) {
      _Step.form => _form(),
      _Step.confirm => _confirm(),
      _Step.busy => _busy(),
      _Step.done => _done(),
    },
  );

  Widget _form() {
    final bal = _bal(_token);
    return Column(
      children: [
        SheetTitle(tr('sts.title'), Icons.arrow_upward),
        const SizedBox(height: 10),
        _netRow(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final t in _tokens)
              ChoiceChip(
                label: Text(t.symbol),
                selected: t == _token,
                onSelected: (_) => setState(() => _token = t),
                selectedColor: C.primary.withValues(alpha: .25),
                backgroundColor: C.dark,
                side: BorderSide(color: t == _token ? C.primaryLight : C.border),
                labelStyle: const TextStyle(color: Colors.white),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _to,
          minLines: 2,
          maxLines: 3,
          style: const TextStyle(fontFamily: monoFamily, fontSize: 13),
          decoration: InputDecoration(hintText: _poly ? tr('sts.addressPoly') : tr('sts.addressSol')),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: OutlineButton(label: tr('common.paste'), icon: Icons.content_paste, onPressed: _paste)),
            const SizedBox(width: 10),
            Expanded(child: OutlineButton(label: tr('common.scan'), icon: Icons.qr_code_scanner, onPressed: _scan)),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontFamily: monoFamily, fontSize: 24, fontWeight: FontWeight.w600),
          decoration: InputDecoration(hintText: tr('common.amount'), suffixText: _token.symbol),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              bal == null ? tr('sts.balance', {'v': '...'}) : tr('sts.balance', {'v': '${fmtUnits(bal, stableDecimals6)} ${_token.symbol}'}),
              style: const TextStyle(color: C.muted, fontSize: 12),
            ),
            if (bal != null && bal > BigInt.zero)
              GestureDetector(
                onTap: () => setState(() => _amount.text = fmtUnits(bal, stableDecimals6, minPlaces: stableDecimals6)),
                child: Text(tr('sts.all'), style: const TextStyle(color: C.primaryLight, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            tr('sts.gasNote', {'gas': _token.gasSymbol, 'net': _netName}),
            style: const TextStyle(color: C.muted, fontSize: 12),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: C.warn, fontSize: 13))),
        const SizedBox(height: 16),
        GradientButton(label: _working ? tr('sts.consulting') : tr('common.continue'), onPressed: _working ? null : _continue),
        const SizedBox(height: 8),
        TextButton(onPressed: _working ? null : () => Navigator.pop(context, false), child: Text(tr('common.cancel'), style: const TextStyle(color: C.muted))),
      ],
    );
  }

  Widget _confirm() {
    final q = _quote!;
    final gasDec = _poly ? 18 : 9;
    final left = q.gasBalance - q.fee - q.rent;
    String gas(BigInt v) => '${fmtUnits(v, gasDec, minPlaces: 4)} ${q.token.gasSymbol}';
    return Column(
      children: [
        Text(tr('send.youWillSend'), style: const TextStyle(color: C.textSec, fontSize: 14)),
        const SizedBox(height: 6),
        Text('${fmtUnits(q.amount, stableDecimals6)} ${q.token.symbol}', style: const TextStyle(fontFamily: monoFamily, fontSize: 34, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: C.primary.withValues(alpha: .12), border: Border.all(color: C.primaryLight), borderRadius: BorderRadius.circular(12)),
          child: _netRow(size: 26, font: 20),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('common.to'), style: const TextStyle(color: C.textSec, fontSize: 14)),
              const SizedBox(height: 6),
              _AddressText(q.to),
              const Divider(height: 20),
              RowKV(_poly ? tr('sts.networkFeeUpTo') : tr('send.networkFee'), gas(q.fee)),
              if (q.rent > BigInt.zero) RowKV(tr('sts.recipientAccount'), gas(q.rent)),
              RowKV(tr('sts.gasLeft'), gas(left)),
            ],
          ),
        ),
        for (final w in q.warnings) Padding(padding: const EdgeInsets.only(top: 10), child: Text(w, style: const TextStyle(color: C.warn, fontSize: 13))),
        const SizedBox(height: 10),
        Text(
          tr('sts.checkNet', {'net': _netName, 'sym': _token.symbol}),
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.warn, fontSize: 12),
        ),
        const SizedBox(height: 16),
        GradientButton(label: tr('btn.send'), colors: const [C.electric, Color(0xFF0099CC)], onPressed: _send),
        const SizedBox(height: 8),
        TextButton(onPressed: () => setState(() => _step = _Step.form), child: Text(tr('scan.back'), style: const TextStyle(color: C.muted))),
      ],
    );
  }

  Widget _busy() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 3, color: C.primaryLight)),
        const SizedBox(height: 24),
        Text(tr('send.sending'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(tr('sts.sendingNote'), textAlign: TextAlign.center, style: const TextStyle(color: C.textSec, fontSize: 14)),
      ],
    ),
  );

  Widget _done() {
    final o = _outcome;
    final (IconData icon, Color color, String title, String body) = o == null
        ? (Icons.close, C.warn, tr('sts.notSent'), _failure ?? '')
        : switch (o.result) {
            Result.confirmed => (Icons.check, C.success, tr('sts.sent'), tr('sts.confirmedOn', {'net': _netName})),
            Result.reverted => (Icons.close, C.warn, tr('sts.txFailed'), tr('sts.revertedBody', {'sym': _token.symbol})),
            Result.notSent => (Icons.close, C.warn, tr('sts.notSent'), tr('sts.expiredBody')),
            Result.pending => (
              Icons.hourglass_top,
              C.warn,
              tr('sts.pendingTitle'),
              tr('sts.pendingBody'),
            ),
          };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .15), border: Border.all(color: color, width: 2)),
            child: Icon(icon, size: 36, color: color),
          ),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color == C.success ? C.primaryLight : color)),
          const SizedBox(height: 10),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: C.textSec, fontSize: 14)),
          if (o != null) ...[
            const SizedBox(height: 16),
            Panel(child: SelectableText(o.id, style: const TextStyle(fontFamily: monoFamily, fontSize: 12, color: C.primaryLight))),
            const SizedBox(height: 10),
            OutlineButton(
              label: _copied ? tr('sts.linkCopied') : tr('sts.copyLink'),
              icon: Icons.copy,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: o.explorer));
                if (mounted) setState(() => _copied = true);
              },
            ),
          ],
          const SizedBox(height: 20),
          GradientButton(
            label: o == null || o.result == Result.notSent ? tr('scan.back') : tr('common.done'),
            onPressed: () {
              if (o == null || o.result == Result.notSent) {
                setState(() {
                  _failure = null;
                  _outcome = null;
                  _step = _Step.form;
                });
              } else {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// The whole address, with its first and last 6 characters in the accent colour: the part a look-alike address cannot fake cheaply.
class _AddressText extends StatelessWidget {
  const _AddressText(this.address);
  final String address;
  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: monoFamily, fontSize: 14, color: C.textSec);
    const bold = TextStyle(fontFamily: monoFamily, fontSize: 14, color: C.primaryLight, fontWeight: FontWeight.w700);
    return SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(text: address.substring(0, 6), style: bold),
          TextSpan(text: address.substring(6, address.length - 6), style: mono),
          TextSpan(text: address.substring(address.length - 6), style: bold),
        ],
      ),
    );
  }
}
