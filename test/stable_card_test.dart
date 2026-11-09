import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/chain_balances.dart';
import 'package:wallet/stable_card.dart';

BigInt _u(int units) => BigInt.from(units);

final _rows = [
  StableBalance('Polygon', 'USDT', _u(1008000)),
  StableBalance('Polygon', 'USDC', _u(1086900)),
  StableBalance('Polygon', 'USDC.e', _u(500000)),
  StableBalance('Solana', 'USDT', _u(1030000)),
  StableBalance('Solana', 'USDC', _u(2284800)),
];

Future<void> _pump(WidgetTester t, List<StableBalance>? rows) => t.pumpWidget(MaterialApp(home: Scaffold(body: StableCard(balances: rows))));

String _text(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  test('stableOn sums per network, folds USDC.e into USDC, and an unread row is unknown, never zero', () {
    expect(stableOn(_rows, 'USDT'), _u(2038000));
    expect(stableOn(_rows, 'USDT', network: 'Polygon'), _u(1008000));
    expect(stableOn(_rows, 'USDC', network: 'Polygon'), _u(1586900));
    expect(stableOn(_rows, 'USDC', network: 'Solana'), _u(2284800));
    final broken = [..._rows, StableBalance('Solana', 'USDT', null)];
    expect(stableOn(broken, 'USDT'), isNull);
    expect(stableOn(broken, 'USDT', network: 'Solana'), isNull);
    expect(stableOn(broken, 'USDT', network: 'Polygon'), _u(1008000));
    expect(stableOn(const [], 'USDT'), BigInt.zero);
  });

  testWidgets('closed by default; a tap on a coin opens its split by network, a second tap closes it', (t) async {
    await _pump(t, _rows);
    expect(find.byKey(const Key('stable-split-USDT')), findsNothing);
    await t.tap(find.byKey(const Key('stable-USDT')));
    await t.pump();
    expect(_text(t, 'stable-USDT-Polygon'), '1,00');
    expect(_text(t, 'stable-USDT-Solana'), '1,03');
    await t.tap(find.byKey(const Key('stable-USDT')));
    await t.pump();
    expect(find.byKey(const Key('stable-split-USDT')), findsNothing);
  });

  testWidgets('opening the other coin swaps the split, and USDC shows the bridged USDC.e inside Polygon', (t) async {
    await _pump(t, _rows);
    await t.tap(find.byKey(const Key('stable-USDT')));
    await t.pump();
    await t.tap(find.byKey(const Key('stable-USDC')));
    await t.pump();
    expect(find.byKey(const Key('stable-split-USDT')), findsNothing);
    expect(_text(t, 'stable-USDC-Polygon'), '1,58');
    expect(_text(t, 'stable-USDC-Solana'), '2,28');
  });

  testWidgets('an unreadable network shows ? on its own row only', (t) async {
    await _pump(t, [..._rows.where((b) => !(b.network == 'Solana' && b.symbol == 'USDT')), StableBalance('Solana', 'USDT', null)]);
    await t.tap(find.byKey(const Key('stable-USDT')));
    await t.pump();
    expect(_text(t, 'stable-USDT-Polygon'), '1,00');
    expect(_text(t, 'stable-USDT-Solana'), '?');
  });

  testWidgets('while nothing is read yet the split says ... and does not crash', (t) async {
    await _pump(t, null);
    await t.tap(find.byKey(const Key('stable-USDC')));
    await t.pump();
    expect(_text(t, 'stable-USDC-Polygon'), '...');
    expect(_text(t, 'stable-USDC-Solana'), '...');
  });

  testWidgets('the split follows a refresh while it is open', (t) async {
    await _pump(t, _rows);
    await t.tap(find.byKey(const Key('stable-USDT')));
    await t.pump();
    await _pump(t, [StableBalance('Polygon', 'USDT', _u(9000000)), StableBalance('Solana', 'USDT', _u(0))]);
    expect(_text(t, 'stable-USDT-Polygon'), '9,00');
    expect(_text(t, 'stable-USDT-Solana'), '0,00');
  });
}
