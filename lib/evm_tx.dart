// An ERC-20 transfer on Polygon as an EIP-1559 (type 2) transaction: RLP, the signing hash, the signature, and the check that the
// signature recovers to the wallet's own address before anything is broadcast. No network here, so every byte can be tested.
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'wallet_seed.dart';

const polygonChainId = 137;

final _curve = ECCurve_secp256k1();
final _halfN = _curve.n >> 1;

String bytesToHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List hexToBytes(String h) {
  var s = h.startsWith('0x') ? h.substring(2) : h;
  if (s.length.isOdd) s = '0$s';
  return Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
}

Uint8List _beBytes(BigInt v) {
  var h = v.toRadixString(16);
  if (h.length.isOdd) h = '0$h';
  return hexToBytes(h);
}

BigInt _bigInt(List<int> b) => b.isEmpty ? BigInt.zero : BigInt.parse(bytesToHex(b), radix: 16);

/// An RLP integer: big-endian without leading zeros, zero is the empty string.
Uint8List rlpInt(BigInt v) {
  if (v.isNegative) throw ArgumentError('rlp: inteiro negativo');
  return v == BigInt.zero ? Uint8List(0) : _beBytes(v);
}

List<int> _prefix(int length, int offset) {
  if (length < 56) return [offset + length];
  final l = _beBytes(BigInt.from(length));
  return [offset + 55 + l.length, ...l];
}

/// RLP of [item]: a [Uint8List] is a byte string, any other [List] is a list of items.
Uint8List rlp(Object item) {
  if (item is Uint8List) {
    if (item.length == 1 && item[0] < 0x80) return item;
    return Uint8List.fromList([..._prefix(item.length, 0x80), ...item]);
  }
  if (item is List) {
    final body = <int>[for (final i in item) ...rlp(i as Object)];
    return Uint8List.fromList([..._prefix(body.length, 0xc0), ...body]);
  }
  throw ArgumentError('rlp: tipo ${item.runtimeType}');
}

/// The 20 bytes of an `0x` + 40 hex address (any case; the checksum is the caller's to judge).
Uint8List evmAddressBytes(String address) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) throw ArgumentError('endereço EVM inválido');
  return hexToBytes(address);
}

/// `transfer(address,uint256)` calldata.
Uint8List erc20TransferData(String to, BigInt amount) {
  if (amount <= BigInt.zero || amount.bitLength > 256) throw ArgumentError('valor fora do intervalo');
  final data = Uint8List(68)..setRange(0, 4, const [0xa9, 0x05, 0x9c, 0xbb]);
  data.setRange(16, 36, evmAddressBytes(to));
  final a = _beBytes(amount);
  data.setRange(68 - a.length, 68, a);
  return data;
}

class Eip1559Tx {
  const Eip1559Tx({
    required this.nonce,
    required this.maxPriorityFee,
    required this.maxFee,
    required this.gasLimit,
    required this.to,
    required this.data,
  });
  final int nonce;
  final BigInt maxPriorityFee;
  final BigInt maxFee;
  final int gasLimit;

  /// The 20-byte contract the call goes to (the token); the transaction itself carries no value.
  final Uint8List to;
  final Uint8List data;

  List<Object> _fields() => [
    rlpInt(BigInt.from(polygonChainId)),
    rlpInt(BigInt.from(nonce)),
    rlpInt(maxPriorityFee),
    rlpInt(maxFee),
    rlpInt(BigInt.from(gasLimit)),
    to,
    Uint8List(0),
    data,
    <Object>[],
  ];

  Uint8List get signingHash => keccak256(Uint8List.fromList([0x02, ...rlp(_fields())]));
}

class SignedTx {
  const SignedTx(this.raw, this.hash);
  final Uint8List raw;
  final Uint8List hash;
  String get hashHex => '0x${bytesToHex(hash)}';
  String get rawHex => '0x${bytesToHex(raw)}';
}

/// The compressed public key that signed [hash] with (r, s) and recovery id [v] (0 or 1).
Uint8List recoverPublicKey(Uint8List hash, BigInt r, BigInt s, int v) {
  final n = _curve.n;
  if (v != 0 && v != 1) throw ArgumentError('v inválido');
  if (r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) throw ArgumentError('assinatura inválida');
  final point = _curve.curve.decompressPoint(v, r);
  final rInv = r.modInverse(n);
  final u1 = (-_bigInt(hash) * rInv) % n;
  final u2 = (s * rInv) % n;
  final q = (_curve.G * u1)! + (point * u2)!;
  if (q == null || q.isInfinity) throw ArgumentError('assinatura inválida');
  return q.getEncoded(true);
}

/// Signs [tx] with [privateKey] (32 bytes; the caller wipes it) and refuses to return anything that does not recover to
/// [expectedAddress]: a wrong key or a bad signature never reaches the network.
SignedTx signTx(Eip1559Tx tx, Uint8List privateKey, {required String expectedAddress}) {
  final hash = tx.signingHash;
  final d = _bigInt(privateKey);
  final signer = ECDSASigner(null, HMac(SHA256Digest(), 64))..init(true, PrivateKeyParameter(ECPrivateKey(d, _curve)));
  final sig = signer.generateSignature(hash) as ECSignature;
  final r = sig.r;
  final s = sig.s > _halfN ? _curve.n - sig.s : sig.s; // EIP-2: low s only
  final own = (_curve.G * d)!.getEncoded(true);
  int? parity;
  for (final v in const [0, 1]) {
    final rec = recoverPublicKey(hash, r, s, v);
    if (bytesToHex(rec) == bytesToHex(own)) parity = v;
  }
  if (parity == null || evmAddress(own) != checksumEvmAddress(expectedAddress)) {
    throw WalletError('a assinatura não corresponde à carteira; nada foi enviado');
  }
  final raw = Uint8List.fromList([
    0x02,
    ...rlp([...tx._fields(), rlpInt(BigInt.from(parity)), rlpInt(r), rlpInt(s)]),
  ]);
  return SignedTx(raw, keccak256(raw));
}
