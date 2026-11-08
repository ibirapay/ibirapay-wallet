import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/app_lock.dart';
import 'package:wallet/pin.dart';
import 'package:wallet/pin_pad.dart';
import 'package:wallet/theme.dart';

import 'memory_secret_store.dart';

var _clock = DateTime(2026, 11, 5, 12);
DateTime _now() => _clock;

Widget _app(Widget body) => MaterialApp(theme: appTheme(), home: Scaffold(body: body));

Future<void> _type(WidgetTester t, String pin, {bool ok = true}) async {
  for (final c in pin.split('')) {
    await t.tap(find.byKey(Key('pin-$c')));
    await t.pump();
  }
  if (ok) {
    await t.tap(find.byKey(const Key('pin-ok')));
    // the hash and the store run on timers the test clock must be moved past
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }
}

int _dots(WidgetTester t) => find.descendant(of: find.byKey(const Key('pin-dots')), matching: find.byType(Container)).evaluate().length;

PinStore _pins(MemorySecretStore s) => testPins(s, now: _now);

void main() {
  setUp(() => _clock = DateTime(2026, 11, 5, 12));

  group('the keypad', () {
    testWidgets('digits become dots (at least 4 shown), backspace removes one, never more than 8', (t) async {
      await t.pumpWidget(_app(PinPad(title: 'T', onSubmit: (_) async {})));
      expect(_dots(t), 4);
      await _type(t, '12345', ok: false);
      expect(_dots(t), 5);
      await t.tap(find.byKey(const Key('pin-del')));
      await t.pump();
      expect(_dots(t), 4);
      await _type(t, '9999999999', ok: false);
      expect(_dots(t), 8);
    });

    testWidgets('OK does nothing under 4 digits; with 4 or more it submits exactly what was typed and clears', (t) async {
      final got = <String>[];
      await t.pumpWidget(_app(PinPad(title: 'T', onSubmit: (p) async => got.add(p))));
      await _type(t, '482');
      expect(got, isEmpty);
      await _type(t, '1');
      expect(got, ['4821']);
      expect(_dots(t), 4); // cleared: back to the 4 empty slots
      await _type(t, '123456789'); // the 9th is ignored
      expect(got.last, '12345678');
    });

    testWidgets('while a wait is running the keys are off and the time left is shown', (t) async {
      final got = <String>[];
      await t.pumpWidget(_app(PinPad(title: 'T', waitUntil: _clock.add(const Duration(seconds: 75)), now: _now, onSubmit: (p) async => got.add(p))));
      expect(find.text('Muitas tentativas. Tente de novo em 01:15'), findsOneWidget);
      await _type(t, '4821');
      expect(got, isEmpty);
      expect(_dots(t), 4);
    });

    test('the wait is shown as mm:ss, then h:mm:ss', () {
      expect(fmtWait(const Duration(seconds: 30)), '00:30');
      expect(fmtWait(const Duration(minutes: 15, seconds: 5)), '15:05');
      expect(fmtWait(const Duration(hours: 1)), '1:00:00');
      expect(fmtWait(const Duration(milliseconds: 29001)), '00:30'); // never shows 0 while it still waits
    });
  });

  group('asking the PIN', () {
    testWidgets('a wrong PIN says how many tries are left; the right one opens, once', (t) async {
      final s = MemorySecretStore();
      final pins = _pins(s);
      await pins.set('4821');
      var opened = 0;
      await t.pumpWidget(_app(PinVerifyView(store: pins, now: _now, onVerified: () => opened++)));
      await _type(t, '0000');
      expect(find.text('PIN errado. Mais 4 tentativas antes de esperar.'), findsOneWidget);
      await _type(t, '0001');
      await _type(t, '0002');
      await _type(t, '0003');
      expect(find.text('PIN errado. Mais 1 tentativa antes de esperar.'), findsOneWidget);
      expect(opened, 0);
      await _type(t, '4821');
      expect(opened, 1);
    });

    testWidgets('the 5th wrong try starts the wait: countdown shown, and even the right PIN is not accepted during it', (t) async {
      final s = MemorySecretStore();
      final pins = _pins(s);
      await pins.set('4821');
      var opened = 0;
      await t.pumpWidget(_app(PinVerifyView(store: pins, now: _now, onVerified: () => opened++)));
      for (final w in ['0000', '0001', '0002', '0003', '0004']) {
        await _type(t, w);
      }
      expect(find.text('Muitas tentativas. Tente de novo em 00:30'), findsOneWidget);
      await _type(t, '4821');
      expect(opened, 0);
    });

    testWidgets('a wait that started before the app was closed is shown at once', (t) async {
      final s = MemorySecretStore();
      final pins = _pins(s);
      await pins.set('4821');
      for (var i = 0; i < 5; i++) {
        await pins.verify('9999');
      }
      await t.pumpWidget(_app(PinVerifyView(store: _pins(s), now: _now, onVerified: () {})));
      await t.pump();
      expect(find.textContaining('Muitas tentativas'), findsOneWidget);
    });

    testWidgets('a dead PIN (too many wrong tries) shows a permanent block, the keys do nothing, and the caller is told', (t) async {
      final s = MemorySecretStore();
      final pins = _pins(s);
      await pins.set('4821');
      for (var i = 0; i < 20; i++) {
        _clock = _clock.add(const Duration(days: 1));
        await pins.verify('9999');
      }
      _clock = _clock.add(const Duration(days: 30)); // long past any timed wait: only the permanent block can be holding the keys
      var opened = 0;
      var told = 0;
      await t.pumpWidget(_app(PinVerifyView(store: pins, now: _now, onVerified: () => opened++, onExhausted: () => told++)));
      await t.pump();
      await t.pump();
      expect(find.textContaining('PIN bloqueado'), findsOneWidget);
      expect(told, 1);
      await _type(t, '482159', ok: false);
      expect(_dots(t), 4); // the keys are off: six digits typed would show six dots
      await _type(t, '', ok: true);
      expect(opened, 0);
    });

    testWidgets('the 20th wrong try on screen kills the PIN there and then', (t) async {
      final s = MemorySecretStore();
      final pins = _pins(s);
      await pins.set('4821');
      var told = 0;
      await t.pumpWidget(_app(PinVerifyView(store: pins, now: _now, onVerified: () {}, onExhausted: () => told++)));
      for (var i = 0; i < 20; i++) {
        _clock = _clock.add(const Duration(days: 1)); // every wait skipped
        await _type(t, '9999');
      }
      expect(find.textContaining('PIN bloqueado'), findsOneWidget);
      expect(told, 1);
    });

    testWidgets('a PIN record that cannot be read says so and opens nothing', (t) async {
      final s = MemorySecretStore()..map['pin.v1'] = '{broken';
      var opened = 0;
      await t.pumpWidget(_app(PinVerifyView(store: _pins(s), now: _now, onVerified: () => opened++)));
      await _type(t, '4821');
      expect(find.textContaining('Não consegui ler o PIN'), findsOneWidget);
      expect(opened, 0);
    });
  });

  group('setting a PIN', () {
    testWidgets('typed twice; a weak one and a mismatch are refused with their reason; the match is stored', (t) async {
      final s = MemorySecretStore();
      final pins = _pins(s);
      var done = 0;
      await t.pumpWidget(_app(PinCreateView(store: pins, onDone: () => done++)));
      await _type(t, '1234');
      expect(find.textContaining('sequência'), findsOneWidget);
      await _type(t, '4821');
      expect(find.text('Repita o PIN'), findsOneWidget);
      await _type(t, '4822');
      expect(find.textContaining('diferentes'), findsOneWidget);
      expect(find.text('Crie um PIN'), findsOneWidget); // back to the start
      expect(s.map.containsKey('pin.v1'), isFalse);
      await _type(t, '4821');
      await _type(t, '4821');
      expect(done, 1);
      expect(s.map.containsKey('pin.v1'), isTrue);
      final r = await pins.verify('4821');
      expect(r, isA<PinOk>());
    });
  });

  group('the lock layer', () {
    Future<(AppLock, PinStore)> setup(WidgetTester t, {String? pin}) async {
      final s = MemorySecretStore();
      final pins = _pins(s);
      if (pin != null) await pins.set(pin);
      final lock = AppLock(pins: pins, now: _now, secure: (_) async {});
      await lock.refresh();
      return (lock, pins);
    }

    Widget layered(AppLock lock) => MaterialApp(
      theme: appTheme(),
      builder: (context, child) => LockLayer(
        lock: lock,
        forgotBuilder: (context, back) => Column(children: [const Text('FORGOT'), TextButton(onPressed: back, child: const Text('voltar'))]),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox(height: 200, child: Center(child: Text('SHEET')))), child: const Text('abrir'))),
        ),
      ),
    );

    testWidgets('the lock screen covers a sheet that was open, and unlocking reveals it again', (t) async {
      final (lock, _) = await setup(t, pin: '4821');
      await t.pumpWidget(layered(lock));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(find.text('SHEET').hitTestable(), findsOneWidget);
      lock.lockNow();
      await t.pump();
      expect(find.text('Digite o PIN'), findsOneWidget);
      expect(find.text('SHEET').hitTestable(), findsNothing);
      await _type(t, '4821');
      expect(lock.locked, isFalse);
      await t.pump();
      expect(find.text('SHEET').hitTestable(), findsOneWidget);
    });

    testWidgets('a wrong PIN keeps it locked', (t) async {
      final (lock, _) = await setup(t, pin: '4821');
      await t.pumpWidget(layered(lock));
      lock.lockNow();
      await t.pump();
      await _type(t, '0000');
      expect(lock.locked, isTrue);
      expect(find.textContaining('PIN errado'), findsOneWidget);
    });

    testWidgets('"Esqueci o PIN" opens the forgot screen inside the layer, and back returns to the pad', (t) async {
      final (lock, _) = await setup(t, pin: '4821');
      await t.pumpWidget(layered(lock));
      lock.lockNow();
      await t.pump();
      await t.tap(find.text('Esqueci o PIN'));
      await t.pump();
      expect(find.text('FORGOT'), findsOneWidget);
      expect(find.text('Digite o PIN'), findsNothing);
      await t.tap(find.text('voltar'));
      await t.pump();
      expect(find.text('Digite o PIN'), findsOneWidget);
    });

    testWidgets('confirm with a dead PIN closes the page, answers no, and puts the lock screen up (where Esqueci o PIN is)', (t) async {
      final (lock, pins) = await setup(t, pin: '4821');
      for (var i = 0; i < 20; i++) {
        _clock = _clock.add(const Duration(days: 1));
        await pins.verify('9999');
      }
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(theme: appTheme(), home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })));
      final f = lock.confirm(ctx);
      await t.pumpAndSettle();
      expect(await f, isFalse);
      expect(lock.locked, isTrue);
    });

    testWidgets('confirm: true on the right PIN, false when closed, false when there is no PIN at all', (t) async {
      final (lock, _) = await setup(t, pin: '4821');
      bool? result;
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(theme: appTheme(), home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })));
      final f = lock.confirm(ctx, reason: 'Confirme');
      await t.pumpAndSettle();
      expect(find.text('Confirme'), findsOneWidget);
      await _type(t, '4821');
      await t.pumpAndSettle();
      result = await f;
      expect(result, isTrue);

      final g = lock.confirm(ctx);
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.close));
      await t.pumpAndSettle();
      expect(await g, isFalse);

      final (bare, _) = await setup(t);
      expect(await bare.confirm(ctx), isFalse); // a missing lock opens nothing
    });
  });
}
