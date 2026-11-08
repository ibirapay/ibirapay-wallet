import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/backup_crypto.dart';

const words = [
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'about',
];
const fastParams = Argon2Params(memory: 1024, iterations: 1);
const password = 'senha-segura-123';

void main() {
  test('backup round trip uses the standard Argon2id parameters once', () async {
    final stopwatch = Stopwatch()..start();
    final blob = await encryptBackup(words, password, shopId: 'loja-42');
    final decoded = jsonDecode(blob) as Map<String, dynamic>;
    expect(decoded, containsPair('v', 1));
    expect(decoded, containsPair('kdf', 'argon2id'));
    expect(decoded, containsPair('m', 65536));
    expect(decoded, containsPair('t', 3));
    expect(decoded, containsPair('p', 1));
    expect(await decryptBackup(blob, password, shopId: 'loja-42'), words);
    stopwatch.stop();
    // Kept visible so the acceptance run records the cost on its actual host.
    // ignore: avoid_print
    print('standard Argon2id round trip: ${stopwatch.elapsedMilliseconds} ms');
  });

  test('wrong password and wrong shop AAD have the same error', () async {
    final blob = await encryptBackup(words, password, shopId: 'loja-42', params: fastParams);
    final matcher = throwsA(
      isA<BackupError>().having((error) => error.message, 'message', 'senha errada ou backup corrompido'),
    );
    await expectLater(decryptBackup(blob, 'senha-errada-123', shopId: 'loja-42'), matcher);
    await expectLater(decryptBackup(blob, password, shopId: 'outra-loja'), matcher);
  });

  test('tampered ciphertext fails authentication', () async {
    final blob = await encryptBackup(words, password, shopId: 'loja-42', params: fastParams);
    final decoded = jsonDecode(blob) as Map<String, dynamic>;
    final cipherText = base64Decode(decoded['ct'] as String)..[0] ^= 1;
    decoded['ct'] = base64Encode(cipherText);
    await expectLater(
      decryptBackup(jsonEncode(decoded), password, shopId: 'loja-42'),
      throwsA(isA<BackupError>().having((error) => error.message, 'message', 'senha errada ou backup corrompido')),
    );
  });

  test('oversized Argon2 memory is refused before decoding or running the KDF', () async {
    final blob = jsonEncode({'v': 1, 'kdf': 'argon2id', 'm': 1048577, 't': 1, 'p': 1, 'salt': false});
    await expectLater(
      decryptBackup(blob, password, shopId: 'loja-42'),
      throwsA(isA<BackupError>().having((error) => error.message, 'message', 'parâmetros do backup excedem o limite')),
    );
  });

  test('hostile restore params are refused: memory over 256 MiB or below 8 x parallelism', () async {
    for (final (m, p) in [(262145, 1), (1, 64)]) {
      final blob = jsonEncode({'v': 1, 'kdf': 'argon2id', 'm': m, 't': 1, 'p': p, 'salt': false});
      await expectLater(
        decryptBackup(blob, password, shopId: 'loja-42'),
        throwsA(
          isA<BackupError>().having((error) => error.message, 'message', 'parâmetros do backup excedem o limite'),
        ),
      );
    }
  });

  test('password rule is exactly a 12-character minimum', () {
    expect(passwordProblem('12345678901'), isNotNull);
    expect(passwordProblem('123456789012'), isNull);
    expect(passwordProblem('uma senha bem maior'), isNull);
  });
}
