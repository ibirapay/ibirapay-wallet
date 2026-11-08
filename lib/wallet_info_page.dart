// Carteira: the 12 words (behind a reveal), the Polygon and Solana addresses, build version.
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'chain_balances.dart' show rpcRoute;
import 'spark.dart' show sparkRoute;
import 'delete_wallet_view.dart';
import 'theme.dart';
import 'wallet.dart';
import 'wipe.dart';

class WalletInfoPage extends StatefulWidget {
  const WalletInfoPage({super.key, required this.wallet, required this.words, required this.version, required this.lock, required this.ops, required this.balanceLines});
  final DerivedWallet wallet;
  final List<String> words;
  final String version;
  final AppLock lock;
  final WalletOps ops;
  final ValueListenable<List<String>> balanceLines;
  @override
  State<WalletInfoPage> createState() => _WalletInfoPageState();
}

class _WalletInfoPageState extends State<WalletInfoPage> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.lock.addListener(_onLock);
  }

  /// The words are put away whenever the app locks, so they never reappear after an unlock.
  void _onLock() {
    if (widget.lock.locked && _show) _hide();
  }

  void _hide() {
    widget.lock.secure.release('words');
    if (mounted) setState(() => _show = false);
  }

  @override
  void dispose() {
    widget.lock.removeListener(_onLock);
    widget.lock.secure.release('words');
    super.dispose();
  }

  Future<void> _toggle() async {
    // showing the words asks the PIN; hiding them does not
    if (!_show && !await widget.lock.confirm(context, reason: 'Confirme o PIN para ver as 12 palavras')) return;
    if (!mounted) return;
    if (_show) {
      _hide();
      return;
    }
    // no screenshots or recordings while the words are on screen, whatever else happens: and the words are only drawn once that is
    // CONFIRMED on; if it cannot be switched on they are not shown at all
    final ok = await widget.lock.secure.hold('words');
    if (!ok || !mounted) {
      widget.lock.secure.release('words');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não consegui bloquear capturas de tela, então as palavras não serão mostradas.')));
      }
      return;
    }
    setState(() => _show = true);
  }

  Widget _addr(String label, String a) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: C.textSec, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: SelectableText(a, style: const TextStyle(fontFamily: monoFamily, fontSize: 12.5, color: C.primaryLight))),
              IconButton(
                icon: const Icon(Icons.copy, size: 18, color: C.muted),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: a));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado')));
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );

  void _openDelete() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: const Text('Apagar carteira'), backgroundColor: C.surface, automaticallyImplyLeading: false),
        body: Backdrop(
          child: SafeArea(
            child: DeleteWalletView(
              ops: widget.ops,
              balances: widget.balanceLines,
              onBack: () => Navigator.pop(ctx),
              confirmPin: () => widget.lock.confirm(ctx, reason: 'Confirme o PIN para apagar a carteira'),
              onWiped: widget.lock.walletWiped, // the Gate goes back to the welcome screen and clears the pages above it
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Carteira'), backgroundColor: C.surface),
    body: Backdrop(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Endereços para USDT e USDC', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .5, color: C.muted)),
          const SizedBox(height: 10),
          _addr('Polygon', widget.wallet.polygon),
          _addr('Solana', widget.wallet.solana),
          const SizedBox(height: 12),
          const Text('Palavras de recuperação', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .5, color: C.muted)),
          const SizedBox(height: 10),
          Panel(
            child: Column(
              children: [
                if (_show)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < widget.words.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: C.elevated, borderRadius: BorderRadius.circular(8)),
                          child: Text('${i + 1}. ${widget.words[i]}', style: const TextStyle(fontFamily: monoFamily, fontSize: 14)),
                        ),
                    ],
                  )
                else
                  const Text('Escondidas. Quem tiver estas 12 palavras controla todo o saldo.', style: TextStyle(color: C.textSec, fontSize: 14)),
                const SizedBox(height: 12),
                OutlineButton(label: _show ? 'Esconder' : 'Mostrar as 12 palavras', icon: _show ? Icons.visibility_off : Icons.visibility, onPressed: _toggle),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Zona de risco', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .5, color: C.muted)),
          const SizedBox(height: 10),
          OutlineButton(label: 'Apagar carteira', icon: Icons.delete_outline, onPressed: _openDelete),
          const SizedBox(height: 16),
          ValueListenableBuilder<String?>(
            valueListenable: rpcRoute,
            builder: (context, route, _) => route == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      route == 'relay' ? 'Polygon: relay IBIRAPAY' : 'Polygon: nós públicos (relay indisponível)',
                      style: TextStyle(color: route == 'relay' ? C.primaryLight : C.warn, fontSize: 12),
                    ),
                  ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: sparkRoute,
            builder: (context, route, _) => route == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      route == 'relay' ? 'Spark: relay IBIRAPAY' : 'Spark: conexão direta (relay indisponível)',
                      key: const Key('spark-route'),
                      style: TextStyle(color: route == 'relay' ? C.primaryLight : C.warn, fontSize: 12),
                    ),
                  ),
          ),
          Text(widget.version, style: const TextStyle(color: C.muted, fontSize: 12, fontFamily: monoFamily)),
        ],
      ),
    ),
  );
}
