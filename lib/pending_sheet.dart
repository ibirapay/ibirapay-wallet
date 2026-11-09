// An open stablecoin send: signed and possibly on the network, outcome not yet certain. Shown from the home notice. The user can
// check again, copy the explorer link, or discard it once they have looked at the explorer themselves.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n.dart';
import 'pending_sends.dart';
import 'stable_send.dart';
import 'theme.dart';

String pendingExplorer(PendingSend r) => r.net == Net.polygon.name ? 'https://polygonscan.com/tx/${r.id}' : 'https://solscan.io/tx/${r.id}';

String pendingNetName(PendingSend r) => r.net == Net.polygon.name ? 'Polygon' : 'Solana';

String pendingAmount(PendingSend r) => '${fmtUnits(BigInt.parse(r.amount), stableDecimals6)} ${r.symbol}';

/// What the user is told when [o] settles an open send.
String settledText(PendingSend r, Outcome o) => switch (o.result) {
  Result.confirmed => tr('pend.confirmed', {'amount': pendingAmount(r)}),
  Result.reverted => tr('pend.reverted', {'amount': pendingAmount(r)}),
  Result.notSent => tr('pend.notSent', {'amount': pendingAmount(r)}),
  Result.pending => tr('pend.pending', {'amount': pendingAmount(r)}),
};

/// What the user is told when a cancel settles an open send.
String cancelText(PendingSend r, Outcome o) => switch (o.result) {
  Result.notSent => tr('pend.cancelled', {'amount': pendingAmount(r)}),
  Result.confirmed => tr('pend.cancelTooLateOk', {'amount': pendingAmount(r)}),
  Result.reverted => tr('pend.cancelTooLateFail', {'amount': pendingAmount(r)}),
  Result.pending => tr('pend.pending', {'amount': pendingAmount(r)}),
};

class PendingSheet extends StatefulWidget {
  const PendingSheet({super.key, required this.record, required this.sender, required this.words, required this.confirmPin});
  final PendingSend record;
  final StableSender sender;

  /// To sign the cancelling transaction; nothing else here needs them.
  final List<String> words;

  /// The PIN, asked right before the cancelling transaction is signed: it moves POL like any send.
  final Future<bool> Function() confirmPin;
  @override
  State<PendingSheet> createState() => _PendingSheetState();
}

class _PendingSheetState extends State<PendingSheet> {
  bool _checking = false;
  bool _confirmCancel = false;
  bool _confirmDiscard = false;
  bool _copied = false;
  String? _note;

  PendingSend get _r => widget.record;
  bool get _polygon => _r.net == Net.polygon.name;
  String get _explorerName => _polygon ? 'Polygonscan' : 'Solscan';

  /// The only clearing on the user's word: a send over an hour old that the public nodes can no longer vouch for. Within the hour an
  /// explorer can still lag, so there is no such button.
  Future<void> _discard() async {
    if (!_confirmDiscard) {
      setState(() => _confirmDiscard = true);
      return;
    }
    try {
      final o = await widget.sender.discardStale(_r);
      if (mounted) Navigator.pop(context, o == null ? tr('pend.discarded') : settledText(_r, o));
    } on SendError catch (e) {
      if (mounted) {
        setState(() {
          _confirmDiscard = false;
          _note = e.message;
        });
      }
    }
  }

  /// Every other record is only ever cleared by the chain's own proof: an explorer can lag.
  Future<void> _cancel() async {
    if (!_confirmCancel) {
      setState(() => _confirmCancel = true);
      return;
    }
    setState(() => _checking = true);
    if (!await widget.confirmPin()) {
      if (mounted) {
        setState(() {
          _checking = false;
          _confirmCancel = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _note = tr('pend.cancelling'));
    try {
      final o = await widget.sender.cancelPolygon(_r, widget.words);
      if (!mounted) return;
      if (o == null) {
        setState(() {
          _checking = false;
          _confirmCancel = false;
          _note = tr('pend.cancelUnconfirmed');
        });
        return;
      }
      await widget.sender.store.remove(_r.id);
      if (mounted) Navigator.pop(context, cancelText(_r, o));
    } on SendError catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _confirmCancel = false;
          _note = e.message;
        });
      }
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _note = null;
    });
    final o = await widget.sender.reconcile(_r);
    if (!mounted) return;
    if (o == null) {
      setState(() {
        _checking = false;
        _note = tr('pend.cannotTell');
      });
      return;
    }
    await widget.sender.store.remove(_r.id);
    if (mounted) Navigator.pop(context, settledText(_r, o));
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SheetTitle(tr('pend.title'), Icons.hourglass_top),
      const SizedBox(height: 14),
      Text(
        tr('pend.body'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: C.warn, fontSize: 13),
      ),
      const SizedBox(height: 14),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RowKV(tr('common.amount'), pendingAmount(_r)),
            RowKV(tr('pend.network'), pendingNetName(_r)),
            const Divider(height: 16),
            Text(tr('common.to'), style: const TextStyle(color: C.textSec, fontSize: 14)),
            const SizedBox(height: 4),
            SelectableText(_r.to, style: const TextStyle(fontFamily: monoFamily, fontSize: 12, color: C.primaryLight)),
            const SizedBox(height: 10),
            Text(tr('pend.transaction'), style: const TextStyle(color: C.textSec, fontSize: 14)),
            const SizedBox(height: 4),
            SelectableText(_r.id, style: const TextStyle(fontFamily: monoFamily, fontSize: 12, color: C.primaryLight)),
          ],
        ),
      ),
      if (_note != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_note!, style: const TextStyle(color: C.muted, fontSize: 13))),
      const SizedBox(height: 14),
      GradientButton(label: _checking ? tr('pend.checking') : tr('pend.checkNow'), onPressed: _checking ? null : _check),
      const SizedBox(height: 10),
      OutlineButton(
        label: _copied ? tr('sts.linkCopied') : tr('sts.copyLink'),
        icon: Icons.copy,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: pendingExplorer(_r)));
          if (mounted) setState(() => _copied = true);
        },
      ),
      const SizedBox(height: 10),
      if (isStale(_r)) ...[
        Text(
          tr('pend.staleNote', {'explorer': _explorerName}),
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.muted, fontSize: 12),
        ),
        TextButton(
          onPressed: _checking ? null : _discard,
          child: Text(
            _confirmDiscard ? tr('pend.discardAgain', {'explorer': _explorerName}) : tr('pend.discardCheck', {'explorer': _explorerName}),
            textAlign: TextAlign.center,
            style: TextStyle(color: _confirmDiscard ? C.warn : C.textSec),
          ),
        ),
      ] else if (_polygon) ...[
        Text(
          tr('pend.cancelNote'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.muted, fontSize: 12),
        ),
        TextButton(
          onPressed: _checking ? null : _cancel,
          child: Text(
            _confirmCancel ? tr('pend.cancelAgain') : tr('pend.cancelSend'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _confirmCancel ? C.warn : C.textSec),
          ),
        ),
      ] else
        Text(
          tr('pend.solanaNote'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.muted, fontSize: 12),
        ),
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('common.close'), style: const TextStyle(color: C.muted))),
    ],
  );
}
