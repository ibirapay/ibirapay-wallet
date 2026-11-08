import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'bip39_words.dart';

class WalletError implements Exception {
  WalletError(this.message);

  final String message;

  @override
  String toString() => message;
}

final _curve = ECCurve_secp256k1();
final _wordIndexes = {for (var i = 0; i < bip39English.length; i++) bip39English[i]: i};
const _base58Alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

void wipe(Uint8List b) => b.fillRange(0, b.length, 0);

/// Dart Strings cannot be wiped, so keep the returned words only for display or backup.
List<String> newMnemonic() {
  final random = Random.secure();
  final entropy = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
  try {
    return entropyToMnemonic(entropy);
  } finally {
    wipe(entropy);
  }
}

List<String> entropyToMnemonic(Uint8List entropy) {
  if (entropy.length != 16 && entropy.length != 32) throw WalletError('entropia deve ter 16 ou 32 bytes');
  final checksumBits = entropy.length * 8 ~/ 32;
  final checksum = _sha256(entropy)[0];
  final words = <String>[];
  var value = 0;
  var bits = 0;
  for (final byte in entropy) {
    value = (value << 8) | byte;
    bits += 8;
    if (bits >= 11) {
      bits -= 11;
      words.add(bip39English[(value >> bits) & 0x7ff]);
    }
  }
  value = (value << checksumBits) | (checksum >> (8 - checksumBits));
  bits += checksumBits;
  while (bits >= 11) {
    bits -= 11;
    words.add(bip39English[(value >> bits) & 0x7ff]);
  }
  return words;
}

bool validMnemonic(List<String> words) {
  if (words.length != 12 && words.length != 24) return false;
  var value = 0;
  var bits = 0;
  final bytes = <int>[];
  for (final word in words) {
    final index = _wordIndexes[word];
    if (index == null) return false;
    value = (value << 11) | index;
    bits += 11;
    while (bits >= 8) {
      bits -= 8;
      bytes.add((value >> bits) & 0xff);
    }
  }
  final checksumBits = words.length ~/ 3;
  final entropy = Uint8List.fromList(bytes.take((words.length * 11 - checksumBits) ~/ 8).toList());
  final expected = _sha256(entropy)[0] >> (8 - checksumBits);
  final actual = value & ((1 << checksumBits) - 1);
  wipe(entropy);
  return actual == expected;
}

/// The English BIP39 words are already NFKD ASCII. The passphrase is encoded as supplied.
Uint8List mnemonicToSeed(List<String> words, {String passphrase = ''}) {
  if (!validMnemonic(words)) throw WalletError('frase de recuperação inválida');
  final password = Uint8List.fromList(utf8.encode(words.join(' ')));
  final salt = Uint8List.fromList(utf8.encode('mnemonic$passphrase'));
  try {
    final derivator = PBKDF2KeyDerivator(HMac(SHA512Digest(), 128))..init(Pbkdf2Parameters(salt, 2048, 64));
    return derivator.process(password);
  } finally {
    wipe(password);
    wipe(salt);
  }
}

/// Derives and serializes an xpub. Hardened path components have bit 31 set.
String bip32Xpub(Uint8List seed, List<int> path) {
  var node = _master(seed);
  try {
    for (final index in path) {
      final next = _privateChild(node, index);
      node.wipeSecrets();
      node = next;
    }
    return _serializeXpub(node.publicKey, node.chainCode, node.depth, node.parentFingerprint, node.childNumber);
  } finally {
    node.wipeSecrets();
  }
}

({String address, String accountXpub}) deriveEvm(Uint8List seed) {
  var node = _master(seed);
  try {
    for (final index in const [0x8000002c, 0x8000003c, 0x80000000]) {
      final next = _privateChild(node, index);
      node.wipeSecrets();
      node = next;
    }
    final accountXpub = _serializeXpub(
      node.publicKey,
      node.chainCode,
      node.depth,
      node.parentFingerprint,
      node.childNumber,
    );
    for (final index in const [0, 0]) {
      final next = _privateChild(node, index);
      node.wipeSecrets();
      node = next;
    }
    return (address: evmAddress(node.publicKey), accountXpub: accountXpub);
  } finally {
    node.wipeSecrets();
  }
}

/// The secp256k1 key of m/44'/60'/0'/0/0, the one behind the address [deriveEvm] returns. Only for signing a send: the caller wipes it.
Uint8List deriveEvmPrivateKey(Uint8List seed) {
  var node = _master(seed);
  try {
    for (final index in const [0x8000002c, 0x8000003c, 0x80000000, 0, 0]) {
      final next = _privateChild(node, index);
      node.wipeSecrets();
      node = next;
    }
    return Uint8List.fromList(node.privateKey);
  } finally {
    node.wipeSecrets();
  }
}

Uint8List keccak256(Uint8List data) => _keccak(data);

