import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/app_lock.dart';
import 'package:wallet/main.dart';
import 'package:wallet/pending_sends.dart';
import 'package:wallet/theme.dart';
import 'package:wallet/wallet.dart';
import 'package:wallet/wipe.dart';

import 'memory_secret_store.dart';
import 'stable_vectors.dart';

class _App {
  _App() {
    lock = AppLock(pins: pins, secure: (_) async {});
    ops = WalletOps(store: store, pins: pins, pending: MemoryPendingStore(), closeSpark: () async {}, deleteSparkData: () async {});
  }
  final store = MemorySecretStore();
  late final pins = testPins(store);
  late final AppLock lock;
  late final WalletOps ops;
  final opened = <List<String>>[];

  Future<OpenedWallet> open(List<String> words) async {
    opened.add(words);
    return OpenedWallet(wallet: const DerivedWallet(sparkCredential: 'c', polygon: '0xp', solana: 'sol'), words: words, sdk: Object());
  }

  Widget home(BuildContext c, OpenedWallet w, WalletOps o, AppLock l) => Column(
    children: [
      const Text('HOME'),
      TextButton(onPressed: () => o.wipe().then((_) => l.walletWiped()), child: const Text('wipe-now')),
    ],
  );

  Future<void> start(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await lock.refresh(lockIfSet: true); // what main() does
    await t.pumpWidget(WalletApp(store: store, lock: lock, ops: ops, open: open, home: home));
    await settle(t);
  }
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> typePin(WidgetTester t, String pin) async {
  for (final c in pin.split('')) {
    await t.tap(find.byKey(Key('pin-$c')));
    await t.pump();
  }
  await t.tap(find.byKey(const Key('pin-ok')));
  await settle(t);
}

void main() {
  testWidgets('fresh install: welcome, create, set a PIN (typed twice), then the home', (t) async {
    final a = _App();
    await a.start(t);
    expect(find.text('Criar carteira'), findsOneWidget);
    expect(find.textContaining('só valores pequenos'), findsNothing);
    await t.tap(find.text('Criar carteira'));
    await settle(t);
    expect(find.text('Crie um PIN para proteger a carteira'), findsOneWidget);
    expect(a.opened, isEmpty); // the wallet does not open before it has a PIN
    await typePin(t, '4821');
    expect(find.text('Repita o PIN'), findsOneWidget);
    await typePin(t, '4821');
    expect(find.text('HOME'), findsOneWidget);
    expect(a.opened, hasLength(1));
    expect(a.store.map.containsKey(walletWordsKey), isTrue);
    expect(await a.pins.has(), isTrue);
  });

  testWidgets('a wallet from before the PIN existed gets its PIN first and is not opened until then', (t) async {
    final a = _App();
    a.store.map[walletWordsKey] = vMnemonic;
    await a.start(t);
    expect(find.text('Crie um PIN para proteger a carteira'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(a.opened, isEmpty);
    await typePin(t, '4821');
    await typePin(t, '4821');
    expect(find.text('HOME'), findsOneWidget);
    expect(a.opened.single.join(' '), vMnemonic);
  });

  testWidgets('with a PIN: locked at start, the words are NOT even read until it is right, a wrong one opens nothing', (t) async {
    final a = _App();
    a.store.map[walletWordsKey] = vMnemonic;
    await a.pins.set('4821');
    a.store.reads.clear();
    await a.start(t);
    expect(find.text('Digite o PIN'), findsOneWidget);
    expect(a.store.reads.contains(walletWordsKey), isFalse);
    expect(a.opened, isEmpty);
    await typePin(t, '0000');
    expect(find.text('HOME'), findsNothing);
    expect(a.store.reads.contains(walletWordsKey), isFalse);
    await typePin(t, '4821');
    expect(find.text('HOME'), findsOneWidget);
    expect(a.store.reads.contains(walletWordsKey), isTrue);
    expect(a.opened, hasLength(1));
  });

  testWidgets('forgot PIN: the lock screen leads to the wipe, then the welcome screen with nothing left, then restore and a new PIN', (t) async {
    final a = _App();
    a.store.map[walletWordsKey] = vMnemonic;
    await a.pins.set('4821');
    await a.start(t);
    await t.tap(find.text('Esqueci o PIN'));
    await settle(t);
    expect(find.text('Apagar carteira'), findsWidgets);
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.enterText(find.byType(TextField), 'APAGAR');
    await t.pump();
    await t.tap(find.widgetWithText(GradientButton, 'Apagar carteira'));
    await settle(t);
    // back to the start: welcome, no lock, nothing stored
    expect(find.text('Criar carteira'), findsOneWidget);
    expect(find.text('Digite o PIN'), findsNothing);
    expect(a.lock.locked, isFalse);
    expect(a.store.map.containsKey(walletWordsKey), isFalse);
    expect(await a.pins.has(), isFalse);
    // restore with the 12 words: a PIN is asked again, then the home
    await t.tap(find.text('Restaurar com 12 palavras'));
    await settle(t);
    await t.enterText(find.byType(TextField), vMnemonic);
    await t.tap(find.text('Restaurar'));
    await settle(t);
    expect(find.text('Crie um PIN para proteger a carteira'), findsOneWidget);
    await typePin(t, '7359');
    await typePin(t, '7359');
    expect(find.text('HOME'), findsOneWidget);
    expect(a.opened.last.join(' '), vMnemonic);
    expect(a.store.map[walletWordsKey], vMnemonic);
  });

  testWidgets('wiping from inside the app returns to the welcome screen and drops the home', (t) async {
    final a = _App();
    a.store.map[walletWordsKey] = vMnemonic;
    await a.pins.set('4821');
    await a.start(t);
    await typePin(t, '4821');
    expect(find.text('HOME'), findsOneWidget);
    await t.tap(find.text('wipe-now'));
    await settle(t);
    expect(find.text('HOME'), findsNothing);
    expect(find.text('Criar carteira'), findsOneWidget);
    expect(a.store.map.containsKey(walletWordsKey), isFalse);
  });

  testWidgets('start-up with no wallet clears a stale PIN left by a cut-short wipe', (t) async {
    final a = _App();
    await a.pins.set('4821'); // a PIN and no words
    await a.start(t);
    // the lock was up because a PIN existed, and forgetting it leads here; with no words there is nothing to unlock
    expect(await a.pins.has(), isTrue);
    await typePin(t, '4821');
    expect(find.text('Criar carteira'), findsOneWidget);
    expect(await a.pins.has(), isFalse);
  });

  testWidgets('a bad restore phrase is refused and nothing is stored', (t) async {
    final a = _App();
    await a.start(t);
    await t.tap(find.text('Restaurar com 12 palavras'));
    await settle(t);
    await t.enterText(find.byType(TextField), 'not twelve valid words');
    await t.tap(find.text('Restaurar'));
    await settle(t);
    expect(find.textContaining('não formam uma carteira válida'), findsOneWidget);
    expect(a.store.map.containsKey(walletWordsKey), isFalse);
  });
}
