// An open stablecoin send: signed and possibly on the network, outcome not yet certain. Shown from the home notice. The user can
// check again, copy the explorer link, or discard it once they have looked at the explorer themselves.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pending_sends.dart';
import 'stable_send.dart';
import 'theme.dart';

String pendingExplorer(PendingSend r) => r.net == Net.polygon.name ? 'https://polygonscan.com/tx/${r.id}' : 'https://solscan.io/tx/${r.id}';

String pendingNetName(PendingSend r) => r.net == Net.polygon.name ? 'Polygon' : 'Solana';

String pendingAmount(PendingSend r) => '${fmtUnits(BigInt.parse(r.amount), stableDecimals6)} ${r.symbol}';

/// What the user is told when [o] settles an open send.
String settledText(PendingSend r, Outcome o) => switch (o.result) {
  Result.confirmed => 'Envio de ${pendingAmount(r)}: confirmado',
  Result.reverted => 'Envio de ${pendingAmount(r)}: falhou na rede, os tokens não saíram',
  Result.notSent => 'Envio de ${pendingAmount(r)}: não chegou a entrar na rede, nada foi cobrado',
  Result.pending => 'Envio de ${pendingAmount(r)}: ainda sem confirmação',
};

/// What the user is told when a cancel settles an open send.
String cancelText(PendingSend r, Outcome o) => switch (o.result) {
  Result.notSent => 'Envio de ${pendingAmount(r)} cancelado: não entrou na rede. O cancelamento custou um pouco de POL',
  Result.confirmed => 'Não deu para cancelar: o envio de ${pendingAmount(r)} já tinha entrado e foi confirmado',
  Result.reverted => 'Não deu para cancelar: o envio de ${pendingAmount(r)} já tinha sido executado e falhou na rede, os tokens não saíram',
  Result.pending => 'Envio de ${pendingAmount(r)}: ainda sem confirmação',
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
      if (mounted) Navigator.pop(context, o == null ? 'Envio descartado do registro' : settledText(_r, o));
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
    setState(() => _note = 'Cancelando... pode levar até um minuto e meio. Não feche o aplicativo');
    try {
      final o = await widget.sender.cancelPolygon(_r, widget.words);
      if (!mounted) return;
      if (o == null) {
        setState(() {
          _checking = false;
          _confirmCancel = false;
          _note = 'Cancelamento enviado, mas a rede ainda não o confirmou. Confira de novo em instantes.';
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
        _note = 'Ainda não dá para saber. Confira no explorador.';
      });
      return;
    }
    await widget.sender.store.remove(_r.id);
    if (mounted) Navigator.pop(context, settledText(_r, o));
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SheetTitle('Envio em aberto', Icons.hourglass_top),
      const SizedBox(height: 14),
      Text(
        'Esse envio foi assinado e pode ter entrado na rede, mas ainda não há confirmação. Não envie de novo antes de conferir: pode pagar duas vezes.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: C.warn, fontSize: 13),
      ),
      const SizedBox(height: 14),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RowKV('Valor', pendingAmount(_r)),
            RowKV('Rede', pendingNetName(_r)),
            const Divider(height: 16),
            const Text('Para', style: TextStyle(color: C.textSec, fontSize: 14)),
            const SizedBox(height: 4),
            SelectableText(_r.to, style: const TextStyle(fontFamily: monoFamily, fontSize: 12, color: C.primaryLight)),
            const SizedBox(height: 10),
            const Text('Transação', style: TextStyle(color: C.textSec, fontSize: 14)),
            const SizedBox(height: 4),
            SelectableText(_r.id, style: const TextStyle(fontFamily: monoFamily, fontSize: 12, color: C.primaryLight)),
          ],
        ),
      ),
      if (_note != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_note!, style: const TextStyle(color: C.muted, fontSize: 13))),
      const SizedBox(height: 14),
      GradientButton(label: _checking ? 'Conferindo...' : 'Conferir agora', onPressed: _checking ? null : _check),
      const SizedBox(height: 10),
      OutlineButton(
        label: _copied ? 'Link copiado' : 'Copiar link do explorador',
        icon: Icons.copy,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: pendingExplorer(_r)));
          if (mounted) setState(() => _copied = true);
        },
      ),
      const SizedBox(height: 10),
      if (isStale(_r)) ...[
        Text(
          'Esse envio tem mais de 1 hora e a rede pública já não guarda o histórico dele, então o app não consegue provar que ele não entrou. Antes de descartar, abra o link no $_explorerName (histórico completo): se a transação aparece lá, o envio FOI feito.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.muted, fontSize: 12),
        ),
        TextButton(
          onPressed: _checking ? null : _discard,
          child: Text(
            _confirmDiscard ? 'Toque de novo: conferi no $_explorerName e ele NÃO aparece' : 'Descartar (conferi no $_explorerName)',
            textAlign: TextAlign.center,
            style: TextStyle(color: _confirmDiscard ? C.warn : C.textSec),
          ),
        ),
      ] else if (_polygon) ...[
        const Text(
          'Se ele não aparece no explorador e você quer liberar novos envios, dá para cancelar: o app manda uma transação sua, para você mesmo e sem valor, no lugar dele. Se o envio original já tiver entrado, ele é confirmado normalmente. Custa um pouco de POL.',
          textAlign: TextAlign.center,
          style: TextStyle(color: C.muted, fontSize: 12),
        ),
        TextButton(
          onPressed: _checking ? null : _cancel,
          child: Text(
            _confirmCancel ? 'Toque de novo para cancelar o envio' : 'Cancelar envio',
            textAlign: TextAlign.center,
            style: TextStyle(color: _confirmCancel ? C.warn : C.textSec),
          ),
        ),
      ] else
        const Text(
          'A Solana resolve esse envio sozinha: se ele não tiver entrado até o fim da validade (cerca de 1 a 2 minutos), o app o marca como não enviado.',
          textAlign: TextAlign.center,
          style: TextStyle(color: C.muted, fontSize: 12),
        ),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar', style: TextStyle(color: C.muted))),
    ],
  );
}
