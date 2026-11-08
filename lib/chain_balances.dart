// USDT / USDC and gas (POL / SOL) balances of the wallet's own Polygon and Solana addresses, read with plain JSON-RPC (display only).
// Several public nodes are tried in order; a balance that no node could read is reported as unknown, never as zero.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;

/// Our own relay (the wallet-api gate in front of IBIRAPAY's private pagcoin-rpc instance, which holds the Alchemy key): asked FIRST, the
/// public nodes only when it is unavailable. An empty `POLYGON_RELAY_URL` switches it off. It never carries a key (an APK is public).
const polygonRelay = String.fromEnvironment('POLYGON_RELAY_URL', defaultValue: 'https://rpc.pagcoin.org/api/rpc/polygon');
const polygonPublicRpcs = ['https://polygon.drpc.org', 'https://polygon.gateway.tenderly.co', 'https://polygon-bor-rpc.publicnode.com'];
const polygonRpcs = [if (polygonRelay != '') polygonRelay, ...polygonPublicRpcs];
const solanaRpcs = ['https://api.mainnet-beta.solana.com', 'https://solana-rpc.publicnode.com'];

/// ERC-20 contracts on Polygon: native USDT (USDT0), native USDC and the older bridged USDC.e (shown only when held).
const polygonTokens = {
  'USDT': '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
  'USDC': '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
  'USDC.e': '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174',
};

/// SPL mints on Solana.
const solanaMints = {
  'USDC': 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
  'USDT': 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
};

const stableDecimals = 6;

class StableBalance {
  const StableBalance(this.network, this.symbol, this.raw);
  final String network;
  final String symbol;

  /// Smallest units (6 decimals), or null when no node answered.
  final BigInt? raw;

  String get text => raw == null ? '?' : _fmt(raw!);
}

/// The chain's own token, which pays the gas of a send: POL on Polygon, SOL on Solana.
class GasBalance {
  const GasBalance(this.symbol, this.raw);
  final String symbol;

  /// Smallest units (wei / lamports), or null when no node answered.
  final BigInt? raw;

  String get text => raw == null ? '?' : _fmt(raw!, decimals: symbol == 'POL' ? 18 : 9, shown: 4);
}

/// [raw] in units of 10^-[decimals], truncated to [shown] places, comma separator.
String _fmt(BigInt raw, {int decimals = stableDecimals, int shown = 2}) {
  final base = BigInt.from(10).pow(decimals);
  final frac = ((raw % base) ~/ BigInt.from(10).pow(decimals - shown)).toString().padLeft(shown, '0');
  return '${raw ~/ base},$frac';
}

BigInt _hex(String s) => BigInt.parse(s.replaceFirst('0x', '').isEmpty ? '0' : s.replaceFirst('0x', ''), radix: 16);

/// A node ANSWERED with a JSON-RPC error (revert, nonce too low, insufficient funds...): a definitive answer, not an outage.
class RpcError implements Exception {
  RpcError(this.message, [this.code, this.ambiguous = false, this.messages = const []]);
  final String message;
  final int? code;

  /// What EVERY node that answered with an error said, in order ([message] is the first). One node's refusal says nothing about
  /// another's acceptance, so a caller deciding "was it taken?" must read all of them, not just the first.
  final List<String> messages;

  /// Another node failed at the transport level (a timeout, a dropped connection, an unreadable reply) before this answer, so a
  /// request that carried a broadcast may STILL have been delivered there. This refusal then proves nothing about that attempt.
  final bool ambiguous;
  @override
  String toString() => message;
}

typedef RpcFn = Future<dynamic> Function(List<String> nodes, String method, List<dynamic> params);

/// Pause before asking the nodes again after every answer was a rate limit; a test sets it to zero.
Duration rpcBackoff = const Duration(milliseconds: 800);

/// The URLs that are OURS (a relay, not a public node). A test adds its local server here.
final relayUrls = <String>{if (polygonRelay != '') polygonRelay};

/// How long a relay that failed is left alone, so each call does not pay its timeout; and how long a relay may take to answer.
const relayBreak = Duration(seconds: 60);
Duration relayTimeout = const Duration(seconds: 5);

/// The clock the breaker reads; a test moves it.
DateTime Function() rpcNow = DateTime.now;
DateTime? _relayDownUntil;

/// Who answered the last call that had a relay in its list: 'relay' or 'public' (null before any). The wallet page shows it, so a
/// fallback can be SEEN.
final rpcRoute = ValueNotifier<String?>(null);

/// Forgets a relay failure (tests, and a relay that answered).
void resetRelayBreaker() => _relayDownUntil = null;

/// The relay's gate itself said no, or not now (HTTP 400 method refused, 429 its own limit, 5xx upstream trouble). Not an answer from a
/// node: the call goes on to the public nodes.
class _RelayRefused implements Exception {
  _RelayRefused(this.status);
  final int status;
}

/// The relay passed a node's own JSON-RPC error through (a revert, "nonce too low"...): DEFINITIVE, nobody else is asked.
class _RelayAnswered implements Exception {
  _RelayAnswered(this.error);
  final RpcError error;
}

bool _rateLimited(RpcError e) =>
    const {429, -32005, -32029, -32429}.contains(e.code) || RegExp(r'too many|rate.?limit', caseSensitive: false).hasMatch(e.message);

