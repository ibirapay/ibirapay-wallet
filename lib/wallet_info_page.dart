// Carteira: the 12 words (behind a reveal), the Polygon and Solana addresses, build version.
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'chain_balances.dart' show rpcRoute;
import 'spark.dart' show sparkRoute;
import 'delete_wallet_view.dart';
import 'i18n.dart';
import 'theme.dart';
import 'wallet.dart';
import 'wipe.dart';

class WalletInfoPage extends StatefulWidget {
  const WalletInfoPage({super.key, required this.wallet, required this.words, required this.version, required this.lock, required this.ops, required this.balanceLines, this.langPrefs});
  final DerivedWallet wallet;
  final List<String> words;
  final String version;
  final AppLock lock;
  final WalletOps ops;
  final ValueListenable<List<String>> balanceLines;

  /// Where the language choice is saved (tests give a temp folder).
  final LangPrefs? langPrefs;
  @override
  State<WalletInfoPage> createState() => _WalletInfoPageState();
}

class _WalletInfoPageState extends State<WalletInfoPage> {
  bool _show = false;

  Future<void> _pickLang(Lang l) async {
    setLang(l);
    try {
      await (widget.langPrefs ?? LangPrefs()).save(l);
    } catch (_) {
      // not saved: the choice holds until the app is closed, and the next start follows the phone again
    }
  }

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
    if (!_show && !await widget.lock.confirm(context, reason: tr('info.confirmWords'))) return;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('info.noCapture'))));
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('info.copied'))));
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
        appBar: AppBar(title: Text(tr('del.title')), backgroundColor: C.surface, automaticallyImplyLeading: false),
        body: Backdrop(
          child: SafeArea(
            child: DeleteWalletView(
              ops: widget.ops,
              balances: widget.balanceLines,
              onBack: () => Navigator.pop(ctx),
              confirmPin: () => widget.lock.confirm(ctx, reason: tr('info.confirmDelete')),
              onWiped: widget.lock.walletWiped, // the Gate goes back to the welcome screen and clears the pages above it
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('info.title')), backgroundColor: C.surface),
    body: Backdrop(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('lang.title'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .5, color: C.muted)),
          const SizedBox(height: 10),
          ValueListenableBuilder<Lang>(
            valueListenable: lang,
            builder: (context, current, _) => SegmentedButton<Lang>(
              segments: [for (final l in Lang.values) ButtonSegment(value: l, label: Text(l.label, key: Key('lang-${l.name}')))],
              selected: {current},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _pickLang(s.first),
            ),
          ),
          const SizedBox(height: 20),
          Text(tr('info.addresses'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .5, color: C.muted)),
          const SizedBox(height: 10),
          _addr('Polygon', widget.wallet.polygon),
          _addr('Solana', widget.wallet.solana),
          const SizedBox(height: 12),
          Text(tr('info.words'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .5, color: C.muted)),
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
                  Text(tr('info.hidden'), style: const TextStyle(color: C.textSec, fontSize: 14)),
                const SizedBox(height: 12),
                OutlineButton(label: _show ? tr('info.hide') : tr('info.show'), icon: _show ? Icons.visibility_off : Icons.visibility, onPressed: _toggle),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(tr('info.risk'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .5, color: C.muted)),
          const SizedBox(height: 10),
          OutlineButton(label: tr('del.title'), icon: Icons.delete_outline, onPressed: _openDelete),
          const SizedBox(height: 16),
          ValueListenableBuilder<String?>(
            valueListenable: rpcRoute,
            builder: (context, route, _) => route == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      route == 'relay' ? 'Polygon: relay IBIRAPAY' : tr('info.polyFallback'),
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
                      route == 'relay' ? 'Spark: relay IBIRAPAY' : tr('info.sparkFallback'),
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