/// SLIP-0010 ed25519 child key (32 bytes) at [path]. Every step is hardened: ed25519 has no public derivation, so a Solana
/// address can be kept on the till but never an xpub.
Uint8List slip10Ed25519(Uint8List seed, List<int> path) {
  var node = _hmacSha512(Uint8List.fromList(utf8.encode('ed25519 seed')), seed);
  try {
    for (final index in path) {
      if (index < 0 || index >= 0x80000000) throw WalletError('índice de derivação inválido');
      final data = Uint8List(37)..setRange(1, 33, node.sublist(0, 32));
      ByteData.sublistView(data).setUint32(33, index | 0x80000000);
      final next = _hmacSha512(node.sublist(32), data);
      wipe(data);
      wipe(node);
      node = next;
    }
    return Uint8List.fromList(node.sublist(0, 32));
  } finally {
    wipe(node);
  }
}

/// The 32 bytes the Spark wallet is built from: HMAC-SHA512 over the BIP39 seed under a fixed domain tag. Another tag
/// gives an unrelated key, so the till can hold this one without holding what derives the USDT/USDC addresses.
Uint8List sparkEntropy(Uint8List seed) {
  final out = _hmacSha512(Uint8List.fromList(utf8.encode('ibirapay/spark/v1')), seed);
  try {
    return Uint8List.fromList(out.sublist(0, 32));
  } finally {
    wipe(out);
  }
}

String evmAddressFromXpub(String xpub, int index) {
  if (index < 0 || index >= 0x80000000) throw WalletError('índice público inválido');
  var node = _parseXpub(xpub);
  try {
    for (final childIndex in [0, index]) {
      final next = _publicChild(node, childIndex);
      node.wipeSecrets();
      node = next;
    }
    return evmAddress(node.publicKey);
  } finally {
    node.wipeSecrets();
  }
}

String evmAddress(Uint8List compressedOrUncompressedPubKey) {
  ECPoint? point;
  try {
    point = _curve.curve.decodePoint(compressedOrUncompressedPubKey);
  } catch (_) {
    throw WalletError('chave pública inválida');
  }
  if (point == null || point.isInfinity) throw WalletError('chave pública inválida');
  final encoded = point.getEncoded(false);
  final hash = _keccak(Uint8List.sublistView(encoded, 1));
  return checksumEvmAddress(_hex(Uint8List.sublistView(hash, 12)));
}

String checksumEvmAddress(String address) {
  final lowercase = (address.startsWith('0x') ? address.substring(2) : address).toLowerCase();
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(lowercase)) throw WalletError('endereço inválido');
  return _checksumAddress(lowercase);
}

class _PrivateNode {
  _PrivateNode(this.privateKey, this.chainCode, this.depth, this.parentFingerprint, this.childNumber);

  final Uint8List privateKey;
  final Uint8List chainCode;
  final int depth;
  final int parentFingerprint;
  final int childNumber;

  Uint8List get publicKey => (_curve.G * _bytesToBigInt(privateKey))!.getEncoded(true);

  void wipeSecrets() {
    wipe(privateKey);
    wipe(chainCode);
  }
}

class _PublicNode {
  _PublicNode(this.publicKey, this.chainCode, this.depth, this.parentFingerprint, this.childNumber);

  final Uint8List publicKey;
  final Uint8List chainCode;
  final int depth;
  final int parentFingerprint;
  final int childNumber;

  void wipeSecrets() => wipe(chainCode);
}

_PrivateNode _master(Uint8List seed) {
  final digest = _hmacSha512(Uint8List.fromList(utf8.encode('Bitcoin seed')), seed);
  final key = Uint8List.fromList(digest.sublist(0, 32));
  final chain = Uint8List.fromList(digest.sublist(32));
  wipe(digest);
  final scalar = _bytesToBigInt(key);
  if (scalar == BigInt.zero || scalar >= _curve.n) {
    wipe(key);
    wipe(chain);
    throw WalletError('semente BIP32 inválida');
  }
  return _PrivateNode(key, chain, 0, 0, 0);
}

_PrivateNode _privateChild(_PrivateNode parent, int index) {
  if (index < 0 || index > 0xffffffff) throw WalletError('índice BIP32 inválido');
  final data = Uint8List(37);
  if (index >= 0x80000000) {
    data.setRange(1, 33, parent.privateKey);
  } else {
    data.setRange(0, 33, parent.publicKey);
  }
  ByteData.sublistView(data).setUint32(33, index);
  final digest = _hmacSha512(parent.chainCode, data);
  wipe(data);
  final left = _bytesToBigInt(Uint8List.sublistView(digest, 0, 32));
  final child = (left + _bytesToBigInt(parent.privateKey)) % _curve.n;
  if (left >= _curve.n || child == BigInt.zero) {
    wipe(digest);
    throw WalletError('derivação BIP32 inválida');
  }
  final key = _bigIntBytes(child, 32);
  final chain = Uint8List.fromList(digest.sublist(32));
  wipe(digest);
  return _PrivateNode(key, chain, parent.depth + 1, _fingerprint(parent.publicKey), index);
}

