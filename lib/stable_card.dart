// The USDT / USDC card on the home screen: one total per coin, and a tap on it opens that coin's split by network.
import 'package:flutter/material.dart';

import 'chain_balances.dart';
import 'theme.dart';

/// What [symbol] holds on [network]: null when any row of it is unread (a node did not answer), never a guessed zero.
/// The bridged USDC.e counts as USDC.
BigInt? stableOn(List<StableBalance> rows, String symbol, {String? network}) {
  var sum = BigInt.zero;
  for (final b in rows) {
    if (b.symbol != symbol && !(symbol == 'USDC' && b.symbol == 'USDC.e')) continue;
    if (network != null && b.network != network) continue;
    if (b.raw == null) return null;
    sum += b.raw!;
  }
  return sum;
}

/// USDT and USDC under the sats balance, summed over Polygon and Solana; '...' while unread. Tap a coin for its networks.
class StableCard extends StatefulWidget {
  const StableCard({super.key, required this.balances});
  final List<StableBalance>? balances;
  @override
  State<StableCard> createState() => _StableCardState();
}

class _StableCardState extends State<StableCard> {
  static const _networks = [('Polygon', 'polygon'), ('Solana', 'solana')];
  String? _open;

  @override
  Widget build(BuildContext context) {
    final rows = widget.balances;
    String show(BigInt? v) => v == null ? '...' : StableBalance('', '', v).text;

    Widget cell(String symbol) {
      final open = _open == symbol;
      return Expanded(
        child: InkWell(
          key: Key('stable-$symbol'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open = open ? null : symbol),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/icons/${symbol.toLowerCase()}.png', width: 22, height: 22),
                  const SizedBox(width: 8),
                  Text(symbol, style: const TextStyle(fontSize: 13, color: C.textSec)),
                  const SizedBox(width: 8),
                  Text(show(rows == null ? null : stableOn(rows, symbol)), style: const TextStyle(fontFamily: monoFamily, fontSize: 16, fontWeight: FontWeight.w600)),
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: C.muted),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget split(String symbol) => Padding(
      key: Key('stable-split-$symbol'),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
      child: Column(
        children: [
          const Divider(height: 1, color: C.border),
          const SizedBox(height: 8),
          for (final (net, icon) in _networks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Image.asset('assets/icons/$icon.png', width: 18, height: 18),
                  const SizedBox(width: 8),
                  Text(net, style: const TextStyle(fontSize: 13, color: C.textSec)),
                  const Spacer(),
                  Text(
                    rows == null ? '...' : (stableOn(rows, symbol, network: net) == null ? '?' : show(stableOn(rows, symbol, network: net))),
                    key: Key('stable-$symbol-$net'),
                    style: const TextStyle(fontFamily: monoFamily, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Panel(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          children: [
            Row(children: [cell('USDT'), Container(width: 1, height: 24, color: C.border), cell('USDC')]),
            if (_open != null) split(_open!),
          ],
        ),
      ),
    );
  }
}
