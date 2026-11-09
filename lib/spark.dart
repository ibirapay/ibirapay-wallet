// Lightning through the Breez Spark SDK on IBIRAPAY's own Spark deployment (3 operators + SSP, mainnet).
// The wallet key is derived from the 12 words (wallet.dart) and never leaves SecretStore.
import 'dart:async';
import 'dart:convert';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'wallet.dart' show sparkEntropyFromCredential;

/// Operators (public identity keys and addresses) and the SSP. From ~/ops/ibirapay/spark-deploy.sh, 10-26.
/// Identifiers follow the SDK's mainnet pattern: operator index + 1, as 32 bytes.
const sparkDeploymentJson = '''
{
  "coordinator_identifier": "0000000000000000000000000000000000000000000000000000000000000001",
  "threshold": 2,
  "signing_operators": [
    {
      "id": 0,
      "identifier": "0000000000000000000000000000000000000000000000000000000000000001",
      "address": "https://so0.ibirapay.com:8535",
      "identity_public_key": "0398d822e97c0c28837fc8994aad582aa7cc5c3a9ceb2951577d84345e9ff8dab2"
    },
    {
      "id": 1,
      "identifier": "0000000000000000000000000000000000000000000000000000000000000002",
      "address": "https://so1.ibirapay.com:8536",
      "identity_public_key": "022239a448bee910538fcda9d4717abe6ad8b3c04db25121981e4dd8db03dcc686"
    },
    {
      "id": 2,
      "identifier": "0000000000000000000000000000000000000000000000000000000000000003",
      "address": "https://so2.ibirapay.com:8537",
      "identity_public_key": "03b76b179afad94ccda293a5172ad07e9f14db6443a902cfe16d446c00db7d94d1"
    }
  ],
  "ssp_config": {
    "base_url": "https://api.ibirapay.com:9443",
    "identity_public_key": "02693f14e2151204af19ccffa8a9050029bd69fba865e5895433172cd93f752292"
  },
  "expected_withdraw_bond_sats": 10000,
  "expected_withdraw_relative_block_locktime": 1000
}
''';

/// Spark through our relay (owner 11-06: ALL wallet traffic goes through the pagcoin relay): Cloudflare tunnel ->
/// operators (gRPC) and SSP. Probed 11-06 (gRPC on in the pagcoin.org zone): connect, sync, invoice, deposit address and a 210 s idle all work through it. The direct deployment stays
/// as the fallback of [SparkWallet.open]: the relay is tried first and the direct hosts only when opening a connection through it fails.
const sparkRelayEnabled = bool.fromEnvironment('SPARK_RELAY', defaultValue: true);
const sparkRelayOperators = ['https://spark-so0.pagcoin.org', 'https://spark-so1.pagcoin.org', 'https://spark-so2.pagcoin.org'];
const sparkRelaySsp = 'https://spark-ssp.pagcoin.org';

/// [sparkDeploymentJson] with every address pointed at the relay. Identities (public keys) are untouched: the wallet trusts the keys.
String sparkRelayDeploymentJson([String base = sparkDeploymentJson]) {
  final j = jsonDecode(base) as Map<String, dynamic>;
  final ops = j['signing_operators'] as List<dynamic>;
  for (var i = 0; i < ops.length; i++) {
    (ops[i] as Map<String, dynamic>)['address'] = sparkRelayOperators[i];
  }
  (j['ssp_config'] as Map<String, dynamic>)['base_url'] = sparkRelaySsp;
  return jsonEncode(j);
}

/// Where the SDK reads the Bitcoin chain (deposit addresses, fees, refund broadcast): our relay first, the public mempool.space only if
/// the relay is down. An empty `BTC_RELAY_URL` switches the relay off. It never carries a key (an APK is public).
const btcRelay = String.fromEnvironment('BTC_RELAY_URL', defaultValue: 'https://rpc.pagcoin.org/api/btc');
const btcPublic = 'https://mempool.space/api';
const btcChainBackends = [if (btcRelay != '') btcRelay, btcPublic];

/// Which route the last Spark connection took: 'relay' or 'direct' (null before any). The wallet page shows it, so a fallback can be SEEN.
final sparkRoute = ValueNotifier<String?>(null);

