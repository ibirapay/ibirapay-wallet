import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/backup_crypto.dart' show Argon2Params;
import 'package:wallet/pin.dart';
import 'package:wallet/secret_store.dart';

const _tiny = Argon2Params(memory: 8, iterations: 1);

void main() {
  late Directory dir;
  late SecretStore secrets;
  var clock = DateTime(2026, 11, 5, 12);
  PinStore store() => PinStore(secrets, params: _tiny, now: () => clock);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pin_test');
    secrets = SecretStore.dir(dir);
    clock = DateTime(2026, 11, 5, 12);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('what a new PIN may be', () {
    test('4 to 8 digits that are not one repeated digit or a straight run', () {
      for (final ok in ['4821', '135792', '90210', '12345679', '1357', '2580', '1212', '0001']) {
        expect(pinProblem(ok), isNull, reason: ok);
      }
      for (final bad in ['', '123', '123456789', '12a4', '12 34', '１２３４', '1111', '00000', '12345', '4321', '6789', '7890', '0123', '3210', '98765', '12345678']) {
        expect(pinProblem(bad), isNotNull, reason: bad);
      }
    });
  });

  group('wrong tries earn waits', () {
    test('schedule: nothing for 4, then 30 s, 1 min, 5 min, 15 min, 1 h', () {
      expect([for (var i = 0; i <= 4; i++) pinWaitAfter(i)], everyElement(Duration.zero));
      expect(pinWaitAfter(5), const Duration(seconds: 30));
      expect(pinWaitAfter(6), const Duration(minutes: 1));
      expect(pinWaitAfter(7), const Duration(minutes: 5));
      expect(pinWaitAfter(8), const Duration(minutes: 15));
      expect(pinWaitAfter(9), const Duration(hours: 1));
      expect(pinWaitAfter(40), const Duration(hours: 1));
    });
  });

  group('the store', () {
    test('a right PIN opens, a wrong one counts down the tries left', () async {
      final s = store();
      expect(await s.has(), isFalse);
      await s.set('4821');
      expect(await s.has(), isTrue);
      expect(await s.verify('4821'), isA<PinOk>());
      for (final left in [4, 3, 2, 1]) {
        expect((await s.verify('0000')), isA<PinWrong>().having((r) => r.triesLeft, 'triesLeft', left));
      }
    });

    test('the 5th wrong try starts a 30 s wait; during it even the right PIN is not checked; after it the next wrong one waits longer', () async {
      final s = store();
      await s.set('4821');
      for (var i = 0; i < 4; i++) {
        await s.verify('9999');
      }
      final fifth = await s.verify('9999');
      expect(fifth, isA<PinWait>().having((r) => r.until, 'until', clock.add(const Duration(seconds: 30))));
      expect(await s.verify('4821'), isA<PinWait>()); // right PIN, still waiting
      expect(await s.waitingUntil(), clock.add(const Duration(seconds: 30)));
      clock = clock.add(const Duration(seconds: 31));
      expect(await s.waitingUntil(), isNull);
      expect(await s.verify('9999'), isA<PinWait>().having((r) => r.until, 'until', clock.add(const Duration(minutes: 1))));
      clock = clock.add(const Duration(minutes: 2));
      expect(await s.verify('4821'), isA<PinOk>());
      // a right PIN resets the count: 4 more tries are free again
      expect(await s.verify('1357'), isA<PinWrong>().having((r) => r.triesLeft, 'triesLeft', 4));
    });

    test('the waits survive a restart (a new store object, same storage)', () async {
      final a = store();
      await a.set('4821');
      for (var i = 0; i < 5; i++) {
        await a.verify('9999');
      }
      final b = store();
      expect(await b.verify('4821'), isA<PinWait>());
    });

    test('a wait is not started or shortened by tries made during it', () async {
      final s = store();
      await s.set('4821');
      for (var i = 0; i < 5; i++) {
        await s.verify('9999');
      }
      final until = await s.waitingUntil();
      for (var i = 0; i < 20; i++) {
        await s.verify('9999');
      }
      expect(await s.waitingUntil(), until);
    });

    test('setting a new PIN replaces the old one and clears the count; clear removes it', () async {
      final s = store();
      await s.set('4821');
      await s.verify('9999');
      await s.set('7359');
      expect(await s.verify('4821'), isA<PinWrong>().having((r) => r.triesLeft, 'triesLeft', 4));
      expect(await s.verify('7359'), isA<PinOk>());
      await s.clear();
      expect(await s.has(), isFalse);
      expect(File('${dir.path}/pin.fails').existsSync(), isFalse);
    });

    test('an unacceptable PIN is refused with its reason and nothing is stored', () async {
      final s = store();
      await expectLater(s.set('1234'), throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('sequência'))));
      expect(await s.has(), isFalse);
    });

    test('the PIN itself is never stored', () async {
      await store().set('4821');
      for (final f in dir.listSync().whereType<File>()) {
        expect(f.readAsStringSync().contains('4821'), isFalse, reason: f.path);
      }
    });

    test('two tries at once are counted one by one', () async {
      final s = store();
      await s.set('4821');
      await Future.wait([for (var i = 0; i < 4; i++) s.verify('9999')]);
      expect(await s.verify('9999'), isA<PinWait>()); // exactly the 5th
    });

    test('no PIN set is an error, and an unreadable record is an error, never "open"', () async {
      await expectLater(store().verify('4821'), throwsStateError);
      File('${dir.path}/pin.v1').writeAsStringSync('{not json');
      await expectLater(store().verify('4821'), throwsA(isA<FormatException>()));
      File('${dir.path}/pin.v1').writeAsStringSync('{"v":2,"salt":"AA==","hash":"AA==","memory":8,"iterations":1,"parallelism":1}');
      await expectLater(store().verify('4821'), throwsA(isA<FormatException>()));
      File('${dir.path}/pin.v1').writeAsStringSync('{"v":1,"salt":"AA==","hash":"AA==","memory":99999999,"iterations":1,"parallelism":1}');
      await expectLater(store().verify('4821'), throwsA(isA<FormatException>())); // a record cannot ask for unbounded memory
    });

    test('a corrupt failure counter stops the check instead of resetting it', () async {
      final s = store();
      await s.set('4821');
      File('${dir.path}/pin.fails').writeAsStringSync('garbage');
      await expectLater(s.verify('4821'), throwsA(isA<FormatException>()));
    });

    test('the real Argon2 parameters hash and verify (slow path, once)', () async {
      final s = PinStore(secrets, now: () => clock);
      await s.set('4821');
      expect(await s.verify('4821'), isA<PinOk>());
      expect(await s.verify('4822'), isA<PinWrong>());
    });
  });

  group('the hard cap: waits depend on a clock the holder of the phone can move, the count does not', () {
    test('moving the clock forward before every try gets 20 guesses, not more: the 20th wrong try kills the PIN', () async {
      final s = store();
      await s.set('4821');
      PinResult? last;
      for (var i = 1; i <= 19; i++) {
        clock = clock.add(const Duration(days: 1)); // the attacker skips every wait
        last = await s.verify('9999');
        expect(last, isNot(isA<PinExhausted>()), reason: 'try $i');
      }
      clock = clock.add(const Duration(days: 1));
      expect(await s.verify('9999'), isA<PinExhausted>()); // the 20th
      expect(await s.exhausted(), isTrue);
      // from now on even the RIGHT PIN is refused, and unchecked
      clock = clock.add(const Duration(days: 365));
      expect(await s.verify('4821'), isA<PinExhausted>());
      expect(await s.verify('4821'), isA<PinExhausted>());
    });

    test('a right PIN before the cap resets the count', () async {
      final s = store();
      await s.set('4821');
      for (var i = 0; i < 19; i++) {
        clock = clock.add(const Duration(days: 1));
        await s.verify('9999');
      }
      clock = clock.add(const Duration(days: 1));
      expect(await s.verify('4821'), isA<PinOk>());
      expect(await s.exhausted(), isFalse);
      for (var i = 0; i < 19; i++) {
        clock = clock.add(const Duration(days: 1));
        expect(await s.verify('9999'), isNot(isA<PinExhausted>()));
      }
    });

    test('a dead PIN stays dead across a restart, and setting a new PIN (a restored wallet) starts fresh', () async {
      final s = store();
      await s.set('4821');
      for (var i = 0; i < 20; i++) {
        clock = clock.add(const Duration(days: 1));
        await s.verify('9999');
      }
      expect(await store().exhausted(), isTrue);
      expect(await store().verify('4821'), isA<PinExhausted>());
      await s.set('7359');
      expect(await store().exhausted(), isFalse);
      expect(await store().verify('7359'), isA<PinOk>());
    });
  });
}