/// Asks the nodes in order and returns the first answer. When none gave a result, a node's own JSON-RPC error wins over
/// "nobody answered", so a revert is never reported as an outage. A node that rate-limits is waited out (twice) before giving up:
/// repeating a call is safe, a rejected broadcast was not processed and the same signed transaction is idempotent.
Future<dynamic> rpc(List<String> nodes, String method, List<dynamic> params) async {
  var transportFailed = false;
  final said = <String>[];
  Object? last; // across the retry rounds too: "nobody answered" always says why the last node failed
  for (var round = 1;; round++) {
    RpcError? answered;
    var limited = false;
    for (final n in nodes) {
      final ours = relayUrls.contains(n);
      final down = _relayDownUntil;
      if (ours && down != null && rpcNow().isBefore(down)) continue; // it failed a moment ago: not asked, so nothing may have been delivered
      final http = HttpClient()..connectionTimeout = ours ? const Duration(seconds: 3) : const Duration(seconds: 6);
      try {
        final req = await http.postUrl(Uri.parse(n));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}));
        final res = await req.close().timeout(ours ? relayTimeout : const Duration(seconds: 10));
        // OUR relay answers 200 with a node's answer, or refuses with 400/429/5xx; anything but 200 is the gate, not a node
        if (ours && res.statusCode != 200) {
          await res.drain<void>();
          throw _RelayRefused(res.statusCode);
        }
        if (res.statusCode == 429) throw RpcError('Too many requests', 429);
        final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
        final err = body['error'];
        if (err != null) {
          // Solana puts the real reason (the transaction error) in `data.err`, behind a generic "simulation failed"
          final why = err is Map && err['data'] is Map && err['data']['err'] != null ? ' (${jsonEncode(err['data']['err'])})' : '';
          final e = RpcError(err is Map ? '${err['message']}$why' : '$err', err is Map && err['code'] is int ? err['code'] as int : null);
          // a node's own error through the relay is final, unless it is the node saying "slow down": that is the relay being unavailable
          if (ours) throw _rateLimited(e) ? _RelayRefused(200) : _RelayAnswered(e);
          throw e;
        }
        if (ours) _relayDownUntil = null;
        if (nodes.any(relayUrls.contains)) rpcRoute.value = ours ? 'relay' : 'public';
        return body['result'];
      } on _RelayAnswered catch (a) {
        _relayDownUntil = null;
        throw RpcError(a.error.message, a.error.code, false, [a.error.message]);
      } on _RelayRefused catch (r) {
        last = r;
        if (r.status != 400) _relayDownUntil = rpcNow().add(relayBreak); // a refused METHOD says nothing about the relay's health
        if (r.status >= 500) transportFailed = true; // trouble past the gate: a broadcast may have gone through
      } catch (e) {
        last = e;
        if (e is RpcError) {
          answered ??= e;
          said.add(e.message);
          if (_rateLimited(e)) limited = true;
        } else {
          transportFailed = true;
          if (ours) _relayDownUntil = rpcNow().add(relayBreak);
        }
      } finally {
        http.close(force: true);
      }
    }
    if (limited && round <= 2) {
      await Future<void>.delayed(rpcBackoff * round);
      continue;
    }
    if (answered != null) throw RpcError(answered.message, answered.code, transportFailed, List.unmodifiable(said));
    throw StateError('nenhum nó respondeu: ${last ?? 'nenhum nó disponível (o relay descansa e não há outro)'}');
  }
}

Future<BigInt?> _erc20(String owner, String contract) async {
  try {
    // balanceOf(address): selector 0x70a08231 + the owner padded to 32 bytes
    final data = '0x70a08231${owner.toLowerCase().replaceFirst('0x', '').padLeft(64, '0')}';
    final r = await rpc(polygonRpcs, 'eth_call', [
      {'to': contract, 'data': data},
      'latest',
    ]);
    return _hex(r as String);
  } catch (_) {
    return null;
  }
}

Future<BigInt?> _pol(String owner) async {
  try {
    return _hex(await rpc(polygonRpcs, 'eth_getBalance', [owner, 'latest']) as String);
  } catch (_) {
    return null;
  }
}

Future<BigInt?> _sol(String owner) async {
  try {
    final r = await rpc(solanaRpcs, 'getBalance', [
      owner,
      {'commitment': 'finalized'},
    ]);
    return BigInt.from(r['value'] as int);
  } catch (_) {
    return null;
  }
}

/// POL and SOL of the wallet's own addresses, in that order.
Future<List<GasBalance>> readGasBalances({required String polygon, required String solana}) async {
  final (pol, sol) = await (_pol(polygon), _sol(solana)).wait;
  return [GasBalance('POL', pol), GasBalance('SOL', sol)];
}

Future<BigInt?> _spl(String owner, String mint) async {
  try {
    final r = await rpc(solanaRpcs, 'getTokenAccountsByOwner', [
      owner,
      {'mint': mint},
      {'encoding': 'jsonParsed', 'commitment': 'finalized'},
    ]);
    var sum = BigInt.zero;
    for (final a in (r['value'] as List)) {
      sum += BigInt.parse(a['account']['data']['parsed']['info']['tokenAmount']['amount'] as String);
    }
    return sum;
  } catch (_) {
    return null;
  }
}

Future<List<StableBalance>> readStableBalances({required String polygon, required String solana}) async {
  final out = await Future.wait([
    for (final e in polygonTokens.entries) _erc20(polygon, e.value).then((v) => StableBalance('Polygon', e.key, v)),
    for (final e in solanaMints.entries) _spl(solana, e.value).then((v) => StableBalance('Solana', e.key, v)),
  ]);
  // the bridged USDC.e row only appears when held
  return out.where((b) => b.symbol != 'USDC.e' || (b.raw ?? BigInt.zero) > BigInt.zero).toList();
}
