import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/delete_wallet_view.dart';
import 'package:wallet/pending_sends.dart';
import 'package:wallet/theme.dart';
import 'package:wallet/wallet.dart' show walletWordsKey;
import 'package:wallet/wipe.dart';

import 'memory_secret_store.dart';

class _World {
  _World() {
    store.map[walletWordsKey] = 'a b c';
    ops = WalletOps(store: store, pins: pins, pending: pending, closeSpark: () async => log.add('close'), deleteSparkData: () async => log.add('delete-spark'));
  }
  final store = MemorySecretStore();
  late final pins = testPins(store);
  final pending = MemoryPendingStore();
  final log = <String>[];
  late final WalletOps ops;
  var wiped = 0;
  var back = 0;
}

Future<void> _pump(WidgetTester t, _World w, {List<String>? lines = const ['12 345 sats', 'USDT 4,50'], Future<bool> Function()? pin, bool forgot = false}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: DeleteWalletView(ops: w.ops, balances: forgot ? null : ValueNotifier(lines ?? const <String>[]), confirmPin: forgot ? null : pin, onWiped: () => w.wiped++, onBack: () => w.back++),
      ),
    ),
  );
  await t.pump();
}

GradientButton _button(WidgetTester t) => t.widget<GradientButton>(find.widgetWithText(GradientButton, 'Apagar carteira'));

Future<void> _confirmAll(WidgetTester t, {String word = 'APAGAR'}) async {
  await t.tap(find.byType(CheckboxListTile));
  await t.pump();
  await t.enterText(find.byType(TextField), word);
  await t.pump();
}

