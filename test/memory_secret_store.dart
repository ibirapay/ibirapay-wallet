import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show SHA256Digest;
import 'package:wallet/backup_crypto.dart' show Argon2Params;
import 'package:wallet/pin.dart';
import 'package:wallet/secret_store.dart';

/// A fast stand-in for the PIN hash, for widget tests (see [PinHash]). Different PINs and salts give different bytes.
Future<List<int>> fastHash(String pin, Uint8List salt, Argon2Params params) async =>
    SHA256Digest().process(Uint8List.fromList([...utf8.encode(pin), ...salt, params.memory & 0xff]));

/// A PinStore for widget tests: in-memory secrets, fast hash, an injectable clock.
PinStore testPins(MemorySecretStore s, {DateTime Function()? now}) => PinStore(s, params: const Argon2Params(memory: 8, iterations: 1), now: now, hash: fastHash);

/// A secret store in memory, for widget tests (real file I/O does not complete under the widget-test clock). [reads] logs every name read,
/// so a test can prove something was NOT read.
class MemorySecretStore extends SecretStore {
  MemorySecretStore() : super();
  final map = <String, String>{};
  final reads = <String>[];

  @override
  Future<String?> read(String name) async {
    reads.add(name);
    return map[name];
  }

  @override
  Future<void> write(String name, String value) async => map[name] = value;

  @override
  Future<void> delete(String name) async => map.remove(name);
}