/// Opens the connection through the relay first and, only if building through it throws, through the direct hosts. Records the route and
/// logs the error TYPE only (an error message can carry hosts or credentials).
/// ponytail: the SDK's operator transport is lazy (tonic `connect_lazy`), so `build()` does not reach the network: this fallback covers
/// local failures (bad URL, TLS setup), NOT a relay that is down. A down relay shows up as a wallet that cannot sync.
@visibleForTesting
Future<T> buildRelayFirst<T>(Future<T> Function(String deploymentJson) build, {bool relay = sparkRelayEnabled}) async {
  if (relay) {
    try {
      final r = await build(sparkRelayDeploymentJson());
      sparkRoute.value = 'relay';
      return r;
    } catch (e) {
      debugPrint('spark: relay build failed (${e.runtimeType}), using the direct hosts');
    }
  }
  final r = await build(sparkDeploymentJson);
  sparkRoute.value = 'direct';
  return r;
}

/// Claim ceiling for on-chain deposits: the fastest recommended fee rate at claim time plus this leeway (sat/vB). The SDK default
/// (1 sat/vB) would leave every deposit unclaimed whenever the market is above it, and an unset ceiling disables claiming.
const depositClaimLeewaySatPerVbyte = 5;

/// One live connection per process: reused for the same key, and for another key the old one is closed (awaited)
/// before the new one opens. Opens run one at a time. The Breez SDK forbids two instances on one storage directory.
class OneConnection<T extends Object> {
  OneConnection(this._connect, this._disconnect);
  final Future<T> Function(String key) _connect;
  final Future<void> Function(T) _disconnect;
  T? _live;
  String? _key;
  Future<void> _queue = Future.value();

  /// Disconnects the live connection, if any, once the opens queued before it are done.
  Future<void> close() {
    final result = _queue.then((_) async {
      final live = _live;
      _live = _key = null;
      if (live != null) await _disconnect(live);
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<T> get(String key) {
    final result = _queue.then((_) async {
      final live = _live;
      if (live != null && _key == key) return live;
      if (live != null) {
        _live = _key = null;
        await _disconnect(live);
      }
      final c = await _connect(key);
      _live = c;
      _key = key;
      return c;
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// Where the SDK keeps this wallet's data on the device.
Future<String> sparkDataDir() async => '${(await getApplicationSupportDirectory()).path}/spark';

class SparkWallet {
  SparkWallet._(this.sdk);

  /// The SDK handle for the send/receive screens.
  final breez.BreezSdk sdk;

  static bool _initialised = false;
  static final _wallet = OneConnection<breez.BreezSdk>(_connect, (sdk) => sdk.disconnect());

  static Future<breez.BreezSdk> _connect(String credential) async {
    if (!_initialised) {
      await breez.BreezSdkSparkLib.init();
      _initialised = true;
    }
    final dir = await sparkDataDir();
    return buildRelayFirst((json) => _build(credential, dir, json));
  }

  static Future<breez.BreezSdk> _build(String credential, String dir, String deploymentJson) {
    final config = breez
        .defaultConfig(network: breez.Network.mainnet)
        .copyWith(
          sparkConfig: breez.parseSparkConfig(json: deploymentJson),
          maxDepositClaimFee: breez.MaxFee.networkRecommended(leewaySatPerVbyte: BigInt.from(depositClaimLeewaySatPerVbyte)),
        );
    var builder = breez.SdkBuilder(config: config, seed: seedOf(credential)).withDefaultStorage(storageDir: dir);
    for (final url in btcChainBackends) {
      builder = builder.withRestChainService(url: url, apiType: breez.ChainApiType.mempoolSpace);
    }
    return builder.build();
  }

  /// Closes the connection, so its data directory can be deleted.
  static Future<void> close() => _wallet.close();

  /// The first open syncs with the operators (heavy); later ones reuse that connection.
  static Future<SparkWallet> open({required String credential}) async => SparkWallet._(await _wallet.get(credential));

  /// The Spark key derived from the 12 words (`entropy:`).
  @visibleForTesting
  static breez.Seed seedOf(String credential) {
    final entropy = sparkEntropyFromCredential(credential);
    if (entropy == null) throw ArgumentError('not an entropy: credential');
    return breez.Seed.entropy(entropy);
  }

  /// Spendable sats.
  Future<int> balanceSats() async {
    final info = await sdk.getInfo(request: const breez.GetInfoRequest(ensureSynced: false));
    return info.balanceSats.toInt();
  }
}
