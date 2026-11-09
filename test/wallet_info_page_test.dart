import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/app_lock.dart';
import 'package:wallet/chain_balances.dart' show rpcRoute;
import 'package:wallet/i18n.dart';
import 'package:wallet/pending_sends.dart';
import 'package:wallet/theme.dart';
import 'package:wallet/wallet.dart';
import 'package:wallet/wallet_info_page.dart';
import 'package:wallet/wipe.dart';

import 'memory_secret_store.dart';

const _words = ['alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel', 'india', 'juliet', 'kilo', 'lima'];

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _type(WidgetTester t, String pin) async {
  for (final c in pin.split('')) {
    await t.tap(find.byKey(Key('pin-$c')));
    await t.pump();
  }
  await t.tap(find.byKey(const Key('pin-ok')));
  await _settle(t);
}

void main() {
  late MemorySecretStore store;
  late AppLock lock;
  late WalletOps ops;
  late List<bool> secure;
  late Directory langDir;

  Future<void> Function(bool)? secureHook;

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    langDir = Directory.systemTemp.createTempSync('lang');
    addTearDown(() {
      lang.value = Lang.pt;
      langDir.deleteSync(recursive: true);
    });
    store = MemorySecretStore();
    store.map[walletWordsKey] = _words.join(' ');
    secure = [];
    final pins = testPins(store);
    await pins.set('4821');
    secureHook = null;
    lock = AppLock(pins: pins, secure: (on) async {
      secure.add(on);
      await secureHook?.call(on);
    });
    await lock.refresh();
    ops = WalletOps(store: store, pins: pins, pending: MemoryPendingStore(), closeSpark: () async {}, deleteSparkData: () async {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ibirapay/seed_backup'), (call) async {
      if (call.method == 'secure') secure.add(call.arguments == true);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ibirapay/seed_backup'), null));
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: WalletInfoPage(
          wallet: const DerivedWallet(sparkCredential: 'c', polygon: '0xPOLY', solana: 'SOLADDR'),
          words: _words,
          version: 'v-test',
          lock: lock,
          ops: ops,
          balanceLines: ValueNotifier(const ['1 000 sats']),
          langPrefs: LangPrefs(langDir),
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('the language choice: three languages named in their own tongue, tapping one switches the page now and saves it', (t) async {
    await pump(t);
    // the save is real file IO: let the real clock run before reading the file back
    Future<Lang?> saved(String phone) async {
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(); // the pending save continues in the test's fake zone only when it pumps
      }
      return t.runAsync(() => LangPrefs(langDir).load(phone: phone));
    }
    expect(find.text('Idioma'), findsOneWidget);
    for (final l in ['Português', 'English', 'Español']) {
      expect(find.text(l), findsOneWidget);
    }
    await t.tap(find.byKey(const Key('lang-en')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(lang.value, Lang.en);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Idioma'), findsNothing);
    expect(await saved('pt'), Lang.en, reason: 'saved, so a restart keeps it even if the phone says pt');
    await t.tap(find.byKey(const Key('lang-es')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Idioma'), findsOneWidget);
    expect(await saved('en'), Lang.es);
  });

  for (final l in Lang.values) {
    testWidgets('the Carteira page and the delete screen fit a narrow phone in ${l.label}, with every text in that language', (t) async {
      await pump(t);
      setLang(l);
      t.view.physicalSize = const Size(360, 800);
      await t.pump();
      expect(t.takeException(), isNull, reason: 'no overflow on the page');
      expect(find.text(tr('info.title')), findsOneWidget);
      expect(find.text(tr('info.addresses')), findsOneWidget);
      expect(find.text(tr('info.words')), findsOneWidget);
      expect(find.text(tr('info.risk')), findsOneWidget);
      await t.tap(find.text(tr('del.title')));
      await _settle(t);
      expect(t.takeException(), isNull, reason: 'no overflow on the delete screen');
      expect(find.text(tr('del.warn')), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  }

  testWidgets('the 12 words are hidden, and showing them asks the PIN: wrong keeps them hidden, right shows them', (t) async {
    await pump(t);
    expect(find.textContaining('1. alpha'), findsNothing);
    await t.tap(find.text('Mostrar as 12 palavras'));
    await _settle(t);
    expect(find.text('Confirme o PIN para ver as 12 palavras'), findsOneWidget);
    await _type(t, '0000');
    expect(find.textContaining('PIN errado'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close)); // give up
    await _settle(t);
    expect(find.textContaining('1. alpha'), findsNothing);
    await t.tap(find.text('Mostrar as 12 palavras'));
    await _settle(t);
    await _type(t, '4821');
    expect(find.textContaining('1. alpha'), findsOneWidget);
    expect(secure, contains(true)); // no screenshots while they are showing
    // hiding does not ask the PIN
    await t.tap(find.text('Esconder'));
    await _settle(t);
    expect(find.textContaining('1. alpha'), findsNothing);
  });

  testWidgets('delete from the wallet page: tick, APAGAR, then the PIN; nothing is wiped before the PIN, and a wrong PIN wipes nothing', (t) async {
    await pump(t);
    await t.scrollUntilVisible(find.text('Apagar carteira'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.widgetWithText(OutlineButton, 'Apagar carteira'));
    await _settle(t);
    expect(find.text('1 000 sats'), findsOneWidget);
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.enterText(find.byType(TextField), 'APAGAR');
    await t.pump();
    await t.tap(find.widgetWithText(GradientButton, 'Apagar carteira'));
    await _settle(t);
    expect(find.text('Confirme o PIN para apagar a carteira'), findsOneWidget);
    expect(store.map.containsKey(walletWordsKey), isTrue);
    await _type(t, '0000');
    expect(store.map.containsKey(walletWordsKey), isTrue);
    expect(lock.wipes, 0);
    await _type(t, '4821');
    expect(store.map.containsKey(walletWordsKey), isFalse);
    expect(lock.wipes, 1);
    expect(await testPins(store).has(), isFalse);
  });

  testWidgets('while the words show, leaving and returning never drops the screenshot block; a lock puts the words away and they stay away after unlocking', (t) async {
    await pump(t);
    await t.tap(find.text('Mostrar as 12 palavras'));
    await _settle(t);
    await _type(t, '4821');
    expect(find.textContaining('1. alpha'), findsOneWidget);
    expect(secure, [true]);
    // leave and come back at once
    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await t.pump();
    expect(secure.contains(false), isFalse);
    expect(find.textContaining('1. alpha'), findsOneWidget);
    // the lock engages: the words are put away at once
    lock.lockNow();
    await t.pump();
    expect(find.textContaining('1. alpha'), findsNothing);
    lock.unlock();
    await t.pump();
    expect(find.textContaining('1. alpha'), findsNothing); // and do not come back by themselves
    expect(secure.last, isFalse); // nothing needs the protection any more
  });

  testWidgets('the words are not drawn until the screenshot block is CONFIRMED on; if it cannot be switched on they are never shown', (t) async {
    await pump(t);
    // 1) slow to confirm: the words wait for it
    final gate = Completer<void>();
    secureHook = (on) => on ? gate.future : Future.value();
    await t.tap(find.text('Mostrar as 12 palavras'));
    await _settle(t);
    await _type(t, '4821');
    expect(secure, [true]); // asked...
    expect(find.textContaining('1. alpha'), findsNothing); // ...but not confirmed yet: nothing drawn
    gate.complete();
    await _settle(t);
    expect(find.textContaining('1. alpha'), findsOneWidget);
    await t.tap(find.text('Esconder'));
    await _settle(t);
    // 2) the platform refuses: fail closed
    secureHook = (on) async {
      if (on) throw StateError('channel down');
    };
    await t.tap(find.text('Mostrar as 12 palavras'));
    await _settle(t);
    await _type(t, '4821');
    expect(find.textContaining('1. alpha'), findsNothing);
    expect(find.textContaining('Não consegui bloquear capturas de tela'), findsOneWidget);
  });

  testWidgets('the wallet page says whether Polygon is served by our relay or by the public fallback', (t) async {
    rpcRoute.value = null;
    await pump(t);
    expect(find.textContaining('Polygon: '), findsNothing);
    rpcRoute.value = 'relay';
    await t.pump();
    expect(find.text('Polygon: relay IBIRAPAY'), findsOneWidget);
    rpcRoute.value = 'public';
    await t.pump();
    expect(find.text('Polygon: nós públicos (relay indisponível)'), findsOneWidget);
    rpcRoute.value = null;
  });
}
