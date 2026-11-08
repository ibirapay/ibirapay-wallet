import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/wallet.dart';
import 'package:wallet/wallet_seed.dart';

void main() {
  final words = [...List.filled(11, 'abandon'), 'about'];

  test('one 12-word wallet gives the Spark key and the Polygon and Solana addresses', () async {
    final w = await deriveWallet(words);
    expect(w.polygon, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94'); // MetaMask account 1 for these words
    expect(w.solana, 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk'); // Phantom account 1; cross-checked in Python
    expect(w.sparkCredential, 'entropy:a61babab9f332be598b4873d07d3c8a1189e500e6868f4e3b81d947621036703');
  });

  test('the credential never contains the words and is deterministic', () async {
    final a = await deriveWallet(words);
    final b = await deriveWallet(words);
    expect(a.sparkCredential, b.sparkCredential);
    for (final word in words.toSet()) {
      expect(a.sparkCredential, isNot(contains(word)));
    }
  });

  test('a phrase with a bad checksum is refused', () async {
    await expectLater(deriveWallet([...List.filled(12, 'abandon')]), throwsA(isA<WalletError>()));
  });

  test('sparkEntropyFromCredential reads only well-formed entropy credentials', () {
    final h = 'ab' * 32;
    expect(sparkEntropyFromCredential('entropy:$h'), hasLength(32));
    expect(sparkEntropyFromCredential('entropy:$h')!.first, 0xab);
    expect(sparkEntropyFromCredential('entropy:${'ab' * 31}'), isNull);
    expect(sparkEntropyFromCredential('entropy:${'zz' * 32}'), isNull);
    expect(sparkEntropyFromCredential('entropy:${'AB' * 32}'), isNull); // saved lower case only
    expect(sparkEntropyFromCredential('abandon abandon'), isNull);
  });
}
