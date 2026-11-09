// The wallet PIN: 4 to 8 digits, kept only as an Argon2id hash. Wrong tries earn waits that grow and are stored, so closing the app
// does not reset them. A PIN record that cannot be read is an error, never "no PIN": an unreadable lock must not open the wallet.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'backup_crypto.dart' show Argon2Params;
import 'i18n.dart';
import 'secret_store.dart';

/// About 19 MiB and 2 passes: a fraction of a second on a phone, and a guess still costs an attacker who got the hash real memory.
const pinParams = Argon2Params(memory: 19456, iterations: 2);

const pinMinLength = 4;
const pinMaxLength = 8;

/// Why [pin] cannot be used as a new PIN, or null when it can. Straight runs wrap around (7890, 0123, 3210).
String? pinProblem(String pin) {
  if (!RegExp(r'^\d+$').hasMatch(pin) || pin.length < pinMinLength || pin.length > pinMaxLength) {
    return tr('pin.length', {'min': pinMinLength, 'max': pinMaxLength});
  }
  final d = [for (final c in pin.codeUnits) c - 0x30];
  if (d.every((x) => x == d.first)) return tr('pin.repeated');
  final steps = {for (var i = 1; i < d.length; i++) (d[i] - d[i - 1]) % 10};
  if (steps.length == 1 && (steps.first == 1 || steps.first == 9)) return tr('pin.sequence');
  return null;
}

/// Wrong tries, in total since the last right PIN, after which the PIN is dead: no wait is long enough to rely on, because waits are
/// measured with a clock the person holding the phone can move. Only wiping the wallet and restoring it from the 12 words goes on.
const pinMaxFails = 20;

/// How long to wait after the [fails]-th wrong try since the last right one: nothing for 4, then 30 s, 1 min, 5 min, 15 min, 1 h.
Duration pinWaitAfter(int fails) {
  if (fails < 5) return Duration.zero;
  return switch (fails) {
    5 => const Duration(seconds: 30),
    6 => const Duration(minutes: 1),
    7 => const Duration(minutes: 5),
    8 => const Duration(minutes: 15),
    _ => const Duration(hours: 1),
  };
}

sealed class PinResult {
  const PinResult();
}

class PinOk extends PinResult {
  const PinOk();
}

/// Wrong, and [triesLeft] more are allowed before the next wait starts.
class PinWrong extends PinResult {
  const PinWrong(this.triesLeft);
  final int triesLeft;
}

/// No tries until [until]; the PIN was not even checked.
class PinWait extends PinResult {
  const PinWait(this.until);
  final DateTime until;
}

/// [pinMaxFails] wrong tries: the PIN is locked for good (even the right one is refused, unchecked) until the wallet is wiped.
class PinExhausted extends PinResult {
  const PinExhausted();
}

/// The hash of [pin] under [salt]: Argon2id in the app. A widget test passes a fast stand-in (pure-Dart Argon2 does real asynchronous work
/// that never completes under the widget-test clock); the real one is tested in pin_test.dart.
typedef PinHash = Future<List<int>> Function(String pin, Uint8List salt, Argon2Params params);

class PinStore {
  // ignore: prefer_initializing_formals
  PinStore(this._store, {Argon2Params params = pinParams, DateTime Function()? now, PinHash? hash}) : _params = params, _now = now ?? DateTime.now, _hashWith = hash;
  final SecretStore _store;
  final Argon2Params _params;
  final DateTime Function() _now;
  final PinHash? _hashWith;

  static const _recordKey = 'pin.v1';
  static const _failsKey = 'pin.fails';

  /// One check at a time: two taps must not both read the same failure count. The app has one PinStore (AppLock's), so a lock per
  /// object is the lock of the whole app.
  Future<void> _tail = Future<void>.value();
  Future<T> _locked<T>(Future<T> Function() f) {
    final run = _tail.then((_) => f());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<bool> has() async => await _store.read(_recordKey) != null;

  Future<List<int>> _hash(String pin, Uint8List salt, Argon2Params p) async {
    final custom = _hashWith;
    if (custom != null) return custom(pin, salt, p);
    final key = await Argon2id(parallelism: p.parallelism, memory: p.memory, iterations: p.iterations, hashLength: 32).deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  /// Sets (or replaces) the PIN and clears the failure count. Throws [ArgumentError] with the reason when the PIN is not acceptable.
  Future<void> set(String pin) => _locked(() async {
    final problem = pinProblem(pin);
    if (problem != null) throw ArgumentError(problem);
    final r = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
    final hash = await _hash(pin, salt, _params);
    await _store.write(
      _recordKey,
      jsonEncode({'v': 1, 'salt': base64Encode(salt), 'hash': base64Encode(hash), 'memory': _params.memory, 'iterations': _params.iterations, 'parallelism': _params.parallelism}),
    );
    await _store.delete(_failsKey);
  });

  Future<void> clear() => _locked(() async {
    await _store.delete(_recordKey);
    await _store.delete(_failsKey);
  });

  Future<({int count, DateTime until})> _fails() async {
    final raw = await _store.read(_failsKey);
    if (raw == null) return (count: 0, until: DateTime.fromMillisecondsSinceEpoch(0));
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return (count: j['count'] as int, until: DateTime.fromMillisecondsSinceEpoch(j['until'] as int));
  }

  /// Whether the PIN is dead ([pinMaxFails] wrong tries). Reads only the stored count: no hashing.
  Future<bool> exhausted() => _locked(() async => (await _fails()).count >= pinMaxFails);

  /// When tries open up again, or null when they are open now. Reads only the stored count: no hashing.
  Future<DateTime?> waitingUntil() => _locked(() async {
    final f = await _fails();
    return f.until.isAfter(_now()) ? f.until : null;
  });

  Future<PinResult> verify(String pin) => _locked(() async {
    final raw = await _store.read(_recordKey);
    if (raw == null) throw StateError('nenhum PIN definido');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final p = Argon2Params(memory: j['memory'] as int, iterations: j['iterations'] as int, parallelism: j['parallelism'] as int);
    if (j['v'] != 1 || p.memory <= 0 || p.memory > 256 * 1024 || p.iterations <= 0 || p.iterations > 10 || p.parallelism <= 0 || p.parallelism > 64) {
      throw const FormatException('registro de PIN inválido');
    }
    final fails = await _fails();
    if (fails.count >= pinMaxFails) return const PinExhausted(); // not even the right PIN: the 21st guess must not be free
    if (fails.until.isAfter(_now())) return PinWait(fails.until);
    final want = base64Decode(j['hash'] as String);
    final got = await _hash(pin, base64Decode(j['salt'] as String), p);
    var diff = want.length ^ got.length;
    for (var i = 0; i < want.length && i < got.length; i++) {
      diff |= want[i] ^ got[i];
    }
    if (diff == 0) {
      await _store.delete(_failsKey);
      return const PinOk();
    }
    final count = fails.count + 1;
    final wait = pinWaitAfter(count);
    final until = wait == Duration.zero ? DateTime.fromMillisecondsSinceEpoch(0) : _now().add(wait);
    await _store.write(_failsKey, jsonEncode({'count': count, 'until': until.millisecondsSinceEpoch}));
    if (count >= pinMaxFails) return const PinExhausted();
    return wait == Duration.zero ? PinWrong(5 - count) : PinWait(until);
  });
}
