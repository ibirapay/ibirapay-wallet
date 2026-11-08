// An SPL-token transfer on Solana: the associated token account (a program-derived address, which needs an ed25519 on-curve test),
// the legacy transaction message, and its signature. No network here, so every byte can be tested.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' show SHA256Digest;

import 'base58.dart';
import 'evm_tx.dart' show bytesToHex;
import 'wallet_seed.dart' show WalletError;

const tokenProgramId = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const ataProgramId = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const systemProgramId = '11111111111111111111111111111111';

/// The 32 bytes of a Solana address; throws [FormatException] when [address] is not base58 of exactly 32 bytes.
Uint8List solPubkey(String address) {
  final b = base58Decode(address.trim());
  if (b.length != 32) throw const FormatException('endereço Solana inválido');
  return b;
}

final _p = (BigInt.one << 255) - BigInt.from(19);
final _d = (BigInt.from(-121665) * BigInt.from(121666).modInverse(_p)) % _p;

BigInt _leInt(List<int> b) => BigInt.parse(bytesToHex(b.reversed.toList()), radix: 16);

/// Whether [key] decompresses to a point of the ed25519 curve (what Solana's `is_on_curve` asks). A program-derived address
/// must be OFF the curve, so that no private key can exist for it.
bool onEd25519Curve(Uint8List key) {
  if (key.length != 32) throw ArgumentError('chave de 32 bytes');
  final bytes = Uint8List.fromList(key)..[31] &= 0x7f; // the top bit is only the sign of x
  final y = _leInt(bytes) % _p;
  final y2 = (y * y) % _p;
  final u = (y2 - BigInt.one) % _p;
  final v = (_d * y2 + BigInt.one) % _p;
  final ratio = (u * v.modInverse(_p)) % _p; // x^2
  return ratio == BigInt.zero || ratio.modPow((_p - BigInt.one) >> 1, _p) == BigInt.one;
}

Uint8List _sha256(List<int> data) => SHA256Digest().process(Uint8List.fromList(data));

/// The program-derived address of [seeds] under [programId]: the first bump from 255 down whose hash is off the curve.
Uint8List findProgramAddress(List<Uint8List> seeds, Uint8List programId) {
  for (var bump = 255; bump >= 0; bump--) {
    final h = _sha256([for (final s in seeds) ...s, bump, ...programId, ...utf8.encode('ProgramDerivedAddress')]);
    if (!onEd25519Curve(h)) return h;
  }
  throw StateError('sem endereço derivado');
}

/// The associated token account of [owner] for [mint] under the legacy Token program.
Uint8List associatedTokenAccount(Uint8List owner, Uint8List mint) =>
    findProgramAddress([owner, solPubkey(tokenProgramId), mint], solPubkey(ataProgramId));

class Meta {
  const Meta(this.key, {this.signer = false, this.writable = false});
  final Uint8List key;
  final bool signer;
  final bool writable;
}

class Ix {
  const Ix(this.program, this.accounts, this.data);
  final Uint8List program;
  final List<Meta> accounts;
  final Uint8List data;
}

/// Creates [ata] for [owner] and [mint], paid by [payer]; does nothing when it already exists, so a race is harmless.
Ix createAtaIdempotent({required Uint8List payer, required Uint8List ata, required Uint8List owner, required Uint8List mint}) => Ix(
  solPubkey(ataProgramId),
  [
    Meta(payer, signer: true, writable: true),
    Meta(ata, writable: true),
    Meta(owner),
    Meta(mint),
    Meta(solPubkey(systemProgramId)),
    Meta(solPubkey(tokenProgramId)),
  ],
  Uint8List.fromList(const [1]),
);