void main() {
  testWidgets('shows what is cut off, and the button stays off until the tick AND the word', (t) async {
    final w = _World();
    await _pump(t, w, pin: () async => true);
    expect(find.text('12 345 sats'), findsOneWidget);
    expect(find.text('USDT 4,50'), findsOneWidget);
    expect(_button(t).onPressed, isNull);
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    expect(_button(t).onPressed, isNull); // tick alone is not enough
    await t.enterText(find.byType(TextField), 'APAGA');
    await t.pump();
    expect(_button(t).onPressed, isNull);
    await t.enterText(find.byType(TextField), 'apagar');
    await t.pump();
    expect(_button(t).onPressed, isNotNull); // the word, in any case
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    expect(_button(t).onPressed, isNull); // untick turns it off again
  });

  testWidgets('opened while the balances are still loading, it says so and FILLS IN by itself when they arrive (the v8 screenshot)', (t) async {
    final w = _World();
    final live = ValueNotifier<List<String>>(const ['sats: carregando...', 'USDT: carregando...', 'USDC: carregando...']);
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: appTheme(), home: Scaffold(body: DeleteWalletView(ops: w.ops, balances: live, confirmPin: () async => true, onWiped: () {}, onBack: () {}))));
    await t.pump();
    expect(find.text('sats: carregando...'), findsOneWidget);
    expect(find.textContaining('ainda está carregando'), findsOneWidget);
    live.value = const ['12 345 sats', 'USDT 4,50'];
    await t.pump();
    expect(find.text('sats: carregando...'), findsNothing);
    expect(find.text('12 345 sats'), findsOneWidget);
    expect(find.text('USDT 4,50'), findsOneWidget);
    expect(find.textContaining('ainda está carregando'), findsNothing); // the note goes with the loading lines
  });

  testWidgets('with no balance it says so; on the lock screen it says the balance is not known', (t) async {
    await _pump(t, _World(), lines: const [], pin: () async => true);
    expect(find.text('Nenhum saldo.'), findsOneWidget);
    await _pump(t, _World(), forgot: true);
    expect(find.textContaining('bloqueado'), findsOneWidget);
  });

  testWidgets('the PIN is asked first: refused or cancelled wipes NOTHING; accepted wipes and reports', (t) async {
    final w = _World();
    var allow = false;
    var asked = 0;
    await _pump(t, w, pin: () async {
      asked++;
      return allow;
    });
    await _confirmAll(t);
    await t.tap(find.widgetWithText(GradientButton, 'Apagar carteira'));
    await t.pump();
    await t.pump();
    expect(asked, 1);
    expect(w.log, isEmpty);
    expect(w.store.map.containsKey(walletWordsKey), isTrue);
    expect(w.wiped, 0);
    allow = true;
    await t.tap(find.widgetWithText(GradientButton, 'Apagar carteira'));
    await t.pump();
    await t.pump();
    expect(w.log, ['close', 'delete-spark']);
    expect(w.store.map.containsKey(walletWordsKey), isFalse);
    expect(w.wiped, 1);
  });

  testWidgets('on the lock screen (forgot PIN) there is no PIN to ask: it wipes after the tick and the word', (t) async {
    final w = _World();
    await _pump(t, w, forgot: true);
    await _confirmAll(t);
    await t.tap(find.widgetWithText(GradientButton, 'Apagar carteira'));
    await t.pump();
    await t.pump();
    expect(w.wiped, 1);
    expect(w.store.map.containsKey(walletWordsKey), isFalse);
  });

  testWidgets('a send still open (under an hour) blocks it, with the reason, and nothing is wiped', (t) async {
    final w = _World();
    w.pending.items.add(PendingSend(id: 'x', net: 'polygon', symbol: 'USDT', amount: '1', to: 't', from: 'f', createdMs: DateTime.now().millisecondsSinceEpoch, nonce: 1));
    await _pump(t, w, pin: () async => true);
    await t.pump();
    await _confirmAll(t);
    expect(find.textContaining('envio de USDT/USDC em aberto'), findsOneWidget);
    expect(_button(t).onPressed, isNull);
    expect(w.log, isEmpty);
  });

  testWidgets('inside the app an OLD open send blocks the delete, with the way out, and nothing is wiped', (t) async {
    final w = _World();
    w.pending.items.add(PendingSend(id: 'old1', net: 'polygon', symbol: 'USDT', amount: '1500000', to: 't', from: 'f', createdMs: DateTime.now().millisecondsSinceEpoch - const Duration(hours: 5).inMilliseconds, nonce: 1));
    await _pump(t, w, pin: () async => true);
    await t.pump();
    await _confirmAll(t);
    expect(find.textContaining('antigos sem resposta'), findsOneWidget);
    expect(_button(t).onPressed, isNull);
    expect(w.log, isEmpty);
  });

  testWidgets('on the lock screen old sends are LISTED with their ids and need one more tick before the wipe goes ahead', (t) async {
    final w = _World();
    w.pending.items.add(PendingSend(id: '0xOLDHASH', net: 'polygon', symbol: 'USDT', amount: '1500000', to: 't', from: 'f', createdMs: DateTime.now().millisecondsSinceEpoch - const Duration(hours: 5).inMilliseconds, nonce: 1));
    await _pump(t, w, forgot: true);
    await t.pump();
    expect(find.text('0xOLDHASH'), findsOneWidget);
    expect(find.text('Polygon: 1,50 USDT'), findsOneWidget);
    await t.tap(find.byType(CheckboxListTile).last); // "I wrote the 12 words"
    await t.pump();
    await t.enterText(find.byType(TextField), 'APAGAR');
    await t.pump();
    expect(_button(t).onPressed, isNull); // the old sends are not acknowledged yet
    await t.tap(find.byType(CheckboxListTile).first);
    await t.pump();
    expect(_button(t).onPressed, isNotNull);
    await t.tap(find.widgetWithText(GradientButton, 'Apagar carteira'));
    await t.pump();
    await t.pump();
    expect(w.wiped, 1);
    expect(w.pending.items, isEmpty);
  });

  testWidgets('a wipe that fails says so, does not report success, and the user can try again', (t) async {
    final w = _World();
    final failing = WalletOps(store: w.store, pins: w.pins, pending: w.pending, closeSpark: () async => throw StateError('boom'), deleteSparkData: () async {});
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: appTheme(), home: Scaffold(body: DeleteWalletView(ops: failing, balances: ValueNotifier(const <String>[]), confirmPin: () async => true, onWiped: () => w.wiped++, onBack: () {}))));
    await _confirmAll(t);
    await t.tap(find.widgetWithText(GradientButton, 'Apagar carteira'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('Não consegui apagar tudo'), findsOneWidget);
    expect(w.wiped, 0);
    expect(w.store.map.containsKey(walletWordsKey), isTrue);
    expect(_button(t).onPressed, isNotNull);
  });

  testWidgets('back does not wipe', (t) async {
    final w = _World();
    await _pump(t, w, pin: () async => true);
    await t.tap(find.byIcon(Icons.arrow_back));
    expect(w.back, 1);
    expect(w.wiped, 0);
  });
}
