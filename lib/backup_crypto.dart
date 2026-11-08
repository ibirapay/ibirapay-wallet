import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class BackupError implements Exception {
  BackupError(this.message);

  final String message;

  @override
  String toString() => message;
}

class Argon2Params {
  const Argon2Params({required this.memory, required this.iterations, this.parallelism = 1});

  static const standard = Argon2Params(memory: 65536, iterations: 3);

  final int memory;
  final int iterations;
  final int parallelism;
}

String? passwordProblem(String pw) => pw.length < 12 ? 'a senha deve ter pelo menos 12 caracteres' : null;

Future<String> encryptBackup(
  List<String> words,
  String password, {
  required String shopId,
  Argon2Params params = Argon2Params.standard,
}) async {
  final problem = passwordProblem(password);
  if (problem != null) throw BackupError(problem);
  _checkParams(params);
  final random = Random.secure();
  final salt = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
  final nonce = Uint8List.fromList(List.generate(12, (_) => random.nextInt(256)));
  final passwordBytes = Uint8List.fromList(utf8.encode(password));
  final clearText = Uint8List.fromList(utf8.encode(words.join(' ')));
  try {
    final key = await _deriveKey(passwordBytes, salt, params);
    final box = await AesGcm.with256bits().encrypt(
      clearText,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode('ibirapay-backup-v1:$shopId'),
    );
    final cipherText = Uint8List(box.cipherText.length + box.mac.bytes.length)
      ..setRange(0, box.cipherText.length, box.cipherText)
      ..setRange(box.cipherText.length, box.cipherText.length + box.mac.bytes.length, box.mac.bytes);
    return jsonEncode({
      'v': 1,
      'kdf': 'argon2id',
      'm': params.memory,
      't': params.iterations,
      'p': params.parallelism,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ct': base64Encode(cipherText),
    });
  } finally {
    passwordBytes.fillRange(0, passwordBytes.length, 0);
    clearText.fillRange(0, clearText.length, 0);
    salt.fillRange(0, salt.length, 0);
  }
}

Future<List<String>> decryptBackup(String json, String password, {required String shopId}) async {
  late Map<String, dynamic> blob;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    blob = decoded;
  } catch (_) {
    throw BackupError('backup inválido');
  }
  if (blob['v'] != 1 || blob['kdf'] != 'argon2id') throw BackupError('versão de backup não suportada');
  final params = Argon2Params(
    memory: _intField(blob, 'm'),
    iterations: _intField(blob, 't'),
    parallelism: _intField(blob, 'p'),
  );
  _checkParams(params);
  late Uint8List salt;
  late Uint8List nonce;
  late Uint8List cipherText;
  try {
    salt = Uint8List.fromList(base64Decode(blob['salt'] as String));
    nonce = Uint8List.fromList(base64Decode(blob['nonce'] as String));
    cipherText = Uint8List.fromList(base64Decode(blob['ct'] as String));
    if (salt.length != 16 || nonce.length != 12 || cipherText.length < 16) throw const FormatException();
  } catch (_) {
    throw BackupError('backup inválido');
  }
  final passwordBytes = Uint8List.fromList(utf8.encode(password));
  try {
    final key = await _deriveKey(passwordBytes, salt, params);
    final macOffset = cipherText.length - 16;
    final box = SecretBox(cipherText.sublist(0, macOffset), nonce: nonce, mac: Mac(cipherText.sublist(macOffset)));
    try {
      final clearText = Uint8List.fromList(
        await AesGcm.with256bits().decrypt(box, secretKey: key, aad: utf8.encode('ibirapay-backup-v1:$shopId')),
      );
      try {
        final phrase = utf8.decode(clearText);
        return phrase.split(' ');
      } finally {
        clearText.fillRange(0, clearText.length, 0);
      }
    } on SecretBoxAuthenticationError {
      throw BackupError('senha errada ou backup corrompido');
    }
  } finally {
    passwordBytes.fillRange(0, passwordBytes.length, 0);
    salt.fillRange(0, salt.length, 0);
  }
}

Future<SecretKey> _deriveKey(Uint8List password, Uint8List salt, Argon2Params params) {
  return Argon2id(
    parallelism: params.parallelism,
    memory: params.memory,
    iterations: params.iterations,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(password), nonce: salt);
}

void _checkParams(Argon2Params params) {
  if (params.memory <= 0 || params.iterations <= 0 || params.parallelism <= 0) {
    throw BackupError('parâmetros do backup inválidos');
  }
  if (params.memory > 256 * 1024 ||
      params.memory < 8 * params.parallelism ||
      params.iterations > 10 ||
      params.parallelism > 64) {
    throw BackupError('parâmetros do backup excedem o limite');
  }
}

int _intField(Map<String, dynamic> blob, String name) {
  final value = blob[name];
  if (value is! int) throw BackupError('backup inválido');
  return value;
}
