// The confirmation before the wallet is deleted from this device: what is cut off, the 12 words on paper, the word APAGAR, and the PIN
// (not on the lock screen, where the PIN is what was forgotten). The wipe itself is [WalletOps.wipe].
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'i18n.dart';
import 'pending_sends.dart';
import 'stable_send.dart' show fmtUnits, isStale;
import 'theme.dart';
import 'wipe.dart';

class DeleteWalletView extends StatefulWidget {
  const DeleteWalletView({super.key, required this.ops, required this.onWiped, required this.onBack, this.balances, this.confirmPin});
  final WalletOps ops;

  /// Runs after the wipe: the app goes back to the welcome screen.
  final VoidCallback onWiped;
  final VoidCallback onBack;

  /// What is on the wallet now ("12 345 sats", "USDT 4,50"), live: lines saying "carregando..." fill in as the balances arrive. Null when
  /// the app is locked and does not know.
  final ValueListenable<List<String>>? balances;

  /// Asks the PIN; null on the lock screen ("Esqueci o PIN"), where there is none to ask.
  final Future<bool> Function()? confirmPin;
  @override
  State<DeleteWalletView> createState() => _DeleteWalletViewState();
}

class _DeleteWalletViewState extends State<DeleteWalletView> {
  final _typed = TextEditingController();
  bool _wrote = false;
  bool _acknowledged = false;
  bool _busy = false;
  String? _error;
  String? _openSend;
  List<PendingSend> _old = const [];

  /// On the lock screen there is no way to open the app and deal with old open sends, so there they are shown and acknowledged instead.
  bool get _lockScreen => widget.confirmPin == null;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {})); // the button follows what is in the field, however it got there (typing, paste, autofill)
    widget.ops.openSends().then((all) {
      if (!mounted || all.isEmpty) return;
      final recent = all.any((r) => !isStale(r));
      setState(() {
        if (recent) {
          _openSend = tr('del.openSend');
        } else if (_lockScreen) {
          _old = all; // shown below, and acknowledged
        } else {
          _openSend = tr('del.oldSends');
        }
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _ready => _wrote && (_old.isEmpty || _acknowledged) && _typed.text.trim().toUpperCase() == tr('del.word') && !_busy && _openSend == null;

  Future<void> _delete() async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ask = widget.confirmPin;
      if (ask != null && !await ask()) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await widget.ops.wipe(acknowledgedOldSends: _lockScreen && _acknowledged);
      if (mounted) widget.onWiped();
    } on WipeRefused catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('del.fail', {'e': e});
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [IconButton(onPressed: _busy ? null : widget.onBack, icon: const Icon(Icons.arrow_back))]),
        const SizedBox(height: 4),
        Text(tr('del.title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Panel(
          child: Text(
            tr('del.warn'),
            style: const TextStyle(color: C.warn, fontSize: 14),
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('del.loses'), style: const TextStyle(color: C.textSec, fontSize: 13)),
              const SizedBox(height: 6),
              if (widget.balances == null)
                Text(tr('del.locked'), style: const TextStyle(fontSize: 14))
              else
                ValueListenableBuilder<List<String>>(
                  valueListenable: widget.balances!,
                  builder: (context, lines, _) => lines.isEmpty
                      ? Text(tr('del.noBalance'), style: const TextStyle(fontSize: 14))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final l in lines) Text(l, style: const TextStyle(fontFamily: monoFamily, fontSize: 15, fontWeight: FontWeight.w600)),
                            if (lines.any(isLoadingLine))
                              Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('del.loadingNote'), style: const TextStyle(color: C.muted, fontSize: 12))),
                          ],
                        ),
                ),
            ],
          ),
        ),
        if (_old.isNotEmpty) ...[
          const SizedBox(height: 12),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('del.unanswered'), style: const TextStyle(color: C.warn, fontSize: 13)),
                const SizedBox(height: 8),
                for (final r in _old) ...[
                  Text('${r.net == 'polygon' ? 'Polygon' : 'Solana'}: ${fmtUnits(BigInt.parse(r.amount), 6)} ${r.symbol}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  SelectableText(r.id, style: const TextStyle(fontFamily: monoFamily, fontSize: 11, color: C.primaryLight)),
                  const SizedBox(height: 6),
                ],
                Text(tr('del.noteCodes'), style: const TextStyle(color: C.textSec, fontSize: 12)),
              ],
            ),
          ),
          CheckboxListTile(
            value: _acknowledged,
            onChanged: _busy ? null : (v) => setState(() => _acknowledged = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: C.primaryLight,
            title: Text(tr('del.checkSends'), style: const TextStyle(fontSize: 14)),
          ),
        ],
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _wrote,
          onChanged: _busy ? null : (v) => setState(() => _wrote = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: C.primaryLight,
          title: Text(tr('del.wrote'), style: const TextStyle(fontSize: 14)),
        ),
        TextField(
          controller: _typed,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: tr('del.hint', {'word': tr('del.word')})),
        ),
        if (_openSend != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_openSend!, style: const TextStyle(color: C.warn, fontSize: 13))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: C.warn, fontSize: 13))),
        const SizedBox(height: 16),
        GradientButton(
          label: _busy ? tr('del.busy') : tr('del.title'),
          colors: const [C.warn, Color(0xFFB45309)],
          onPressed: _ready ? _delete : null,
        ),
      ],
    );
  }
}
