// Receive flow: amount -> invoice QR. While the QR is up it polls for the payment and pops with the received sats.
import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'limits.dart';
import 'onchain.dart';
import 'theme.dart';

class ReceiveSheet extends StatefulWidget {
  const ReceiveSheet({super.key, required this.sdk});
  final breez.BreezSdk sdk;
  @override
  State<ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<ReceiveSheet> {
  final _amount = TextEditingController();
  String? _invoice;
  int _sats = 0;
  String? _error;
  bool _working = false;
  bool _copied = false;
  bool _onchain = false;
  Set<String> _seen = {};
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    _amount.dispose();
    super.dispose();
  }

  Future<List<breez.Payment>> _received() async => (await widget.sdk.listPayments(
    request: const breez.ListPaymentsRequest(typeFilter: [breez.PaymentType.receive], limit: 20),
  )).payments;

  Future<void> _create() async {
    final sats = int.tryParse(_amount.text.trim());
    final bad = satsError(sats);
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    if (sats == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      _seen = (await _received()).map((p) => p.id).toSet();
      final r = await widget.sdk.receivePayment(
        request: breez.ReceivePaymentRequest(
          paymentMethod: breez.ReceivePaymentMethod.bolt11Invoice(
            description: 'IBIRAPAY Carteira',
            amountSats: BigInt.from(sats),
            expirySecs: 3600,
          ),
        ),
      );
      setState(() {
        _invoice = r.paymentRequest;
        _sats = sats;
      });
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } catch (e) {
      setState(() => _error = 'Erro ao criar a fatura: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _check() async {
    try {
      final fresh = (await _received()).where((p) => !_seen.contains(p.id) && p.status == breez.PaymentStatus.completed);
      if (fresh.isNotEmpty && mounted) {
        _poll?.cancel();
        Navigator.pop(context, fresh.first.amount.toInt());
      }
    } catch (_) {
      // transient sync error: the next tick retries
    }
  }

  Widget _modeSwitch() => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(value: false, label: Text('Lightning'), icon: Icon(Icons.bolt)),
      ButtonSegment(value: true, label: Text('Bitcoin'), icon: Icon(Icons.link)),
    ],
    selected: {_onchain},
    onSelectionChanged: (v) => setState(() => _onchain = v.first),
  );

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;
    if (inv == null && _onchain) {
      return Column(
        children: [
          const SheetTitle('Receber', Icons.arrow_downward),
          const SizedBox(height: 12),
          _modeSwitch(),
          const SizedBox(height: 16),
          OnchainReceiveView(api: OnchainApi.fromSdk(widget.sdk), onReceived: (sats) => Navigator.pop(context, sats)),
        ],
      );
    }
    if (inv == null) {
      return Column(
        children: [
          const SheetTitle('Receber', Icons.arrow_downward),
          const SizedBox(height: 12),
          _modeSwitch(),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontFamily: monoFamily, fontSize: 24, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(hintText: 'Valor', suffixText: 'sats'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final v in const [500, 1000, 2500, 5000])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: OutlinedButton(
                      onPressed: () => setState(() => _amount.text = '$v'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: C.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(fmtSats(v), style: const TextStyle(fontFamily: monoFamily, fontSize: 13)),
                    ),
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Pagamentos abaixo de $minPaymentSats sats não são aceitos pela rede.', style: TextStyle(color: C.muted, fontSize: 12)),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: C.warn, fontSize: 13))),
          const SizedBox(height: 16),
          GradientButton(
            label: _working ? 'Criando...' : 'Criar fatura',
            colors: const [C.success, Color(0xFF059669)],
            onPressed: _working ? null : _create,
          ),
        ],
      );
    }
    return Column(
      children: [
        const SheetTitle('Escaneie para pagar', Icons.arrow_downward),
        const SizedBox(height: 8),
        Text('${fmtSats(_sats)} sats', style: const TextStyle(fontFamily: monoFamily, fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: QrImageView(data: inv.toUpperCase(), size: 220, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 14),
        Text(
          '${inv.substring(0, 12)}...${inv.substring(inv.length - 12)}',
          style: const TextStyle(fontFamily: monoFamily, fontSize: 12, color: C.primaryLight),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: GradientButton(
                label: _copied ? 'Copiado!' : 'Copiar',
                icon: Icons.copy,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: inv));
                  setState(() => _copied = true);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: C.primaryLight)),
            SizedBox(width: 8),
            Text('Aguardando o pagamento...', style: TextStyle(color: C.muted, fontSize: 13)),
          ],
        ),
      ],
    );
  }
}
