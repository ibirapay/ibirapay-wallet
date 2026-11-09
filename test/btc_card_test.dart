import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/btc_card.dart';
import 'package:wallet/theme.dart' show fmtSats;

breez.DepositInfo _dep(int sats, {breez.InstantClaimStatus? status}) =>
    breez.DepositInfo(txid: 'ab' * 32, vout: 0, amountSats: BigInt.from(sats), isMature: false, instantClaimStatus: status);

Future<void> _pump(WidgetTester t, {int? sats, List<breez.DepositInfo>? deposits}) =>
    t.pumpWidget(MaterialApp(home: Scaffold(body: BtcBalance(sats: sats, syncing: false, deposits: deposits))));

String _text(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  test('onchainOnTheWay sums the deposits, none is zero, and an unread list is unknown, never zero', () {
    expect(onchainOnTheWay([_dep(1000), _dep(250)]), BigInt.from(1250));
    expect(onchainOnTheWay(const []), BigInt.zero);
    expect(onchainOnTheWay(null), isNull);
  });

  test('a deposit the SDK says is Claimed is already in the balance and is not counted again; declined and submitted ones are still on the way', () {
    expect(onchainOnTheWay([_dep(1000, status: const breez.InstantClaimStatus.claimed())]), BigInt.zero);
    expect(onchainOnTheWay([_dep(1000, status: const breez.InstantClaimStatus.claimed()), _dep(250)]), BigInt.from(250));
    expect(onchainOnTheWay([_dep(300, status: const breez.InstantClaimStatus.declined(confirmations: 1)), _dep(200, status: const breez.InstantClaimStatus.submitted(claimId: 'c'))]), BigInt.from(500));
  });

  testWidgets('the split is closed until the balance is tapped, and a second tap closes it', (t) async {
    await _pump(t, sats: 1500000, deposits: [_dep(40000)]);
    expect(find.byKey(const Key('btc-split')), findsNothing);
    await t.tap(find.byKey(const Key('btc-balance')));
    await t.pump();
    expect(find.byKey(const Key('btc-split')), findsOneWidget);
    await t.tap(find.byKey(const Key('btc-balance')));
    await t.pump();
    expect(find.byKey(const Key('btc-split')), findsNothing);
  });

  testWidgets('open: Disponível is the balance and Pendente is the sum of the deposits on the way', (t) async {
    await _pump(t, sats: 1500000, deposits: [_dep(40000), _dep(2500)]);
    await t.tap(find.byKey(const Key('btc-balance')));
    await t.pump();
    expect(find.text('Disponível'), findsOneWidget);
    expect(find.text('Pendente'), findsOneWidget);
    expect(_text(t, 'btc-available'), fmtSats(1500000));
    expect(_text(t, 'btc-onchain'), fmtSats(42500));
  });

  testWidgets('no deposits shows 0, and a deposit list that could not be read shows ?', (t) async {
    await _pump(t, sats: 10, deposits: const []);
    await t.tap(find.byKey(const Key('btc-balance')));
    await t.pump();
    expect(_text(t, 'btc-onchain'), '0');
    await _pump(t, sats: 10, deposits: null);
    expect(_text(t, 'btc-onchain'), '?');
  });

  testWidgets('while the balance is unread the available line says ... and no number is invented', (t) async {
    await _pump(t, sats: null, deposits: const []);
    await t.tap(find.byKey(const Key('btc-balance')));
    await t.pump();
    expect(_text(t, 'btc-available'), '...');
  });
}
