// Receive USDT or USDC: pick the network, show the wallet address as a QR with the network warning.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'i18n.dart';
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
        SheetTitle(tr('ss.receiveTitle'), Icons.arrow_downward),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icons/${poly ? 'polygon' : 'solana'}.png', width: 22, height: 22),
            const SizedBox(width: 8),
            Text(tr('ss.network', {'net': network}), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
          label: tr('ss.copyAddress'),
          icon: Icons.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: address));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ss.addressCopied'))));
          },
        ),
        const SizedBox(height: 14),
        Panel(
          child: Text(
            poly
                ? tr('ss.onlyOn', {'net': 'Polygon'})
                : tr('ss.onlyOn', {'net': 'Solana'}),
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
      SheetTitle(tr('recv.title'), Icons.arrow_downward),
      const SizedBox(height: 18),
      _NetTile(const Icon(Icons.currency_bitcoin, color: _btcOrange, size: 30), 'Bitcoin', tr('ss.btcReceive'), () => Navigator.pop(context, 'ln')),
      _NetTile(Image.asset('assets/icons/polygon.png', width: 30, height: 30), tr('ss.stableOn', {'net': 'Polygon'}), tr('ss.dollarAddress'), () => Navigator.pop(context, 'Polygon')),
      _NetTile(Image.asset('assets/icons/solana.png', width: 30, height: 30), tr('ss.stableOn', {'net': 'Solana'}), tr('ss.dollarAddress'), () => Navigator.pop(context, 'Solana')),
    ],
  );
}

/// What Enviar offers: Lightning, or one of the two stablecoin networks. Pops with 'ln', 'Polygon' or 'Solana'.
class SendChooser extends StatelessWidget {
  const SendChooser({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SheetTitle(tr('btn.send'), Icons.arrow_upward),
      const SizedBox(height: 18),
      _NetTile(const Icon(Icons.currency_bitcoin, color: _btcOrange, size: 30), 'Bitcoin', tr('ss.btcSend'), () => Navigator.pop(context, 'ln')),
      _NetTile(Image.asset('assets/icons/polygon.png', width: 30, height: 30), tr('ss.stableOn', {'net': 'Polygon'}), tr('ss.gasPol'), () => Navigator.pop(context, 'Polygon')),
      _NetTile(Image.asset('assets/icons/solana.png', width: 30, height: 30), tr('ss.stableOn', {'net': 'Solana'}), tr('ss.feeSol'), () => Navigator.pop(context, 'Solana')),
    ],
  );
}