/// SPL `TransferChecked`: the program verifies [decimals] against the mint, so an amount can never be off by a power of ten.
Ix transferChecked({
  required Uint8List source,
  required Uint8List mint,
  required Uint8List dest,
  required Uint8List authority,
  required BigInt amount,
  required int decimals,
}) {
  if (amount <= BigInt.zero || amount.bitLength > 64) throw ArgumentError('valor fora do intervalo');
  final data = Uint8List(10)
    ..[0] = 12
    ..[9] = decimals;
  ByteData.sublistView(data).setUint64(1, amount.toUnsigned(64).toInt(), Endian.little);
  return Ix(solPubkey(tokenProgramId), [
    Meta(source, writable: true),
    Meta(mint),
    Meta(dest, writable: true),
    Meta(authority, signer: true),
  ], data);
}

List<int> compactU16(int n) {
  final out = <int>[];
  var v = n;
  while (true) {
    final low = v & 0x7f;
    v >>= 7;
    if (v == 0) {
      out.add(low);
      return out;
    }
    out.add(low | 0x80);
  }
}

int _cmp(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}

/// A legacy message: [payer] pays and signs, accounts are grouped (signer+writable, signer, writable, read-only) and sorted by
/// key inside each group, the same compile order as the reference SDK.
Uint8List compileMessage({required Uint8List payer, required Uint8List blockhash, required List<Ix> instructions}) {
  if (blockhash.length != 32) throw ArgumentError('blockhash de 32 bytes');
  final flags = <String, ({Uint8List key, bool signer, bool writable})>{};
  void add(Uint8List key, bool signer, bool writable) {
    final id = bytesToHex(key);
    final old = flags[id];
    flags[id] = (key: key, signer: signer || (old?.signer ?? false), writable: writable || (old?.writable ?? false));
  }

  for (final ix in instructions) {
    add(ix.program, false, false);
    for (final m in ix.accounts) {
      add(m.key, m.signer, m.writable);
    }
  }
  final payerId = bytesToHex(payer);
  flags.remove(payerId);
  List<Uint8List> group(bool signer, bool writable) =>
      (flags.values.where((f) => f.signer == signer && f.writable == writable).map((f) => f.key).toList())..sort(_cmp);
  final signWritable = [payer, ...group(true, true)];
  final signReadonly = group(true, false);
  final writable = group(false, true);
  final readonly = group(false, false);
  final keys = [...signWritable, ...signReadonly, ...writable, ...readonly];
  final index = {for (var i = 0; i < keys.length; i++) bytesToHex(keys[i]): i};
  return Uint8List.fromList([
    signWritable.length + signReadonly.length,
    signReadonly.length,
    readonly.length,
    ...compactU16(keys.length),
    for (final k in keys) ...k,
    ...blockhash,
    ...compactU16(instructions.length),
    for (final ix in instructions) ...[
      index[bytesToHex(ix.program)]!,
      ...compactU16(ix.accounts.length),
      for (final m in ix.accounts) index[bytesToHex(m.key)]!,
      ...compactU16(ix.data.length),
      ...ix.data,
    ],
  ]);
}

/// A signed one-signature transaction: wire bytes and its id (the base58 signature).
class SolSigned {
  const SolSigned(this.wire, this.signature);
  final Uint8List wire;
  final Uint8List signature;
  String get id => base58Encode(signature);
}

/// The wire form of [message] with [signature] in the first slot.
Uint8List wireTransaction(Uint8List message, List<int> signature) => Uint8List.fromList([1, ...signature, ...message]);

/// Signs [message] with the 32-byte ed25519 [seed] (the caller wipes it). The signature is verified against [expectedPubkey]
/// before anything is returned.
Future<SolSigned> signMessage(Uint8List message, Uint8List seed, {required Uint8List expectedPubkey}) async {
  final algo = Ed25519();
  final pair = await algo.newKeyPairFromSeed(seed);
  final pub = await pair.extractPublicKey();
  if (bytesToHex(pub.bytes) != bytesToHex(expectedPubkey)) throw WalletError('a chave não corresponde à carteira; nada foi enviado');
  final sig = await algo.sign(message, keyPair: pair);
  if (!await algo.verify(message, signature: sig)) throw WalletError('assinatura inválida; nada foi enviado');
  final bytes = Uint8List.fromList(sig.bytes);
  return SolSigned(wireTransaction(message, bytes), bytes);
}