_PublicNode _publicChild(_PublicNode parent, int index) {
  if (index < 0 || index >= 0x80000000) throw WalletError('índice público inválido');
  final data = Uint8List(37)..setRange(0, 33, parent.publicKey);
  ByteData.sublistView(data).setUint32(33, index);
  final digest = _hmacSha512(parent.chainCode, data);
  wipe(data);
  final left = _bytesToBigInt(Uint8List.sublistView(digest, 0, 32));
  final parentPoint = _curve.curve.decodePoint(parent.publicKey);
  final childPoint = (_curve.G * left)! + parentPoint;
  if (left >= _curve.n || childPoint == null || childPoint.isInfinity) {
    wipe(digest);
    throw WalletError('derivação BIP32 inválida');
  }
  final chain = Uint8List.fromList(digest.sublist(32));
  wipe(digest);
  return _PublicNode(childPoint.getEncoded(true), chain, parent.depth + 1, _fingerprint(parent.publicKey), index);
}

String _serializeXpub(Uint8List publicKey, Uint8List chainCode, int depth, int fingerprint, int childNumber) {
  final payload = Uint8List(78);
  final data = ByteData.sublistView(payload);
  data.setUint32(0, 0x0488b21e);
  payload[4] = depth;
  data.setUint32(5, fingerprint);
  data.setUint32(9, childNumber);
  payload.setRange(13, 45, chainCode);
  payload.setRange(45, 78, publicKey);
  return _base58CheckEncode(payload);
}

_PublicNode _parseXpub(String xpub) {
  final payload = _base58CheckDecode(xpub);
  if (payload.length != 78 || ByteData.sublistView(payload).getUint32(0) != 0x0488b21e || payload[45] > 3) {
    throw WalletError('xpub inválida');
  }
  final publicKey = Uint8List.fromList(payload.sublist(45));
  try {
    if (_curve.curve.decodePoint(publicKey) == null) throw WalletError('xpub inválida');
  } catch (_) {
    throw WalletError('xpub inválida');
  }
  return _PublicNode(
    publicKey,
    Uint8List.fromList(payload.sublist(13, 45)),
    payload[4],
    ByteData.sublistView(payload).getUint32(5),
    ByteData.sublistView(payload).getUint32(9),
  );
}

int _fingerprint(Uint8List publicKey) {
  final hash = RIPEMD160Digest().process(_sha256(publicKey));
  return ByteData.sublistView(hash).getUint32(0);
}

Uint8List _hmacSha512(Uint8List key, Uint8List data) {
  final hmac = HMac(SHA512Digest(), 128)..init(KeyParameter(key));
  return hmac.process(data);
}

Uint8List _sha256(Uint8List data) => SHA256Digest().process(data);

Uint8List _keccak(Uint8List data) => KeccakDigest(256).process(data);

BigInt _bytesToBigInt(Uint8List bytes) => BigInt.parse(_hex(bytes), radix: 16);

Uint8List _bigIntBytes(BigInt value, int length) {
  final hex = value.toRadixString(16).padLeft(length * 2, '0');
  return Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
}

String _base58CheckEncode(Uint8List payload) {
  final checksum = _sha256(_sha256(payload));
  final bytes = Uint8List(payload.length + 4)
    ..setRange(0, payload.length, payload)
    ..setRange(payload.length, payload.length + 4, checksum);
  var value = _bytesToBigInt(bytes);
  var encoded = '';
  while (value > BigInt.zero) {
    final remainder = (value % BigInt.from(58)).toInt();
    encoded = _base58Alphabet[remainder] + encoded;
    value ~/= BigInt.from(58);
  }
  for (final byte in bytes) {
    if (byte != 0) break;
    encoded = '1$encoded';
  }
  return encoded;
}

Uint8List _base58CheckDecode(String encoded) {
  var value = BigInt.zero;
  for (final rune in encoded.runes) {
    final digit = _base58Alphabet.indexOf(String.fromCharCode(rune));
    if (digit < 0) throw WalletError('xpub inválida');
    value = value * BigInt.from(58) + BigInt.from(digit);
  }
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final decoded = <int>[for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  decoded.insertAll(0, List.filled(encoded.length - encoded.replaceFirst(RegExp(r'^1+'), '').length, 0));
  if (decoded.length < 5) throw WalletError('xpub inválida');
  final payload = Uint8List.fromList(decoded.sublist(0, decoded.length - 4));
  final checksum = _sha256(_sha256(payload));
  for (var i = 0; i < 4; i++) {
    if (decoded[decoded.length - 4 + i] != checksum[i]) throw WalletError('xpub inválida');
  }
  return payload;
}

String _checksumAddress(String lowercase) {
  final hash = _hex(_keccak(Uint8List.fromList(ascii.encode(lowercase))));
  final out = StringBuffer('0x');
  for (var i = 0; i < lowercase.length; i++) {
    final ch = lowercase[i];
    out.write(int.parse(hash[i], radix: 16) >= 8 ? ch.toUpperCase() : ch);
  }
  return out.toString();
}

String _hex(Uint8List bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
