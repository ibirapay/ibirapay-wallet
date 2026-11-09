// The Bitcoin balance on the home screen: the big number is what is spendable now (Lightning and on-chain deposits already claimed
// are the same Spark balance), and a tap opens the one split the SDK really knows: Disponível (spendable now) and Pendente
// (on-chain deposits still waiting for their confirmations or for the SDK to claim them into the balance).
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';

import 'i18n.dart';
import 'theme.dart';

/// Sats sitting in on-chain deposits that are not in the balance yet; null when they could not be read (never a guessed zero).
/// A deposit the SDK marks Claimed stays in the list until the provider spends its output, but its value is already in the
/// balance: counting it would show the same sats twice (as available and as on the way).
BigInt? onchainOnTheWay(List<breez.DepositInfo>? deposits) {
  if (deposits == null) return null;
  var sum = BigInt.zero;
  for (final d in deposits) {
    if (d.instantClaimStatus is breez.InstantClaimStatus_Claimed) continue;
    sum += d.amountSats;
  }
  return sum;
}

class BtcBalance extends StatefulWidget {
  const BtcBalance({super.key, required this.sats, required this.syncing, required this.deposits});
  final int? sats;
  final bool syncing;

  /// Unclaimed on-chain deposits, null while unread or when the read failed.
  final List<breez.DepositInfo>? deposits;
  @override
  State<BtcBalance> createState() => _BtcBalanceState();
}

class _BtcBalanceState extends State<BtcBalance> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final sats = widget.sats;
    final way = onchainOnTheWay(widget.deposits);

    Widget line(String key, String name, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(name, style: const TextStyle(fontSize: 13, color: C.textSec)),
          const Spacer(),
          Text(value, key: Key(key), style: const TextStyle(fontFamily: monoFamily, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );

    return Column(
      children: [
        InkWell(
          key: const Key('btc-balance'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.syncing) ...[
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: C.primaryLight, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                    ],
                    Text(widget.syncing ? tr('btc.syncing') : tr('btc.balance'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 2.4, color: C.muted)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('₿ ', style: TextStyle(fontSize: 30, color: C.textSec.withValues(alpha: .7), fontFamily: monoFamily)),
                    Text(
                      sats == null ? '...' : fmtSats(sats),
                      style: TextStyle(
                        fontFamily: monoFamily,
                        fontSize: 44,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.9,
                        shadows: [Shadow(color: C.primary.withValues(alpha: .5), blurRadius: 40)],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('sats', style: TextStyle(color: C.textSec, fontSize: 14, fontFamily: monoFamily)),
                    Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: C.muted),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            key: const Key('btc-split'),
            padding: const EdgeInsets.fromLTRB(40, 8, 40, 0),
            child: Column(
              children: [
                const Divider(height: 1, color: C.border),
                const SizedBox(height: 6),
                line('btc-available', tr('btc.available'), sats == null ? '...' : fmtSats(sats)),
                line('btc-onchain', tr('btc.pending'), widget.deposits == null ? '?' : fmtSats(way!.toInt())),
              ],
            ),
          ),
      ],
    );
  }
}
