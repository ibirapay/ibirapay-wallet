// Receive USDT or USDC: pick the network, show the wallet address as a QR with the network warning.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'theme.dart';

// Bitcoin's own brand orange, for its icon only (not a design default, see theme.dart).
const _btcOrange = Color(0xFFF7931A);

class StableReceive extends StatelessWidget {
  const StableReceive({super.key, required this.network, required this.address});
  final String network; // 'Polygon' | 'Solana'
  final String address;

  @override
  Widget build(BuildContext context) {
    final poly = network == 'Polygon';
    return Column(
      children: [
        SheetTitle('Receber USDT ou USDC', Icons.arrow_downward),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icons/${poly ? 'polygon' : 'solana'}.png', width: 22, height: 22),
            const SizedBox(width: 8),
            Text('Rede $network', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: QrImageView(data: address, size: 220, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 14),
        SelectableText(address, textAlign: TextAlign.center, style: const TextStyle(fontFamily: monoFamily, fontSize: 12, color: C.primaryLight)),
        const SizedBox(height: 14),
        GradientButton(
          label: 'Copiar endereço',
          icon: Icons.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: address));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Endereço copiado')));
          },
        ),
        const SizedBox(height: 14),
        Panel(
          child: Text(
            poly
                ? 'Envie somente USDT ou USDC pela rede Polygon. Tokens enviados por outra rede ficam perdidos. O mesmo endereço recebe os dois.'
                : 'Envie somente USDT ou USDC pela rede Solana. Tokens enviados por outra rede ficam perdidos. O mesmo endereço recebe os dois.',
            style: const TextStyle(color: C.warn, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// The two-network picker used by the Receber chooser.
class _NetTile extends StatelessWidget {
  const _NetTile(this.icon, this.title, this.subtitle, this.onTap);
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: C.dark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: C.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: C.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

/// What Receber offers: Lightning, or one of the two stablecoin networks. Pops with 'ln', 'Polygon' or 'Solana'.
class ReceiveChooser extends StatelessWidget {
  const ReceiveChooser({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SheetTitle('Receber', Icons.arrow_downward),
      const SizedBox(height: 18),
      _NetTile(const Icon(Icons.currency_bitcoin, color: _btcOrange, size: 30), 'Bitcoin', 'Fatura Lightning (cai na hora) ou endereço on-chain', () => Navigator.pop(context, 'ln')),
      _NetTile(Image.asset('assets/icons/polygon.png', width: 30, height: 30), 'USDT ou USDC na Polygon', 'Endereço para receber dólar digital', () => Navigator.pop(context, 'Polygon')),
      _NetTile(Image.asset('assets/icons/solana.png', width: 30, height: 30), 'USDT ou USDC na Solana', 'Endereço para receber dólar digital', () => Navigator.pop(context, 'Solana')),
    ],
  );
}

/// What Enviar offers: Lightning, or one of the two stablecoin networks. Pops with 'ln', 'Polygon' or 'Solana'.
class SendChooser extends StatelessWidget {
  const SendChooser({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SheetTitle('Enviar', Icons.arrow_upward),
      const SizedBox(height: 18),
      _NetTile(const Icon(Icons.currency_bitcoin, color: _btcOrange, size: 30), 'Bitcoin', 'Fatura ou voucher Lightning, ou endereço on-chain', () => Navigator.pop(context, 'ln')),
      _NetTile(Image.asset('assets/icons/polygon.png', width: 30, height: 30), 'USDT ou USDC na Polygon', 'Você paga o gás em POL', () => Navigator.pop(context, 'Polygon')),
      _NetTile(Image.asset('assets/icons/solana.png', width: 30, height: 30), 'USDT ou USDC na Solana', 'Você paga a taxa em SOL', () => Navigator.pop(context, 'Solana')),
    ],
  );
}
