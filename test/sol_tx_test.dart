import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/base58.dart';
import 'package:wallet/evm_tx.dart' show bytesToHex, hexToBytes;
import 'package:wallet/sol_tx.dart';
import 'package:wallet/wallet_seed.dart';

import 'stable_vectors.dart';

void main() {
  final seed = mnemonicToSeed(vMnemonic.split(' '));
  final key = slip10Ed25519(seed, const [44, 501, 0, 0]);
  final owner = solPubkey(vSolAddress);

  test('base58 decode inverts encode, keeps leading zero bytes, and refuses bad characters', () {
    final b = Uint8List.fromList([0, 0, 1, 2, 255, 128]);
    expect(base58Decode(base58Encode(b)), b);
    expect(base58Decode('1'), [0]);
    expect(base58Decode(''), isEmpty);
    expect(() => base58Decode('0OIl'), throwsFormatException);
    expect(() => solPubkey('abc'), throwsFormatException);
    expect(solPubkey(vSolAddress).length, 32);
  });

  test('the test mnemonic derives the address the independent implementation has', () async {
    final pub = await (await Ed25519().newKeyPairFromSeed(key)).extractPublicKey();
    expect(base58Encode(pub.bytes), vSolAddress);
  });

  test('on-curve test agrees with the reference on keys, program addresses and random strings', () {
    for (final (hex, expected) in vOnCurve) {
      expect(onEd25519Curve(hexToBytes(hex)), expected, reason: hex);
    }
  });

  test('compact-u16', () {
    expect(compactU16(0), [0]);
    expect(compactU16(127), [127]);
    expect(compactU16(128), [0x80, 1]);
    expect(compactU16(16384), [0x80, 0x80, 1]);
  });

  test('associated token accounts equal the reference', () {
    expect(base58Encode(associatedTokenAccount(owner, solPubkey(vSol[0].$1))), vSolOwnerUsdcAta);
    for (final (mint, _, _, source, dest, _, _) in vSol) {
      expect(base58Encode(associatedTokenAccount(owner, solPubkey(mint))), source);
      expect(base58Encode(associatedTokenAccount(solPubkey(vSolRecipient), solPubkey(mint))), dest);
    }
  });

  test('messages and signatures equal the solders output byte for byte', () async {
    final bh = solPubkey(vSolBlockhash);
    for (final (mint, amount, create, source, dest, message, signature) in vSol) {
      final m = solPubkey(mint);
      final recipient = solPubkey(vSolRecipient);
      final msg = compileMessage(
        payer: owner,
        blockhash: bh,
        instructions: [
          if (create) createAtaIdempotent(payer: owner, ata: solPubkey(dest), owner: recipient, mint: m),
          transferChecked(source: solPubkey(source), mint: m, dest: solPubkey(dest), authority: owner, amount: BigInt.from(amount), decimals: 6),
        ],
      );
      expect(bytesToHex(msg), message, reason: '$mint $amount create=$create');
      final signed = await signMessage(msg, key, expectedPubkey: owner);
      expect(bytesToHex(signed.signature), signature);
      expect(bytesToHex(signed.wire), '01$signature$message');
    }
  });

  test('a key that is not the wallet is refused, and an amount beyond u64 is refused', () async {
    final other = Uint8List(32)..[0] = 9;
    final msg = compileMessage(payer: owner, blockhash: solPubkey(vSolBlockhash), instructions: const []);
    await expectLater(signMessage(msg, other, expectedPubkey: owner), throwsA(isA<WalletError>()));
    expect(
      () => transferChecked(source: owner, mint: owner, dest: owner, authority: owner, amount: BigInt.one << 64, decimals: 6),
      throwsArgumentError,
    );
  });
}
