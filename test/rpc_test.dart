import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/chain_balances.dart';

/// A local node that answers each request from [script] in turn (the last answer repeats).
Future<(HttpServer, String)> _node(List<(int, Map<String, Object?>)> script) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var i = 0;
  server.listen((req) async {
    await utf8.decoder.bind(req).join();
    final (status, body) = script[i < script.length ? i : script.length - 1];
    i++;
    req.response.statusCode = status;
    req.response.write(jsonEncode(body));
    await req.response.close();
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

/// A node that answers with plain text, as a broken gateway does: the request may have been processed, the reply cannot be read.
Future<(HttpServer, String)> _garbage(int status) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    await utf8.decoder.bind(req).join();
    req.response.statusCode = status;
    req.response.write('<html>bad gateway</html>');
    await req.response.close();
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

/// A node that counts the requests it gets and answers each from [script] in turn (the last answer repeats); [delay] makes it slow.
class _Counted {
  _Counted(this.server, this.script, this.delay) {
    server.listen((req) async {
      await utf8.decoder.bind(req).join();
      hits++;
      if (delay != null) await Future<void>.delayed(delay!);
      final (status, body) = script[(hits - 1) < script.length ? hits - 1 : script.length - 1];
      try {
        req.response.statusCode = status;
        req.response.write(jsonEncode(body));
        await req.response.close();
      } catch (_) {
        // the client gave up first (a timeout test)
      }
    });
  }
  final HttpServer server;
  final List<(int, Map<String, Object?>)> script;
  final Duration? delay;
  int hits = 0;
  String get url => 'http://127.0.0.1:${server.port}';
  Future<void> close() => server.close(force: true);
}

Future<_Counted> _counted(List<(int, Map<String, Object?>)> script, {Duration? delay}) async => _Counted(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), script, delay);

const _ok = (200, {'jsonrpc': '2.0', 'id': 1, 'result': '0x89'});
const _gate429 = (429, {'jsonrpc': '2.0', 'id': 1, 'error': {'code': -32601, 'message': 'RATE_LIMITED'}});
const _gate502 = (502, {'jsonrpc': '2.0', 'id': 1, 'error': {'code': -32601, 'message': 'RPC_UPSTREAM_UNREACHABLE'}});
const _gate400 = (400, {'jsonrpc': '2.0', 'id': 1, 'error': {'code': -32601, 'message': 'METHOD_NOT_ALLOWED'}});

void main() {
  setUp(() {
    rpcBackoff = Duration.zero;
    relayTimeout = const Duration(milliseconds: 200);
    rpcNow = DateTime.now;
    resetRelayBreaker();
  });
  tearDown(() {
    relayUrls.removeWhere((u) => u.startsWith('http://127.0.0.1'));
    rpcNow = DateTime.now;
    relayTimeout = const Duration(seconds: 5);
    resetRelayBreaker();
  });

  test('an answer is returned; a JSON-RPC error is an RpcError with its message, not an outage', () async {
    final (a, ua) = await _node([(200, {'result': '0x89'})]);
    expect(await rpc([ua], 'eth_chainId', []), '0x89');
    final (b, ub) = await _node([(200, {'error': {'code': 3, 'message': 'execution reverted'}})]);
    await expectLater(rpc([ub], 'eth_estimateGas', []), throwsA(isA<RpcError>().having((e) => e.message, 'message', 'execution reverted')));
    await a.close(force: true);
    await b.close(force: true);
  });

  test('the transaction error behind a generic Solana "simulation failed" is kept in the message', () async {
    final (n, u) = await _node([(200, {'error': {'code': -32002, 'message': 'Transaction simulation failed', 'data': {'err': 'AccountNotFound', 'logs': []}}})]);
    await expectLater(rpc([u], 'sendTransaction', []), throwsA(isA<RpcError>().having((e) => e.message, 'message', 'Transaction simulation failed ("AccountNotFound")')));
    await n.close(force: true);
  });

  test('a refusal that follows a transport failure on another node is flagged ambiguous; refusals alone are not', () async {
    final (bad, ub) = await _garbage(502);
    final (refuse, ur) = await _node([(200, {'error': {'code': -32000, 'message': 'insufficient funds'}})]);
    final (refuse2, ur2) = await _node([(200, {'error': {'code': -32000, 'message': 'insufficient funds'}})]);
    final (gone, ug) = await _node([(200, {'result': 'x'})]);
    await gone.close(force: true);
    await expectLater(rpc([ub, ur], 'eth_sendRawTransaction', []), throwsA(isA<RpcError>().having((e) => e.ambiguous, 'ambiguous', isTrue).having((e) => e.message, 'message', 'insufficient funds')));
    await expectLater(rpc([ug, ur], 'eth_sendRawTransaction', []), throwsA(isA<RpcError>().having((e) => e.ambiguous, 'ambiguous', isTrue)));
    await expectLater(rpc([ur, ur2], 'eth_sendRawTransaction', []), throwsA(isA<RpcError>().having((e) => e.ambiguous, 'ambiguous', isFalse)));
    for (final s in [bad, refuse, refuse2]) {
      await s.close(force: true);
    }
  });

  test('when no node succeeds, EVERY node\'s error is kept, not just the first', () async {
    final (a, ua) = await _node([(200, {'error': {'code': -32000, 'message': 'insufficient funds'}})]);
    final (b, ub) = await _node([(200, {'error': {'code': -32000, 'message': 'already known'}})]);
    await expectLater(
      rpc([ua, ub], 'eth_sendRawTransaction', []),
      throwsA(isA<RpcError>().having((e) => e.message, 'message', 'insufficient funds').having((e) => e.messages, 'messages', ['insufficient funds', 'already known'])),
    );
    await a.close(force: true);
    await b.close(force: true);
  });

  test('the next node is tried when the first is dead or does not support the call', () async {
    final (dead, ud) = await _node([(200, {'result': 'x'})]);
    final deadUrl = ud;
    await dead.close(force: true); // nobody listens there now
    final (nosupport, un) = await _node([(200, {'error': {'code': -32602, 'message': 'Indexed requests require a personal token'}})]);
    final (good, ug) = await _node([(200, {'result': 'ok'})]);
    expect(await rpc([deadUrl, un, ug], 'm', []), 'ok');
    await nosupport.close(force: true);
    await good.close(force: true);
  });

  test('all nodes dead is an outage (StateError), all nodes refusing is the nodes\' own error', () async {
    final (dead, ud) = await _node([(200, {'result': 'x'})]);
    await dead.close(force: true);
    await expectLater(rpc([ud], 'm', []), throwsStateError);
    final (n, un) = await _node([(200, {'error': {'code': -32000, 'message': 'nonce too low'}})]);
    await expectLater(rpc([un], 'm', []), throwsA(isA<RpcError>().having((e) => e.message, 'message', 'nonce too low')));
    await n.close(force: true);
  });

  test('a rate limit (HTTP 429 or the node\'s own error) is waited out and asked again', () async {
    final (a, ua) = await _node([(429, {}), (200, {'error': {'code': -32429, 'message': 'Too many requests for a specific RPC call'}}), (200, {'result': 'finally'})]);
    expect(await rpc([ua], 'm', []), 'finally');
    await a.close(force: true);
  });

  test('a rate limit that never clears gives up with the node\'s message after the retries', () async {
    final (a, ua) = await _node([(200, {'error': {'code': -32429, 'message': 'Too many requests'}})]);
    await expectLater(rpc([ua], 'm', []), throwsA(isA<RpcError>().having((e) => e.message, 'message', contains('Too many'))));
    await a.close(force: true);
  });

  group('our relay first, public nodes only when it is unavailable', () {
    Future<(_Counted, _Counted)> pair(List<(int, Map<String, Object?>)> relay, {Duration? relayDelay}) async {
      final r = await _counted(relay, delay: relayDelay);
      final p = await _counted([(200, {'result': 'public'})]);
      relayUrls.add(r.url);
      return (r, p);
    }

    test('the relay answers: the public node is never asked', () async {
      final (r, p) = await pair([_ok]);
      expect(await rpc([r.url, p.url], 'eth_chainId', []), '0x89');
      expect([r.hits, p.hits], [1, 0]);
      await r.close();
      await p.close();
    });

    test('a node\'s own error through the relay is DEFINITIVE: it reaches the caller and the public nodes are not asked', () async {
      final (r, p) = await pair([(200, {'jsonrpc': '2.0', 'id': 1, 'error': {'code': -32000, 'message': 'nonce too low'}})]);
      await expectLater(
        rpc([r.url, p.url], 'eth_sendRawTransaction', []),
        throwsA(isA<RpcError>().having((e) => e.message, 'message', 'nonce too low').having((e) => e.ambiguous, 'ambiguous', isFalse)),
      );
      expect([r.hits, p.hits], [1, 0]);
      await r.close();
      await p.close();
    });

    test('"slow down" inside a 200 is the relay being unavailable, not a node answer: the public node takes over', () async {
      final (r, p) = await pair([(200, {'jsonrpc': '2.0', 'id': 1, 'error': {'code': -32005, 'message': 'exceeded limit'}})]);
      expect(await rpc([r.url, p.url], 'eth_call', []), 'public');
      await r.close();
      await p.close();
    });

    test('HTTP 429 from the gate: the public node answers, nothing may have been delivered (not ambiguous), and the relay rests', () async {
      final (r, p) = await pair([_gate429]);
      expect(await rpc([r.url, p.url], 'eth_call', []), 'public');
      expect(await rpc([r.url, p.url], 'eth_call', []), 'public');
      expect([r.hits, p.hits], [1, 2]); // the second call did not even ask the relay
      await r.close();
      await p.close();
    });

    test('HTTP 502 from the gate: public takes over, and a refusal there afterwards is ambiguous (the relay may have delivered a broadcast)', () async {
      final r = await _counted([_gate502]);
      final p = await _counted([(200, {'error': {'code': -32000, 'message': 'insufficient funds'}})]);
      relayUrls.add(r.url);
      await expectLater(rpc([r.url, p.url], 'eth_sendRawTransaction', []), throwsA(isA<RpcError>().having((e) => e.ambiguous, 'ambiguous', isTrue)));
      await r.close();
      await p.close();
    });

    test('HTTP 400 (method not allowed): public answers for this call, and the relay is NOT put to rest, it is asked again next time', () async {
      final (r, p) = await pair([_gate400, _ok]);
      expect(await rpc([r.url, p.url], 'eth_getLogs', []), 'public');
      expect(await rpc([r.url, p.url], 'eth_chainId', []), '0x89'); // the relay again
      expect([r.hits, p.hits], [2, 1]);
      await r.close();
      await p.close();
    });

    test('a relay that is down (nothing listening) or too slow: public answers', () async {
      final dead = await _counted([_ok]);
      final deadUrl = dead.url;
      await dead.close();
      final p = await _counted([(200, {'result': 'public'})]);
      relayUrls.add(deadUrl);
      expect(await rpc([deadUrl, p.url], 'eth_call', []), 'public');
      await p.close();
      resetRelayBreaker();
      final (slow, p2) = await pair([_ok], relayDelay: const Duration(milliseconds: 600));
      expect(await rpc([slow.url, p2.url], 'eth_call', []), 'public');
      await slow.close();
      await p2.close();
    });

    test('a relay that TIMES OUT also rests: the next call does not wait for it again', () async {
      final (slow, p) = await pair([_ok], relayDelay: const Duration(milliseconds: 600));
      expect(await rpc([slow.url, p.url], 'eth_call', []), 'public');
      expect(await rpc([slow.url, p.url], 'eth_call', []), 'public');
      expect(slow.hits, 1); // the second call did not ask it
      await slow.close();
      await p.close();
    });

    test('the breaker: a failed relay is skipped for 60 s, then asked again, and a good answer closes it', () async {
      var now = DateTime(2026, 11, 5, 12);
      rpcNow = () => now;
      final (r, p) = await pair([_gate502, _ok]);
      expect(await rpc([r.url, p.url], 'eth_call', []), 'public'); // the failure opens the breaker
      now = now.add(const Duration(seconds: 59));
      expect(await rpc([r.url, p.url], 'eth_call', []), 'public');
      expect(r.hits, 1); // still resting
      now = now.add(const Duration(seconds: 2));
      expect(await rpc([r.url, p.url], 'eth_call', []), '0x89'); // asked again, answered
      expect(await rpc([r.url, p.url], 'eth_call', []), '0x89');
      expect(r.hits, 3);
      await r.close();
      await p.close();
    });

    test('a call to the relay alone (the per-node safety lookups) that fails is "nobody answered", never a stand-in answer', () async {
      final (r, p) = await pair([_gate502]);
      await expectLater(rpc([r.url], 'eth_getTransactionByHash', []), throwsStateError);
      expect(p.hits, 0);
      await r.close();
      await p.close();
    });

    test('without the relay in the list nothing changes: public nodes are tried in order', () async {
      final a = await _counted([(200, {'error': {'code': -32602, 'message': 'unsupported'}})]);
      final b = await _counted([(200, {'result': 'b'})]);
      expect(await rpc([a.url, b.url], 'm', []), 'b');
      await a.close();
      await b.close();
    });

    test('"nobody answered" always says why, also when the only node is a relay that is resting', () async {
      var now = DateTime(2026, 11, 5, 12);
      rpcNow = () => now;
      final r = await _counted([_gate502]);
      relayUrls.add(r.url);
      await expectLater(rpc([r.url], 'eth_call', []), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('RelayRefused'))));
      // resting now: no node is even asked, and the message still names a reason instead of "null"
      await expectLater(rpc([r.url], 'eth_call', []), throwsA(isA<StateError>().having((e) => e.message, 'message', isNot(contains('null')))));
      await r.close();
    });

    test('rpcRoute says who answered, so a fallback can be seen; lists with no relay leave it alone', () async {
      rpcRoute.value = null;
      final (r, p) = await pair([_ok, _gate502, _ok]);
      await rpc([r.url, p.url], 'eth_call', []);
      expect(rpcRoute.value, 'relay');
      await rpc([r.url, p.url], 'eth_call', []); // 502: public answers
      expect(rpcRoute.value, 'public');
      resetRelayBreaker();
      await rpc([r.url, p.url], 'eth_call', []);
      expect(rpcRoute.value, 'relay');
      rpcRoute.value = null;
      await rpc([p.url], 'eth_call', []); // a list without a relay says nothing
      expect(rpcRoute.value, isNull);
      await r.close();
      await p.close();
    });

    test('the node lists put the relay first and keep every public node behind it', () {
      expect(polygonRpcs.first, polygonRelay);
      expect(polygonRpcs.skip(1), polygonPublicRpcs);
      expect(relayUrls, contains(polygonRelay));
    });
  });
}
