import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/bip39_words.dart';
import 'package:wallet/wallet_seed.dart';
import 'package:pointycastle/export.dart';

Uint8List hexBytes(String source) =>
    Uint8List.fromList([for (var i = 0; i < source.length; i += 2) int.parse(source.substring(i, i + 2), radix: 16)]);

String hex(Uint8List bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('BIP39 English list has the required contents', () {
    expect(bip39English, hasLength(2048));
    final bytes = Uint8List.fromList(utf8.encode('${bip39English.join('\n')}\n'));
    expect(hex(SHA256Digest().process(bytes)), '2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda');
  });

  test('BIP39 official zero-entropy mnemonic and TREZOR seed', () {
    final words = entropyToMnemonic(Uint8List(16));
    expect(words, [...List.filled(11, 'abandon'), 'about']);
    expect(validMnemonic(words), isTrue);
    final seed = mnemonicToSeed(words, passphrase: 'TREZOR');
    expect(
      hex(seed),
      'c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553'
      '1f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04',
    );
    wipe(seed);
  });

  test('BIP39 validation rejects bad checksum and unknown word', () {
    final words = [...List.filled(11, 'abandon'), 'about'];
    expect(validMnemonic([...words]..[11] = 'abandon'), isFalse);
    expect(validMnemonic([...words]..[4] = 'ibirapay'), isFalse);
    expect(validMnemonic(newMnemonic()), isTrue);
  });

  test('BIP39 supports 256-bit entropy', () {
    final words = entropyToMnemonic(Uint8List(32));
    expect(words, [...List.filled(23, 'abandon'), 'art']);
    expect(validMnemonic(words), isTrue);
  });

  test('BIP32 official vector 1 master and hardened child xpubs', () {
    final seed = hexBytes('000102030405060708090a0b0c0d0e0f');
    expect(
      bip32Xpub(seed, const []),
      'xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8',
    );
    expect(
      bip32Xpub(seed, const [0x80000000]),
      'xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw',
    );
  });

  test('EVM private path and account xpub derive the MetaMask account 1 address', () {
    final words = [...List.filled(11, 'abandon'), 'about'];
    final seed = mnemonicToSeed(words);
    final derived = deriveEvm(seed);
    expect(derived.address, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
    expect(evmAddressFromXpub(derived.accountXpub, 0), derived.address);
    wipe(seed);
  });

  test('EIP-55 checksum matches the published mixed-case vector', () {
    expect(
      checksumEvmAddress('0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed'),
      '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
    );
  });

  test('wipe clears secret bytes', () {
    final secret = Uint8List.fromList([1, 2, 3]);
    wipe(secret);
    expect(secret, [0, 0, 0]);
  });

  test('SLIP-0010 ed25519 official vector 1 (m/0h) and hardened-only paths', () {
    final seed = hexBytes('000102030405060708090a0b0c0d0e0f');
    expect(hex(slip10Ed25519(seed, const [0])), '68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3');
    expect(hex(slip10Ed25519(seed, const [0, 1])), 'b1d0bad404bf35da785a64ca1ac54b2617211d2777696fbffaf208f746ae84f2');
    expect(() => slip10Ed25519(seed, const [0x80000000]), throwsA(isA<WalletError>()));
  });

  test('Spark entropy is 32 bytes, stable, and a different domain gives an unrelated key', () {
    final seed = mnemonicToSeed([...List.filled(11, 'abandon'), 'about']);
    final a = sparkEntropy(seed);
    expect(a, hasLength(32));
    expect(hex(a), 'a61babab9f332be598b4873d07d3c8a1189e500e6868f4e3b81d947621036703'); // cross-checked in Python
    expect(sparkEntropy(seed), a);
    expect(hex(a), isNot(hex(seed.sublist(0, 32))));
    expect(hex(slip10Ed25519(seed, const [44, 501, 0, 0])), isNot(hex(a)));
  });
}
