import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/app_lock.dart';
import 'package:wallet/backup_crypto.dart' show Argon2Params;
import 'package:wallet/pin.dart';

import 'memory_secret_store.dart';

void main() {
  late MemorySecretStore secrets;
  late PinStore pins;
  late List<bool> secure;
  var clock = DateTime(2026, 11, 5, 12);
  AppLock lock({Duration awayFor = const Duration(seconds: 30)}) => AppLock(pins: pins, now: () => clock, secure: (on) async => secure.add(on), awayFor: awayFor);

  setUp(() {
    secrets = MemorySecretStore();
    pins = PinStore(secrets, params: const Argon2Params(memory: 8, iterations: 1), now: () => clock);
    secure = [];
    clock = DateTime(2026, 11, 5, 12);
  });

  test('refresh learns whether there is a PIN, and locks at start only when asked and there is one', () async {
    final a = lock();
    await a.refresh(lockIfSet: true);
    expect(a.hasPin, isFalse);
    expect(a.locked, isFalse);
    await pins.set('4821');
    await a.refresh();
    expect(a.hasPin, isTrue);
    expect(a.locked, isFalse);
    await a.refresh(lockIfSet: true);
    expect(a.locked, isTrue);
  });

  test('leaving the app marks the screen secure; coming back soon does not lock', () async {
    await pins.set('4821');
    final a = lock();
    await a.refresh();
    a.didChangeAppLifecycleState(AppLifecycleState.inactive);
    a.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(secure, [true]); // one switch on, however many times the app says it is leaving
    clock = clock.add(const Duration(seconds: 30)); // exactly the limit is still fine
    a.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(a.locked, isFalse);
    await Future<void>.delayed(Duration.zero); // the platform call that switched it on has finished
    expect(secure.last, isFalse);
  });

  test('coming back after more than 30 seconds locks, and the screen stays secure until it is unlocked', () async {
    await pins.set('4821');
    final a = lock();
    await a.refresh();
    a.didChangeAppLifecycleState(AppLifecycleState.paused);
    clock = clock.add(const Duration(seconds: 31));
    a.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(a.locked, isTrue);
    expect(secure.last, isTrue);
    await Future<void>.delayed(Duration.zero); // the platform call that switched it on has finished
    a.unlock();
    expect(a.locked, isFalse);
    expect(secure.last, isFalse);
  });

  test('released while still switching on: it is switched off as soon as it is on, never left on', () async {
    final started = <bool>[];
    final h = SecureHolds((on) async {
      started.add(on);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    final f = h.hold('away');
    h.release('away'); // before the platform answered
    expect(await f, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(started, [true, false]);
    expect(h.on, isFalse);
  });

  test('inactive alone (a system dialog) starts no clock: a long inactive spell does not lock', () async {
    await pins.set('4821');
    final a = lock();
    await a.refresh();
    a.didChangeAppLifecycleState(AppLifecycleState.inactive);
    clock = clock.add(const Duration(minutes: 10));
    a.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(a.locked, isFalse);
  });

  test('without a PIN nothing is secured and nothing locks', () async {
    final a = lock();
    await a.refresh();
    a.didChangeAppLifecycleState(AppLifecycleState.paused);
    clock = clock.add(const Duration(hours: 1));
    a.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(a.locked, isFalse);
    expect(secure, isEmpty);
  });

  test('whenUnlocked is immediate when unlocked and waits while locked', () async {
    await pins.set('4821');
    final a = lock();
    await a.refresh();
    await a.whenUnlocked();
    a.lockNow();
    var done = false;
    final f = a.whenUnlocked().then((_) => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(done, isFalse);
    a.unlock();
    await f;
    expect(done, isTrue);
  });

  test('a wipe takes the PIN and the lock away, releases waiters and is counted', () async {
    await pins.set('4821');
    final a = lock();
    await a.refresh(lockIfSet: true);
    var released = false;
    final f = a.whenUnlocked().then((_) => released = true);
    var notified = 0;
    a.addListener(() => notified++);
    a.walletWiped();
    await f;
    expect(released, isTrue);
    expect([a.hasPin, a.locked, a.wipes], [false, false, 1]);
    expect(notified, greaterThan(0));
  });

  group('the screen protection has an owner per reason', () {
    test('the flag is on while ANY reason is held and off only when the last is released', () async {
      final calls = <bool>[];
      final h = SecureHolds((on) async => calls.add(on));
      expect(await h.hold('away'), isTrue);
      expect(await h.hold('words'), isTrue);
      expect(await h.hold('words'), isTrue);
      expect(calls, [true]);
      h.release('away');
      expect(h.on, isTrue);
      expect(calls, [true]); // the words are still showing
      h.release('words');
      expect(calls, [true, false]);
      h.release('words'); // releasing what is not held changes nothing
      expect(calls, [true, false]);
    });

    test('a hold says false when the protection could not be switched on, and says true again once it can', () async {
      var fail = true;
      final h = SecureHolds((on) async {
        if (fail) throw StateError('channel down');
      });
      expect(await h.hold('words'), isFalse);
      fail = false;
      expect(await h.hold('words'), isTrue);
    });

    test('leaving and returning, or unlocking, never switches the protection off while the words are showing', () async {
      await pins.set('4821');
      final a = lock();
      await a.refresh();
      await a.secure.hold('words');
      expect(secure, [true]);
      // back within the limit
      a.didChangeAppLifecycleState(AppLifecycleState.paused);
      clock = clock.add(const Duration(seconds: 5));
      a.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(secure, [true]);
      // back after the limit: locked, then unlocked with the PIN
      a.didChangeAppLifecycleState(AppLifecycleState.paused);
      clock = clock.add(const Duration(minutes: 2));
      a.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(a.locked, isTrue);
      a.unlock();
      expect(secure, [true]); // still on: the words screen has not let go
      a.secure.release('words');
      expect(secure, [true, false]);
    });
  });
}
