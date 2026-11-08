// Shop secrets (MP token, LND cert and macaroon, relay key) stay out of the DB. Android: the Keystore through
// flutter_secure_storage. Elsewhere: one file per secret in the app-support dir, mode 0600.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// A setting whose value is `secret:<name>` points here; any other value is a legacy file path.
const secretPrefix = 'secret:';

/// Names the setting and the secret, never the value.
class SecretMissing implements Exception {
  SecretMissing(this.setting, this.name);
  final String setting;
  final String name;
  @override
  String toString() => 'segredo "$name" (de $setting) ausente: refaça o passo na configuração';
}

/// The text of a secret setting: `secret:<name>` from the store, anything else a legacy file path read as text.
Future<String> secretText(SecretStore store, String value, String setting) async {
  if (!value.startsWith(secretPrefix)) return (await File(value).readAsString()).trim();
  final name = value.substring(secretPrefix.length);
  final text = await store.read(name);
  if (text == null) throw SecretMissing(setting, name);
  return text;
}

class SecretStore {
  SecretStore() : _dir = null;

  /// Tests: the files go into [dir] and the Keystore is never used.
  SecretStore.dir(Directory dir) : _dir = dir;

  final Directory? _dir;
  static const _keystore = FlutterSecureStorage();

  bool get _useKeystore => _dir == null && Platform.isAndroid;

  Future<File> _file(String name) async {
    final d = _dir ?? Directory('${(await getApplicationSupportDirectory()).path}/secrets');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$name');
  }

  Future<String?> read(String name) async {
    if (_useKeystore) return _keystore.read(key: name);
    final f = await _file(name);
    return await f.exists() ? f.readAsString() : null;
  }

  Future<void> write(String name, String value) async {
    if (_useKeystore) return _keystore.write(key: name, value: value);
    final f = await _file(name);
    // ponytail: no Dart API sets file modes, so the 0600 file is made by install(1) before the secret is written
    if (!await f.exists()) await Process.run('install', ['-m', '600', '/dev/null', f.path]);
    await f.writeAsString(value, flush: true);
  }

  Future<void> delete(String name) async {
    if (_useKeystore) return _keystore.delete(key: name);
    final f = await _file(name);
    if (await f.exists()) await f.delete();
  }
}
