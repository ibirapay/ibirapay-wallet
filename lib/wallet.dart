import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'base58.dart';
import 'wallet_seed.dart';

/// The SecretStore key of the 12 words: what makes a wallet exist on this device.
const walletWordsKey = 'wallet.words';

/// The Spark credential the app stores when its wallet was derived from the 12 words: `entropy:` + 64 hex. An older till
/// (or one that typed its own Spark seed) stores the words themselves.
const sparkEntropyPrefix = 'entropy:';

/// What ONE 12-word wallet gives the app: the Spark key, and the PUBLIC Polygon and Solana addresses. The USDT/USDC keys
/// are derived to read the addresses and dropped; they are never stored.
class DerivedWallet {
  const DerivedWallet({required this.sparkCredential, required this.polygon, required this.solana});
  final String sparkCredential;
  final String polygon;
  final String solana;
}

Future<DerivedWallet> deriveWallet(List<String> words) async {
  final seed = mnemonicToSeed(words);
  Uint8List? solKey;
  Uint8List? spark;
  try {
    final evm = deriveEvm(seed); // m/44'/60'/0'/0/0: the address MetaMask shows for these words
    solKey = slip10Ed25519(seed, const [44, 501, 0, 0]); // the address Phantom shows
    final pub = await (await Ed25519().newKeyPairFromSeed(solKey)).extractPublicKey();
    spark = sparkEntropy(seed);
    return DerivedWallet(
      sparkCredential: '$sparkEntropyPrefix${_hex(spark)}',
      polygon: evm.address,
      solana: base58Encode(pub.bytes),
    );
  } finally {
    wipe(seed);
    if (solKey != null) wipe(solKey);
    if (spark != null) wipe(spark);
  }
}

/// The 32 key bytes of an `entropy:` credential, or null when [credential] is not one (or is malformed).
Uint8List? sparkEntropyFromCredential(String credential) {
  if (!credential.startsWith(sparkEntropyPrefix)) return null;
  final h = credential.substring(sparkEntropyPrefix.length);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) return null;
  return Uint8List.fromList([for (var i = 0; i < 64; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
}

String _hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
