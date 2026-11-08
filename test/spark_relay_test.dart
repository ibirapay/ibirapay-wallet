import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/spark.dart';

void main() {
  _sparkFallbackTests();
  test('relay deployment moves every address and keeps every identity', () {
    final direct = jsonDecode(sparkDeploymentJson) as Map<String, dynamic>;
    final relay = jsonDecode(sparkRelayDeploymentJson()) as Map<String, dynamic>;
    final dOps = direct['signing_operators'] as List<dynamic>;
    final rOps = relay['signing_operators'] as List<dynamic>;
    expect(rOps.length, dOps.length);
    for (var i = 0; i < dOps.length; i++) {
      final d = dOps[i] as Map<String, dynamic>, r = rOps[i] as Map<String, dynamic>;
      expect(r['address'], sparkRelayOperators[i]);
      expect(r['address'], isNot(d['address']));
      expect(r['identity_public_key'], d['identity_public_key']);
      expect(r['identifier'], d['identifier']);
      expect(r['id'], d['id']);
    }
    final dSsp = direct['ssp_config'] as Map<String, dynamic>, rSsp = relay['ssp_config'] as Map<String, dynamic>;
    expect(rSsp['base_url'], sparkRelaySsp);
    expect(rSsp['identity_public_key'], dSsp['identity_public_key']);
    expect(relay['threshold'], direct['threshold']);
    expect(relay['coordinator_identifier'], direct['coordinator_identifier']);
    expect(relay['expected_withdraw_bond_sats'], direct['expected_withdraw_bond_sats']);
  });

  test('relay hosts are all on pagcoin.org over https, never the direct hosts', () {
    for (final h in [...sparkRelayOperators, sparkRelaySsp]) {
      expect(Uri.parse(h).scheme, 'https');
      expect(Uri.parse(h).host, endsWith('.pagcoin.org'));
    }
    expect(sparkRelayDeploymentJson(), isNot(contains('ibirapay.com')));
  });

  test('chain backends: our relay first, public mempool.space last, no key in the URLs', () {
    expect(btcChainBackends.first, btcRelay);
    expect(btcChainBackends.last, btcPublic);
    for (final u in btcChainBackends) {
      expect(Uri.parse(u).userInfo, '');
      expect(Uri.parse(u).query, '');
    }
  });
}

void _sparkFallbackTests() {
  group('relay-first build', () {
    setUp(() => sparkRoute.value = null);

    test('relay builds: used once, route recorded as relay, no direct host in what was built', () async {
      final seen = <String>[];
      final r = await buildRelayFirst((json) async {
        seen.add(json);
        return 'sdk';
      }, relay: true);
      expect(r, 'sdk');
      expect(seen, hasLength(1));
      expect(seen.single, isNot(contains('ibirapay.com')));
      expect(sparkRoute.value, 'relay');
    });

    test('relay build throws: the direct hosts are tried once, the route says so, and only the error TYPE is logged', () async {
      final seen = <String>[], logged = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logged.add(m ?? '');
      try {
        final r = await buildRelayFirst((json) async {
          seen.add(json);
          if (!json.contains('ibirapay.com')) throw StateError('secret-token-123 should never be logged');
          return 'direct-sdk';
        }, relay: true);
        expect(r, 'direct-sdk');
      } finally {
        debugPrint = old;
      }
      expect(seen, hasLength(2));
      expect(sparkRoute.value, 'direct');
      expect(logged.join(' '), contains('StateError'));
      expect(logged.join(' '), isNot(contains('secret-token-123')));
    });

    test('relay off: straight to the direct hosts', () async {
      final seen = <String>[];
      await buildRelayFirst((json) async => seen.add(json), relay: false);
      expect(seen, [sparkDeploymentJson]);
      expect(sparkRoute.value, 'direct');
    });

    test('both fail: the direct error surfaces and the route is not set', () async {
      await expectLater(buildRelayFirst((json) async => throw StateError('down'), relay: true), throwsA(isA<StateError>()));
      expect(sparkRoute.value, isNull);
    });
  });
}
