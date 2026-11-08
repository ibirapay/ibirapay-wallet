import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/base58.dart';
import 'package:wallet/chain_balances.dart';
import 'package:wallet/evm_tx.dart';
import 'package:wallet/pending_sends.dart';
import 'package:wallet/sol_tx.dart';
import 'package:wallet/stable_send.dart';
import 'package:wallet/wallet_seed.dart';

import 'stable_vectors.dart';

const _bob = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';
final _words = vMnemonic.split(' ');
final _usdtPoly = polygonSendTokens.firstWhere((t) => t.symbol == 'USDT');
final _usdcSol = solanaSendTokens.firstWhere((t) => t.symbol == 'USDC');

/// Canned node: each method answers a value, throws what it returns (an Error or Exception), or is missing (a test bug).
class Fake {
  Fake(this.on, {this.perNode = const {}, MemoryPendingStore? store}) : store = store ?? MemoryPendingStore();
  final Map<String, Object? Function(List<dynamic>)> on;

  /// Answers for ONE node (a single-element node list), to make one of them lag or fail: url -> method -> handler.
  final Map<String, Map<String, Object? Function(List<dynamic>)>> perNode;
  final MemoryPendingStore store;
  final calls = <String>[];
  final sent = <dynamic>[];
  Future<dynamic> call(List<String> nodes, String method, List<dynamic> params) async {
    calls.add(method);
    final own = nodes.length == 1 ? perNode[nodes.first] : null;
    final h = (own == null ? null : own[method]) ?? on[method];
    if (h == null) throw UnimplementedError('fake has no $method');
    final r = h(params);
    if (r is Error) throw r;
    if (r is Exception) throw r;
    return r;
  }

  StableSender sender({int maxMs = 40}) => StableSender(store: store, call: call, pollEvery: const Duration(milliseconds: 2), maxWait: Duration(milliseconds: maxMs));
}

String _h(BigInt v) => '0x${v.toRadixString(16)}';
final _gwei = BigInt.from(1000000000);

Map<String, Object? Function(List<dynamic>)> poly({
  int tokenBalance = 5000000,
  BigInt? pol,
  int baseGwei = 30,
  Object? nodeTip,
  int estimate = 65000,
  Object? chain = '0x89',
  Object? send,
  Object? receipt,
  Object? byHash,
  int finalized = 100,
}) => {
  'eth_chainId': (_) => chain,
  'eth_call': (_) => '0x${tokenBalance.toRadixString(16).padLeft(64, '0')}',
  'eth_getBalance': (_) => _h(pol ?? BigInt.from(10) * BigInt.from(10).pow(18)),
  'eth_getBlockByNumber': (p) => p[0] == 'finalized' ? {'number': _h(BigInt.from(finalized))} : {'baseFeePerGas': _h(BigInt.from(baseGwei) * _gwei)},
  'eth_maxPriorityFeePerGas': (_) => nodeTip ?? _h(BigInt.from(20) * _gwei),
  'eth_estimateGas': (_) => _h(BigInt.from(estimate)),
  'eth_getTransactionCount': (_) => '0x7',
  'eth_sendRawTransaction': (p) => send ?? '0xhash',
  'eth_getTransactionReceipt': (_) => receipt,
  'eth_getTransactionByHash': (_) => byHash,
};

Map tokenAcct(String pubkey, int amount, {String state = 'initialized'}) => {
  'pubkey': pubkey,
  'account': {
    'data': {
      'parsed': {
        'info': {
          'tokenAmount': {'amount': '$amount'},
          'state': state,
        },
      },
    },
  },
};

Map splInfo(String mint, {String state = 'initialized', int amount = 0}) => {
  'owner': tokenProgramId,
  'data': {
    'parsed': {
      'type': 'account',
      'info': {
        'mint': mint,
        'state': state,
        'tokenAmount': {'amount': '$amount'},
      },
    },
  },
};

final _walletInfo = {'owner': systemProgramId, 'lamports': 1000000, 'data': ['', 'base64']};
final _owner = solPubkey(vSolAddress);
final _mint = solPubkey(_usdcSol.id);
final _myAta = base58Encode(associatedTokenAccount(_owner, _mint));
final _theirAta = base58Encode(associatedTokenAccount(solPubkey(vSolRecipient), _mint));
final _blockhash = solPubkey(vSolBlockhash);

Map<String, Object? Function(List<dynamic>)> sol({
  List<Map>? accounts,
  Map<String, Map?>? info,
  Map? ownAta,
  int lamports = 50000000,
  Object? simErr,
  Object? send,
  Object? status,
  Object? statusHistory,
  Object? height,
}) => {
  'getTokenAccountsByOwner': (_) => {'value': accounts ?? [tokenAcct(_myAta, 20000000)]},
  'getAccountInfo': (p) => {'value': p[0] == _myAta ? ownAta : (info ?? {vSolRecipient: _walletInfo, _theirAta: splInfo(_usdcSol.id)})[p[0]]},
  'getBalance': (_) => {'value': lamports},
  'getMinimumBalanceForRentExemption': (p) => (p[0] as int) == 0 ? 890880 : 2039280,
  'getLatestBlockhash': (_) => {'value': {'blockhash': vSolBlockhash, 'lastValidBlockHeight': 1000}},
  'getFeeForMessage': (_) => {'value': 5000},
  'simulateTransaction': (_) => {'value': {'err': simErr}},
  'sendTransaction': (_) => send ?? 'sig',
  'getSignatureStatuses': (p) => {'value': [(p[1]['searchTransactionHistory'] as bool) ? statusHistory ?? status : status]},
  'getBlockHeight': (_) => height ?? 10,
};

Future<Quote> _q(Fake f, {StableToken? token, String? to, BigInt? amount}) => f.sender().quote(
  token: token ?? _usdtPoly,
  from: token?.net == Net.solana ? vSolAddress : vEvmAddress,
  to: to ?? (token?.net == Net.solana ? vSolRecipient : _bob),
  amount: amount ?? BigInt.from(1500000),
);

Matcher _sendError(Pattern p) => throwsA(isA<SendError>().having((e) => e.message, 'message', contains(p)));

void main() {
  group('amounts', () {
    test('typed amounts become exact smallest units', () {
      expect(parseStableAmount('1'), BigInt.from(1000000));
      expect(parseStableAmount('1,5'), BigInt.from(1500000));
      expect(parseStableAmount('1.5'), BigInt.from(1500000));
      expect(parseStableAmount(' 0,000001 '), BigInt.one);
      expect(parseStableAmount('0,123'), BigInt.from(123000));
      expect(parseStableAmount('1234,56'), BigInt.from(1234560000));
      expect(parseStableAmount('1,0000'), BigInt.from(1000000));
    });

    test('what could be read two ways, or is not a plain amount, is refused', () {
      for (final bad in ['', ' ', 'abc', '1e3', '-1', '+1', '0', '0,0', '0,0000001', '1.000', '12,500', '999.999', '1.000.000', '1,', ',5', '1 000']) {
        expect(() => parseStableAmount(bad), throwsA(isA<SendError>()), reason: '"$bad"');
      }
    });

    test('exact formatting', () {
      expect(fmtUnits(BigInt.from(1500000), 6), '1,50');
      expect(fmtUnits(BigInt.from(1234567), 6), '1,234567');
      expect(fmtUnits(BigInt.zero, 6), '0,00');
      expect(fmtUnits(BigInt.from(5000), 9, minPlaces: 4), '0,000005');
      expect(fmtUnits(BigInt.from(10).pow(18), 18, minPlaces: 4), '1,0000');
    });
  });

  group('recipients', () {
    test('Polygon: a good address, in any case, comes back checksummed', () {
      expect(parsePolygonRecipient(_bob), _bob);
      expect(parsePolygonRecipient(_bob.toLowerCase()), _bob);
      expect(parsePolygonRecipient('  $_bob  '), _bob);
      expect(parsePolygonRecipient('ethereum:$_bob@137'), _bob);
      expect(parsePolygonRecipient('ethereum:$_bob?value=1000000000000000000'), _bob); // a plain request: the target is the beneficiary
      expect(parsePolygonRecipient('polygon:$_bob'), _bob);
    });

    test('Polygon: wrong chain, bad checksum, zero address, token contract and garbage are refused', () {
      expect(() => parsePolygonRecipient('ethereum:$_bob@1'), throwsA(isA<SendError>().having((e) => e.message, 'm', contains('outra rede'))));
      expect(() => parsePolygonRecipient('ethereum:$_bob@8453'), throwsA(isA<SendError>()));
      final flipped = _bob.replaceFirst('742d35Cc', '742D35Cc');
      expect(() => parsePolygonRecipient(flipped), throwsA(isA<SendError>().having((e) => e.message, 'm', contains('digitação'))));
      expect(() => parsePolygonRecipient('0x${'0' * 40}'), throwsA(isA<SendError>().having((e) => e.message, 'm', contains('zero'))));
      expect(() => parsePolygonRecipient(polygonTokens['USDT']!), throwsA(isA<SendError>().having((e) => e.message, 'm', contains('contrato'))));
      expect(() => parsePolygonRecipient(polygonTokens['USDC']!.toLowerCase()), throwsA(isA<SendError>()));
      for (final bad in ['', '0x123', _bob.substring(0, 41), '${_bob}0', vSolAddress, 'hello']) {
        expect(() => parsePolygonRecipient(bad), throwsA(isA<SendError>()), reason: bad);
      }
    });

    test('ERC-681 with a function: only `transfer` on the SELECTED token, and the recipient is the `address` parameter, never the contract', () {
      final usdt = polygonTokens['USDT']!;
      final usdc = polygonTokens['USDC']!;
      expect(parsePolygonRecipient('ethereum:pay-$usdt@137/transfer?address=$_bob&uint256=1500000', token: usdt), _bob);
      expect(parsePolygonRecipient('ethereum:$usdt/transfer?uint256=1&address=${_bob.toLowerCase()}', token: usdt), _bob);
      for (final bad in [
        'ethereum:pay-$usdc@137/transfer?address=$_bob&uint256=1', // a request for another token than the selected one
        'ethereum:pay-0x1111111111111111111111111111111111111111@137/transfer?address=$_bob', // an unknown contract
        'ethereum:pay-$usdt@137/approve?address=$_bob&uint256=1', // not a transfer
        'ethereum:pay-$usdt@137/transfer?uint256=1', // no beneficiary
        'ethereum:pay-$usdt@137/transfer?address=0x123&uint256=1', // a broken beneficiary
        'ethereum:pay-$usdt@137/transfer?address=0x${'0' * 40}', // the zero address
        'ethereum:pay-$usdt@137/transfer?address=$usdc', // a token contract as beneficiary
        'ethereum:pay-$usdt@1/transfer?address=$_bob', // another chain
        'ethereum:pay-$usdt@137/transfer?xaddress=$_bob', // not the parameter
      ]) {
        expect(() => parsePolygonRecipient(bad, token: usdt), throwsA(isA<SendError>()), reason: bad);
      }
      // without knowing the selected token a function link cannot be accepted at all
      expect(() => parsePolygonRecipient('ethereum:pay-$usdt@137/transfer?address=$_bob'), throwsA(isA<SendError>()));
    });

    test('Solana: an address, with or without the solana: scheme and query', () {
      expect(parseSolanaRecipient(vSolRecipient), vSolRecipient);
      expect(parseSolanaRecipient('solana:$vSolRecipient?amount=1'), vSolRecipient);
      expect(parseSolanaRecipient(' $vSolRecipient '), vSolRecipient);
      for (final bad in ['', 'abc', _bob, '${vSolRecipient}1', vSolRecipient.substring(0, 30)]) {
        expect(() => parseSolanaRecipient(bad), throwsA(isA<SendError>()), reason: bad);
      }
    });
  });

  group('Polygon quote', () {
    test('fee: priority floor 25 gwei, max fee = 2 x base + tip, gas limit = estimate + 25%', () async {
      final q = await _q(Fake(poly(baseGwei: 30, estimate: 65000)));
      expect(q.fee, BigInt.from(85) * _gwei * BigInt.from(81250));
      expect(q.to, _bob);
      expect(q.balance, BigInt.from(5000000));
    });

    test('a node tip above the floor is used; a node with no tip method falls back to the floor', () async {
      expect((await _q(Fake(poly(nodeTip: _h(BigInt.from(40) * _gwei))))).fee, BigInt.from(100) * _gwei * BigInt.from(81250));
      final noMethod = poly()..['eth_maxPriorityFeePerGas'] = (_) => RpcError('method not found');
      expect((await _q(Fake(noMethod))).fee, BigInt.from(85) * _gwei * BigInt.from(81250));
    });

    test('each refusal names its own cause', () async {
      await expectLater(_q(Fake(poly(tokenBalance: 1000000))), _sendError('Saldo insuficiente de USDT'));
      await expectLater(_q(Fake(poly(pol: BigInt.from(1000)))), _sendError('POL insuficiente'));
      final revert = poly()..['eth_estimateGas'] = (_) => RpcError('execution reverted: transfer amount exceeds balance');
      await expectLater(_q(Fake(revert)), _sendError('A Polygon recusou a transferência'));
      await expectLater(_q(Fake(poly(chain: '0x1'))), _sendError('outra rede'));
      await expectLater(_q(Fake(poly()), to: '0x${'0' * 40}'), _sendError('zero'));
      final dead = poly()..['eth_chainId'] = (_) => StateError('nenhum nó respondeu: x');
      await expectLater(_q(Fake(dead)), _sendError('Nenhum nó'));
    });

    test('a token-payment QR pays its beneficiary; a crafted one for a contract is refused and nothing is asked of the chain', () async {
      final usdt = polygonTokens['USDT']!;
      final q = await _q(Fake(poly()), to: 'ethereum:pay-$usdt@137/transfer?address=$_bob&uint256=1500000');
      expect(q.to, _bob);
      final f = Fake(poly());
      await expectLater(_q(f, to: 'ethereum:pay-0x1111111111111111111111111111111111111111@137/transfer?address=$_bob'), _sendError('outro token ou contrato'));
      expect(f.calls.contains('eth_estimateGas'), isFalse);
    });

    test('sending to yourself is allowed but flagged', () async {
      final q = await _q(Fake(poly()), to: vEvmAddress);
      expect(q.warnings, isNotEmpty);
    });
  });

  group('Polygon submit', () {
    test('signs the right call, sends it, and reports confirmed with the local hash', () async {
      final f = Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x64'}));
      final q = await _q(f);
      f.sent.clear();
      final sentRaw = <String>[];
      f.on['eth_sendRawTransaction'] = (p) {
        sentRaw.add(p[0] as String);
        return '0xanything';
      };
      final o = await f.sender().submit(q, _words);
      expect(o.result, Result.confirmed);
      expect(sentRaw, hasLength(1));
      final raw = sentRaw.single;
      expect(raw.startsWith('0x02f8'), isTrue);
      expect(o.id, '0x${bytesToHex(keccak256(hexToBytes(raw)))}');
      expect(raw.contains('a9059cbb'), isTrue);
      expect(raw.contains(_bob.substring(2).toLowerCase()), isTrue);
      expect(raw.contains(polygonTokens['USDT']!.substring(2).toLowerCase()), isTrue);
      expect(raw.contains('16e360'), isTrue); // 1.5 USDT in smallest units
      expect(o.explorer, 'https://polygonscan.com/tx/${o.id}');
      expect(f.calls.where((c) => c == 'eth_getTransactionCount'), hasLength(1)); // the nonce is read at submit, when it is used
    });

    test('a reverted receipt is reverted, not failed-to-send', () async {
      final f = Fake(poly(receipt: {'status': '0x0', 'blockNumber': '0x64'}));
      expect((await f.sender().submit(await _q(f), _words)).result, Result.reverted);
    });

    test('no receipt in time is pending with the hash, never a failure', () async {
      final f = Fake(poly());
      final o = await f.sender().submit(await _q(f), _words);
      expect(o.result, Result.pending);
      expect(o.id, startsWith('0x'));
    });

    test('a node refusal is "not sent" only when no node knows the transaction and it is not about the nonce', () async {
      final refused = poly(send: RpcError('insufficient funds for gas * price + value'));
      final f = Fake(refused);
      await expectLater(f.sender().submit(await _q(f), _words), _sendError('recusou o envio'));
      expect(f.store.items, isEmpty); // refused for certain: nothing to remember
      // ...but "already known" with the chain knowing it carries on to its receipt
      final known = poly(send: RpcError('already known'), byHash: {'hash': 'x'}, receipt: {'status': '0x1', 'blockNumber': '0x64'});
      final g = Fake(known);
      expect((await g.sender().submit(await _q(g), _words)).result, Result.confirmed);
    });

    test('a refusal while the lookup also fails is pending, not "not sent"', () async {
      final h = poly(send: RpcError('already known'))..['eth_getTransactionByHash'] = (_) => StateError('offline');
      final f = Fake(h);
      expect((await f.sender().submit(await _q(f), _words)).result, Result.pending);
    });

    test('no node answering the broadcast is pending; a transaction found afterwards is followed', () async {
      final f = Fake(poly(send: StateError('nenhum nó respondeu')));
      expect((await f.sender().submit(await _q(f), _words)).result, Result.pending);
      final g = Fake(poly(send: StateError('nenhum nó respondeu'), byHash: {'hash': 'x'}, receipt: {'status': '0x1', 'blockNumber': '0x64'}));
      expect((await g.sender().submit(await _q(g), _words)).result, Result.confirmed);
    });

    test('before broadcast, failures say nothing was sent', () async {
      final f = Fake(poly());
      final q = await _q(f);
      f.on['eth_getTransactionCount'] = (_) => StateError('offline');
      await expectLater(f.sender().submit(q, _words), _sendError('Nada foi enviado'));
      f.on['eth_getTransactionCount'] = (_) => '0x7';
      // words that are not this wallet's: the key check refuses and nothing is broadcast
      final other = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong'.split(' ');
      await expectLater(f.sender().submit(q, other), throwsA(isA<SendError>()));
      expect(f.calls.contains('eth_sendRawTransaction'), isFalse);
    });
  });

  group('Solana quote', () {
    test('recipient with an existing token account: no creation, no rent', () async {
      final q = await _q(Fake(sol()), token: _usdcSol);
      expect(q.rent, BigInt.zero);
      expect(q.fee, BigInt.from(5000));
      expect(q.to, vSolRecipient);
    });

    test('recipient without a token account: it is created and the rent is shown', () async {
      final q = await _q(Fake(sol(info: {vSolRecipient: _walletInfo})), token: _usdcSol);
      expect(q.rent, BigInt.from(2039280));
      final fresh = await _q(Fake(sol(info: {vSolRecipient: null})), token: _usdcSol); // a wallet never seen on chain
      expect(fresh.rent, BigInt.from(2039280));
    });

    test('the wallet\'s own associated account is read directly; the indexed lookup is only the fallback', () async {
      final f = Fake(sol(ownAta: splInfo(_usdcSol.id, amount: 20000000)));
      final q = await _q(f, token: _usdcSol);
      expect(q.balance, BigInt.from(20000000));
      expect(f.calls.contains('getTokenAccountsByOwner'), isFalse);
      // too small there: another token account may hold it, so the indexed lookup is asked
      final g = Fake(sol(ownAta: splInfo(_usdcSol.id, amount: 1000)));
      await _q(g, token: _usdcSol);
      expect(g.calls.contains('getTokenAccountsByOwner'), isTrue);
      // a frozen associated account is never the source
      final h = Fake(sol(ownAta: splInfo(_usdcSol.id, amount: 20000000, state: 'frozen'), accounts: []));
      await expectLater(_q(h, token: _usdcSol), _sendError('congelada pelo emissor'));
    });

    test('an address that is itself a token account of this mint is paid directly', () async {
      final q = await _q(Fake(sol(info: {vSolRecipient: splInfo(_usdcSol.id)})), token: _usdcSol);
      expect(q.rent, BigInt.zero);
    });

    test('wrong kinds of address are refused', () async {
      await expectLater(_q(Fake(sol(info: {vSolRecipient: splInfo(solanaMints['USDT']!)})), token: _usdcSol), _sendError('outra moeda'));
      await expectLater(_q(Fake(sol(info: {vSolRecipient: {'owner': tokenProgramId, 'data': ['x', 'base64']}})), token: _usdcSol), _sendError('outra moeda'));
      await expectLater(_q(Fake(sol(info: {vSolRecipient: {'owner': 'BPFLoader2111111111111111111111111111111111', 'data': ['', 'base64']}})), token: _usdcSol), _sendError('não é uma carteira'));
      await expectLater(_q(Fake(sol(info: {vSolRecipient: splInfo(_usdcSol.id, state: 'frozen')})), token: _usdcSol), _sendError('congelada'));
      await expectLater(_q(Fake(sol(info: {vSolRecipient: _walletInfo, _theirAta: splInfo(_usdcSol.id, state: 'frozen')})), token: _usdcSol), _sendError('congelada'));
    });

    test('balances and gas', () async {
      await expectLater(_q(Fake(sol(accounts: [tokenAcct(_myAta, 1000)])), token: _usdcSol), _sendError('Saldo insuficiente de USDC'));
      await expectLater(_q(Fake(sol(accounts: [])), token: _usdcSol), _sendError('Saldo insuficiente'));
      // a frozen account cannot send, however much it holds
      await expectLater(_q(Fake(sol(accounts: [tokenAcct(_myAta, 20000000, state: 'frozen')])), token: _usdcSol), _sendError('congelada pelo emissor'));
      // frozen next to a usable account: the usable one is what counts
      await expectLater(_q(Fake(sol(accounts: [tokenAcct(_myAta, 20000000, state: 'frozen'), tokenAcct(vSolRecipient, 1000)])), token: _usdcSol), _sendError('Saldo insuficiente'));
      await expectLater(_q(Fake(sol(accounts: [tokenAcct(_myAta, 1000000), tokenAcct(vSolRecipient, 1000000)])), token: _usdcSol), _sendError('dividido'));
      await expectLater(_q(Fake(sol(lamports: 1000)), token: _usdcSol), _sendError('SOL insuficiente'));
      // rent for the new account is part of what SOL must cover
      await expectLater(_q(Fake(sol(lamports: 1000000, info: {vSolRecipient: _walletInfo})), token: _usdcSol), _sendError('SOL insuficiente'));
      // what is left must be zero or at least the account minimum
      await expectLater(_q(Fake(sol(lamports: 5000 + 100000)), token: _usdcSol), _sendError('mínimo'));
    });

    test('the dry run refuses with the network reason; no node answering is its own message', () async {
      await expectLater(_q(Fake(sol(simErr: {'InstructionError': [0, {'Custom': 1}]})), token: _usdcSol), _sendError('recusou a simulação'));
      final dead = sol()..['getAccountInfo'] = (_) => StateError('nenhum nó respondeu: x');
      await expectLater(_q(Fake(dead), token: _usdcSol), _sendError('Nenhum nó'));
    });
  });

  group('Solana submit', () {
    Future<Uint8List> expectedWire({required bool create, required String dest}) async {
      final key = slip10Ed25519(mnemonicToSeed(_words), const [44, 501, 0, 0]);
      final ixs = [
        if (create) createAtaIdempotent(payer: _owner, ata: solPubkey(dest), owner: solPubkey(vSolRecipient), mint: _mint),
        transferChecked(source: solPubkey(_myAta), mint: _mint, dest: solPubkey(dest), authority: _owner, amount: BigInt.from(1500000), decimals: 6),
      ];
      final msg = compileMessage(payer: _owner, blockhash: _blockhash, instructions: ixs);
      return (await signMessage(msg, key, expectedPubkey: _owner)).wire;
    }

    Future<Outcome> run(Fake f, {Quote? quote}) async => f.sender().submit(quote ?? await _q(f, token: _usdcSol), _words);

    test('the wire transaction is exactly the expected signed message, with and without account creation', () async {
      for (final create in [false, true]) {
        final wires = <String>[];
        final handlers = sol(info: create ? {vSolRecipient: _walletInfo} : null, status: {'confirmationStatus': 'finalized', 'err': null});
        handlers['sendTransaction'] = (p) {
          wires.add(p[0] as String);
          return 'sig';
        };
        final o = await run(Fake(handlers));
        expect(o.result, Result.confirmed);
        expect(base64Decode(wires.single), await expectedWire(create: create, dest: _theirAta), reason: 'create=$create');
        expect(o.explorer, startsWith('https://solscan.io/tx/'));
      }
    });

    test('executed with an error is reverted; finalized is confirmed', () async {
      expect((await run(Fake(sol(status: {'confirmationStatus': 'finalized', 'err': {'InstructionError': [0, 'x']}})))).result, Result.reverted);
      expect((await run(Fake(sol(status: {'confirmationStatus': 'finalized', 'err': null})))).result, Result.confirmed);
    });

    test('"not sent" is only said when the blockhash expired AND the history was asked and is empty', () async {
      expect((await run(Fake(sol(height: 2000)))).result, Result.notSent);
      // expired but the history shows it landed just before
      expect((await run(Fake(sol(height: 2000, statusHistory: {'confirmationStatus': 'finalized', 'err': null})))).result, Result.confirmed);
      // not expired and not seen: keep waiting, then pending
      expect((await run(Fake(sol(height: 10)))).result, Result.pending);
    });

    test('a flaky lookup after expiry is never read as "not sent"', () async {
      final h = sol(height: 2000)..['getSignatureStatuses'] = (_) => StateError('offline');
      final f = Fake(h);
      final q = await _q(Fake(sol()), token: _usdcSol);
      expect((await run(f, quote: q)).result, Result.pending);
    });

    test('a node refusal before broadcast says nothing was sent; "already processed" is followed', () async {
      final f = Fake(sol(send: RpcError('Transaction simulation failed: insufficient funds')));
      await expectLater(run(f), _sendError('recusou o envio'));
      final g = Fake(sol(send: RpcError('already processed'), status: {'confirmationStatus': 'finalized', 'err': null}));
      expect((await run(g)).result, Result.confirmed);
    });

    test('no node answering the broadcast is pending; before the broadcast it is "nothing sent"', () async {
      expect((await run(Fake(sol(send: StateError('nenhum nó respondeu'))))).result, Result.pending);
      final f = Fake(sol());
      final q = await _q(f, token: _usdcSol);
      f.on['getLatestBlockhash'] = (_) => StateError('offline');
      await expectLater(f.sender().submit(q, _words), _sendError('Nada foi enviado'));
      expect(f.calls.contains('sendTransaction'), isFalse);
    });

    test('words that are not this wallet are refused before anything is sent', () async {
      final f = Fake(sol());
      final q = await _q(f, token: _usdcSol);
      final other = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong'.split(' ');
      await expectLater(f.sender().submit(q, other), throwsA(isA<SendError>()));
      expect(f.calls.contains('sendTransaction'), isFalse);
    });
  });


  int agoMs(Duration d) => DateTime.now().millisecondsSinceEpoch - d.inMilliseconds;
  PendingSend polyRecord({int nonce = 7, Duration age = const Duration(minutes: 5)}) =>
      PendingSend(id: '0xabc', net: 'polygon', symbol: 'USDT', amount: '1500000', to: _bob, from: vEvmAddress, createdMs: agoMs(age), nonce: nonce);
  PendingSend solRecord({Duration age = const Duration(minutes: 5)}) =>
      PendingSend(id: 'solsig', net: 'solana', symbol: 'USDC', amount: '1500000', to: vSolRecipient, from: vSolAddress, createdMs: agoMs(age), lastValid: 1000);

  group('an open send is remembered until its outcome is certain', () {
    test('Polygon: the record is written BEFORE the broadcast, with what is needed to find it again', () async {
      final f = Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x64'}));
      final q = await _q(f);
      PendingSend? atBroadcast;
      f.on['eth_sendRawTransaction'] = (_) {
        atBroadcast = f.store.items.singleOrNull;
        return '0xh';
      };
      final o = await f.sender().submit(q, _words);
      expect(atBroadcast, isNotNull);
      expect(atBroadcast!.id, o.id);
      expect([atBroadcast!.net, atBroadcast!.symbol, atBroadcast!.amount, atBroadcast!.to, atBroadcast!.from, atBroadcast!.nonce], ['polygon', 'USDT', '1500000', _bob, vEvmAddress, 7]);
      expect(f.store.items, isEmpty); // confirmed is certain: forgotten
    });

    test('Polygon: reverted and refused clear it; unknown keeps it', () async {
      final r = Fake(poly(receipt: {'status': '0x0', 'blockNumber': '0x64'}));
      await r.sender().submit(await _q(r), _words);
      expect(r.store.items, isEmpty);
      final refused = Fake(poly(send: RpcError('insufficient funds for gas')));
      await expectLater(refused.sender().submit(await _q(refused), _words), throwsA(isA<SendError>()));
      expect(refused.store.items, isEmpty);
      final unknown = Fake(poly());
      final o = await unknown.sender().submit(await _q(unknown), _words);
      expect(o.result, Result.pending);
      expect(unknown.store.items.single.id, o.id);
    });

    test('Solana: written before the broadcast with its last valid block; certain outcomes clear it, unknown keeps it', () async {
      final f = Fake(sol(status: {'confirmationStatus': 'finalized', 'err': null}));
      final q = await _q(f, token: _usdcSol);
      PendingSend? atBroadcast;
      f.on['sendTransaction'] = (_) {
        atBroadcast = f.store.items.singleOrNull;
        return 'sig';
      };
      final o = await f.sender().submit(q, _words);
      expect(atBroadcast?.id, o.id);
      expect([atBroadcast?.net, atBroadcast?.lastValid, atBroadcast?.amount], ['solana', 1000, '1500000']);
      expect(f.store.items, isEmpty);
      for (final (label, h) in [('expired', sol(height: 2000)), ('reverted', sol(status: {'confirmationStatus': 'finalized', 'err': 'x'}))]) {
        final g = Fake(h);
        await g.sender().submit(await _q(g, token: _usdcSol), _words);
        expect(g.store.items, isEmpty, reason: label);
      }
      final u = Fake(sol(height: 10));
      expect((await u.sender().submit(await _q(u, token: _usdcSol), _words)).result, Result.pending);
      expect(u.store.items, hasLength(1));
    });

    test('a second send on the SAME network is refused while one is open; the other network is free', () async {
      final f = Fake(poly());
      final q = await _q(f);
      f.store.items.add(polyRecord());
      await expectLater(f.sender().submit(q, _words), _sendError('em aberto'));
      expect(f.calls.contains('eth_sendRawTransaction'), isFalse);
      final g = Fake(sol(status: {'confirmationStatus': 'finalized', 'err': null}));
      g.store.items.add(polyRecord());
      expect((await g.sender().submit(await _q(g, token: _usdcSol), _words)).result, Result.confirmed);
    });

    test('a store that cannot be written or read stops the send before anything is broadcast', () async {
      final w = Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x64'}));
      final qw = await _q(w);
      w.store.failWrites = true;
      await expectLater(w.sender().submit(qw, _words), _sendError('registro de envios'));
      expect(w.calls.contains('eth_sendRawTransaction'), isFalse);
      final r = Fake(poly());
      final qr = await _q(r);
      r.store.failReads = true;
      await expectLater(r.sender().submit(qr, _words), _sendError('registro de envios'));
      expect(r.calls.contains('eth_sendRawTransaction'), isFalse);
      final s = Fake(sol());
      final qs = await _q(s, token: _usdcSol);
      s.store.failWrites = true;
      await expectLater(s.sender().submit(qs, _words), _sendError('registro de envios'));
      expect(s.calls.contains('sendTransaction'), isFalse);
    });

    test('two sends racing for one network: one broadcasts, the other stops before broadcasting', () async {
      final f = Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x64'}));
      final q1 = await _q(f);
      final q2 = await _q(f);
      final results = await Future.wait([
        f.sender().submit(q1, _words).then<Object>((o) => o, onError: (Object e) => e),
        f.sender().submit(q2, _words).then<Object>((o) => o, onError: (Object e) => e),
      ]);
      expect(results.whereType<Outcome>(), hasLength(1));
      expect(results.whereType<SendError>(), hasLength(1));
      expect(f.calls.where((c) => c == 'eth_sendRawTransaction'), hasLength(1));
      final g = Fake(sol(status: {'confirmationStatus': 'finalized', 'err': null}));
      final s1 = await _q(g, token: _usdcSol);
      final s2 = await _q(g, token: _usdcSol);
      final sr = await Future.wait([
        g.sender().submit(s1, _words).then<Object>((o) => o, onError: (Object e) => e),
        g.sender().submit(s2, _words).then<Object>((o) => o, onError: (Object e) => e),
      ]);
      expect(sr.whereType<Outcome>(), hasLength(1));
      expect(g.calls.where((c) => c == 'sendTransaction'), hasLength(1));
    });

    test('anything unexpected after signing is "unknown", never "not sent"', () async {
      final f = Fake(poly());
      final q = await _q(f);
      f.on['eth_sendRawTransaction'] = (_) => TypeError(); // not an outage and not a refusal: nobody planned for it
      final o = await f.sender().submit(q, _words);
      expect(o.result, Result.pending);
      expect(f.store.items, hasLength(1));
      // the same on Solana
      final g = Fake(sol());
      final qs = await _q(g, token: _usdcSol);
      g.on['sendTransaction'] = (_) => TypeError();
      expect((await g.sender().submit(qs, _words)).result, Result.pending);
      expect(g.store.items, hasLength(1));
    });
  });

  group('a lagging node cannot make a landed transaction look unsent', () {
    final n0 = polygonRpcs[0];
    final n1 = polygonRpcs[1];

    test('Polygon: one node knows it, another says unknown: it is known', () async {
      final f = Fake(poly(send: RpcError('already known'), receipt: {'status': '0x1', 'blockNumber': '0x64'}), perNode: {
        n0: {'eth_getTransactionByHash': (_) => null},
        n1: {'eth_getTransactionByHash': (_) => {'hash': 'x'}},
      });
      expect((await f.sender().submit(await _q(f), _words)).result, Result.confirmed);
    });

    test('Polygon: a refusal about the nonce, with nobody knowing the hash, is pending, not "refused"; any other refusal is refused', () async {
      for (final m in ['nonce too low: next nonce 8, tx nonce 7', 'already known', 'replacement transaction underpriced', 'known transaction: abc']) {
        final f = Fake(poly(send: RpcError(m)));
        final o = await f.sender().submit(await _q(f), _words);
        expect(o.result, Result.pending, reason: m);
        expect(f.store.items, hasLength(1), reason: m);
      }
      final g = Fake(poly(send: RpcError('intrinsic gas too low')));
      await expectLater(g.sender().submit(await _q(g), _words), _sendError('recusou o envio'));
    });

    test('Polygon: a refusal that follows a transport failure elsewhere is pending, the same refusal on its own is refused', () async {
      final ambiguous = Fake(poly(send: RpcError('insufficient funds', null, true)));
      final o = await ambiguous.sender().submit(await _q(ambiguous), _words);
      expect(o.result, Result.pending);
      expect(ambiguous.store.items, hasLength(1));
      final plain = Fake(poly(send: RpcError('insufficient funds')));
      await expectLater(plain.sender().submit(await _q(plain), _words), _sendError('recusou o envio'));
      expect(plain.store.items, isEmpty);
    });

    test('Solana: a refusal that follows a transport failure elsewhere is pending, the same refusal on its own is refused', () async {
      final ambiguous = Fake(sol(send: RpcError('Blockhash not found', null, true)));
      final o = await ambiguous.sender().submit(await _q(ambiguous, token: _usdcSol), _words);
      expect(o.result, Result.pending);
      expect(ambiguous.store.items, hasLength(1));
      final plain = Fake(sol(send: RpcError('Blockhash not found')));
      await expectLater(plain.sender().submit(await _q(plain, token: _usdcSol), _words), _sendError('recusou o envio'));
      expect(plain.store.items, isEmpty);
    });

    test('Polygon: if ANY node said already known / nonce, a first node\'s "insufficient funds" does not make it refused', () async {
      final mixed = Fake(poly(send: RpcError('insufficient funds', null, false, ['insufficient funds', 'already known'])));
      final o = await mixed.sender().submit(await _q(mixed), _words);
      expect(o.result, Result.pending);
      expect(mixed.store.items, hasLength(1));
      // refusals that all say "not taken", however differently worded, are refused
      final plain = Fake(poly(send: RpcError('insufficient funds', null, false, ['insufficient funds', 'intrinsic gas too low'])));
      await expectLater(plain.sender().submit(await _q(plain), _words), _sendError('recusou o envio'));
      expect(plain.store.items, isEmpty);
    });

    test('Solana: if ANY node said already processed, a first node\'s refusal does not make it refused', () async {
      final mixed = Fake(sol(send: RpcError('Transaction simulation failed', null, false, ['Transaction simulation failed', 'This transaction has already been processed'])));
      expect((await mixed.sender().submit(await _q(mixed, token: _usdcSol), _words)).result, Result.pending);
      expect(mixed.store.items, hasLength(1));
      final plain = Fake(sol(send: RpcError('Transaction simulation failed', null, false, ['Transaction simulation failed', 'Blockhash not found'])));
      await expectLater(plain.sender().submit(await _q(plain, token: _usdcSol), _words), _sendError('recusou o envio'));
    });

    test('Polygon: a node that cannot answer the lookup makes the answer unknown, never "refused"', () async {
      final f = Fake(poly(send: RpcError('insufficient funds')), perNode: {
        n0: {'eth_getTransactionByHash': (_) => null},
        n1: {'eth_getTransactionByHash': (_) => StateError('offline')},
      });
      expect((await f.sender().submit(await _q(f), _words)).result, Result.pending);
    });

    test('Solana: past expiry, one node still unknown but another has it: it is confirmed', () async {
      final f = Fake(sol(height: 2000), perNode: {
        solanaRpcs[0]: {'getSignatureStatuses': (_) => {'value': [null]}},
        solanaRpcs[1]: {'getSignatureStatuses': (_) => {'value': [{'confirmationStatus': 'finalized', 'err': null}]}},
      });
      expect((await f.sender().submit(await _q(f, token: _usdcSol), _words)).result, Result.confirmed);
    });

    test('Solana: past expiry with one node unable to answer is pending, only ALL nodes saying unknown is "not sent"', () async {
      final f = Fake(sol(height: 2000), perNode: {
        solanaRpcs[0]: {'getSignatureStatuses': (_) => {'value': [null]}},
        solanaRpcs[1]: {'getSignatureStatuses': (_) => StateError('offline')},
      });
      expect((await f.sender().submit(await _q(f, token: _usdcSol), _words)).result, Result.pending);
      final g = Fake(sol(height: 2000));
      expect((await g.sender().submit(await _q(g, token: _usdcSol), _words)).result, Result.notSent);
    });

    test('Solana: a refused broadcast that another node actually has is followed, not reported refused', () async {
      final f = Fake(sol(send: RpcError('Blockhash not found')), perNode: {
        solanaRpcs[0]: {'getSignatureStatuses': (_) => {'value': [null]}},
        solanaRpcs[1]: {'getSignatureStatuses': (_) => {'value': [{'confirmationStatus': 'finalized', 'err': null}]}},
      });
      expect((await f.sender().submit(await _q(f, token: _usdcSol), _words)).result, Result.confirmed);
    });
  });

  group('reconcile: settling an open send later', () {
    test('Polygon: a receipt on any node settles it', () async {
      final f = Fake(poly(), perNode: {
        polygonRpcs[0]: {'eth_getTransactionReceipt': (_) => null},
        polygonRpcs[1]: {'eth_getTransactionReceipt': (_) => {'status': '0x1', 'blockNumber': '0x64'}},
      });
      expect((await f.sender().reconcile(polyRecord()))?.result, Result.confirmed);
      final g = Fake(poly(receipt: {'status': '0x0', 'blockNumber': '0x64'}));
      expect((await g.sender().reconcile(polyRecord()))?.result, Result.reverted);
    });

    test('Polygon: still in a mempool, or nodes unreachable, stays open', () async {
      final mempool = Fake(poly(byHash: {'hash': 'x'}));
      expect(await mempool.sender().reconcile(polyRecord()), isNull);
      final dead = poly()..['eth_getTransactionReceipt'] = (_) => StateError('offline');
      expect(await Fake(dead).sender().reconcile(polyRecord()), isNull);
      // one node unreachable must not let "nonce used" decide
      final partial = Fake(poly()..['eth_getTransactionCount'] = (_) => '0x9', perNode: {polygonRpcs[1]: {'eth_getTransactionReceipt': (_) => StateError('offline')}});
      expect(await partial.sender().reconcile(polyRecord()), isNull);
    });

    test('Polygon: not sent only when nobody has it AND its nonce was taken by another transaction', () async {
      final taken = Fake(poly()..['eth_getTransactionCount'] = (_) => '0x8');
      expect((await taken.sender().reconcile(polyRecord()))?.result, Result.notSent);
      final free = Fake(poly()..['eth_getTransactionCount'] = (_) => '0x7');
      expect(await free.sender().reconcile(polyRecord()), isNull);
    });

    test('Solana: confirmed, reverted, seen-but-unconfirmed, expired and not yet expired', () async {
      expect((await Fake(sol(status: {'confirmationStatus': 'finalized', 'err': null})).sender().reconcile(solRecord()))?.result, Result.confirmed);
      expect((await Fake(sol(status: {'confirmationStatus': 'finalized', 'err': 'x'})).sender().reconcile(solRecord()))?.result, Result.reverted);
      expect(await Fake(sol(status: {'confirmationStatus': 'processed', 'err': null}, height: 2000)).sender().reconcile(solRecord()), isNull);
      expect((await Fake(sol(height: 2000)).sender().reconcile(solRecord()))?.result, Result.notSent);
      expect(await Fake(sol(height: 10)).sender().reconcile(solRecord()), isNull);
    });

    test('Solana: a node that cannot answer keeps it open even past expiry', () async {
      final f = Fake(sol(height: 2000), perNode: {solanaRpcs[1]: {'getSignatureStatuses': (_) => StateError('offline')}});
      expect(await f.sender().reconcile(solRecord()), isNull);
    });
  });


  group('only finality settles a send', () {
    test('Polygon: a receipt in a block that is not final yet is still pending, and keeps the record', () async {
      for (final status in ['0x1', '0x0']) {
        final f = Fake(poly(receipt: {'status': status, 'blockNumber': '0x65'}, finalized: 100));
        final o = await f.sender().submit(await _q(f), _words);
        expect(o.result, Result.pending, reason: status);
        expect(f.store.items, hasLength(1), reason: status);
      }
      final done = Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x64'}, finalized: 100));
      expect((await done.sender().submit(await _q(done), _words)).result, Result.confirmed);
      final failed = Fake(poly(receipt: {'status': '0x0', 'blockNumber': '0x63'}, finalized: 100));
      expect((await failed.sender().submit(await _q(failed), _words)).result, Result.reverted);
    });

    test('Polygon: a node that cannot say which block is final settles nothing', () async {
      final h = poly(receipt: {'status': '0x1', 'blockNumber': '0x1'})..['eth_getBlockByNumber'] = (p) => p[0] == 'finalized' ? RpcError('unsupported tag') : {'baseFeePerGas': '0x1'};
      final f = Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x1'}));
      final q = await _q(f);
      f.on['eth_getBlockByNumber'] = h['eth_getBlockByNumber']!;
      expect((await f.sender().submit(q, _words)).result, Result.pending);
    });

    test('Solana: processed and confirmed settle nothing, an error is only reverted once final', () async {
      for (final (label, st) in [
        ('processed', {'confirmationStatus': 'processed', 'err': null}),
        ('confirmed', {'confirmationStatus': 'confirmed', 'err': null}),
        ('confirmed with error', {'confirmationStatus': 'confirmed', 'err': 'x'}),
      ]) {
        final f = Fake(sol(status: st));
        final o = await f.sender().submit(await _q(f, token: _usdcSol), _words);
        expect(o.result, Result.pending, reason: label);
        expect(f.store.items, hasLength(1), reason: label);
      }
      final f = Fake(sol(status: {'confirmationStatus': 'finalized', 'err': 'x'}));
      expect((await f.sender().submit(await _q(f, token: _usdcSol), _words)).result, Result.reverted);
    });

    test('reconcile: a receipt not final yet, or a Solana status not finalized, stays open', () async {
      expect(await Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x65'}, finalized: 100)).sender().reconcile(polyRecord()), isNull);
      expect((await Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x64'}, finalized: 100)).sender().reconcile(polyRecord()))?.result, Result.confirmed);
      expect(await Fake(sol(status: {'confirmationStatus': 'confirmed', 'err': null})).sender().reconcile(solRecord()), isNull);
      expect((await Fake(sol(status: {'confirmationStatus': 'finalized', 'err': null})).sender().reconcile(solRecord()))?.result, Result.confirmed);
    });

    test('reconcile: "not sent" reads the nonce at the FINALIZED level, on EVERY node', () async {
      final latestOnly = Fake(poly()..['eth_getTransactionCount'] = (p) => p[1] == 'finalized' ? '0x7' : '0x8');
      expect(await latestOnly.sender().reconcile(polyRecord()), isNull);
      final finalizedUsed = Fake(poly()..['eth_getTransactionCount'] = (p) => p[1] == 'finalized' ? '0x8' : '0x7');
      expect((await finalizedUsed.sender().reconcile(polyRecord()))?.result, Result.notSent);
      final oneBehind = Fake(poly()..['eth_getTransactionCount'] = (_) => '0x8', perNode: {polygonRpcs[2]: {'eth_getTransactionCount': (_) => '0x7'}});
      expect(await oneBehind.sender().reconcile(polyRecord()), isNull);
      // a transaction a pool still lists is not "waiting" once its nonce is final: it can never mine
      final stale = Fake(poly(byHash: {'hash': 'x'})..['eth_getTransactionCount'] = (_) => '0x8');
      expect((await stale.sender().reconcile(polyRecord()))?.result, Result.notSent);
    });
  });

  group('cancelling an open Polygon send with a same-nonce replacement', () {
    final record = PendingSend(id: '0xabc', net: 'polygon', symbol: 'USDT', amount: '1500000', to: _bob, from: vEvmAddress, createdMs: agoMs(const Duration(minutes: 5)), nonce: 7, tip: '30000000000', maxFee: '100000000000');

    /// A node where the original never mined; broadcasting the replacement uses the nonce (or, with [originalWins], the original lands).
    ({Fake fake, List<String> sent}) world({bool originalWins = false, Object? send, BigInt? pol, bool cancelLands = true}) {
      final sent = <String>[];
      var used = false;
      var mined = false;
      final h = poly();
      h['eth_getTransactionCount'] = (p) => p[1] == 'finalized' ? (used ? '0x8' : '0x7') : '0x7';
      h['eth_getTransactionReceipt'] = (_) => mined ? {'status': '0x1', 'blockNumber': '0x64'} : null;
      if (pol != null) h['eth_getBalance'] = (_) => _h(pol);
      h['eth_sendRawTransaction'] = (p) {
        sent.add(p[0] as String);
        if (originalWins) {
          mined = true;
          used = true;
          return RpcError('nonce too low: next nonce 8, tx nonce 7');
        }
        used = cancelLands;
        return send ?? '0xcancel';
      };
      return (fake: Fake(h), sent: sent);
    }

    test('the replacement is exactly: same nonce, to the wallet itself, no value, 21000 gas, twice the fees', () async {
      final w = world();
      final o = await w.fake.sender().cancelPolygon(record, _words);
      expect(o?.result, Result.notSent);
      expect(w.sent, hasLength(1));
      // market now: base 30 gwei, node tip 20 gwei -> tip floor 25, maxFee 2*30+25 = 85. The original used 30 / 100: twice the larger of each
      final expected = signTx(
        Eip1559Tx(nonce: 7, maxPriorityFee: BigInt.from(60) * _gwei, maxFee: BigInt.from(200) * _gwei, gasLimit: 21000, to: evmAddressBytes(vEvmAddress), data: Uint8List(0)),
        hexToBytes(vEvmKeyHex),
        expectedAddress: vEvmAddress,
      );
      expect(w.sent.single, expected.rawHex);
    });

    test('an old record without fees is outbid from the market instead', () async {
      final w = world();
      final bare = PendingSend(id: '0xabc', net: 'polygon', symbol: 'USDT', amount: '1', to: _bob, from: vEvmAddress, createdMs: agoMs(const Duration(minutes: 5)), nonce: 7);
      await w.fake.sender().cancelPolygon(bare, _words);
      final expected = signTx(
        Eip1559Tx(nonce: 7, maxPriorityFee: BigInt.from(50) * _gwei, maxFee: BigInt.from(170) * _gwei, gasLimit: 21000, to: evmAddressBytes(vEvmAddress), data: Uint8List(0)),
        hexToBytes(vEvmKeyHex),
        expectedAddress: vEvmAddress,
      );
      expect(w.sent.single, expected.rawHex);
    });

    test('if the original lands first, that is what is reported: confirmed, not cancelled', () async {
      final w = world(originalWins: true);
      expect((await w.fake.sender().cancelPolygon(record, _words))?.result, Result.confirmed);
    });

    test('nothing is sent when the send is already settled', () async {
      final mined = poly(receipt: {'status': '0x1', 'blockNumber': '0x64'});
      final a = Fake(mined);
      expect((await a.sender().cancelPolygon(record, _words))?.result, Result.confirmed);
      expect(a.calls.contains('eth_sendRawTransaction'), isFalse);
      final taken = Fake(poly()..['eth_getTransactionCount'] = (_) => '0x8');
      expect((await taken.sender().cancelPolygon(record, _words))?.result, Result.notSent);
      expect(taken.calls.contains('eth_sendRawTransaction'), isFalse);
    });

    test('refusals before or at the broadcast are errors that leave the original open', () async {
      final poor = world(pol: BigInt.from(1000));
      await expectLater(poor.fake.sender().cancelPolygon(record, _words), _sendError('POL insuficiente para cancelar'));
      expect(poor.sent, isEmpty);
      final refused = world(send: null);
      refused.fake.on['eth_sendRawTransaction'] = (_) => RpcError('insufficient funds for gas');
      await expectLater(refused.fake.sender().cancelPolygon(record, _words), _sendError('recusou o cancelamento'));
      await expectLater(Fake(poly()).sender().cancelPolygon(solRecord(), _words), throwsA(isA<SendError>()));
      final other = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong'.split(' ');
      final w = world();
      await expectLater(w.fake.sender().cancelPolygon(record, other), throwsA(isA<SendError>()));
      expect(w.sent, isEmpty);
    });

    test('a replacement the network never confirms leaves it open (null), not "cancelled"', () async {
      final w = world(cancelLands: false);
      expect(await w.fake.sender().cancelPolygon(record, _words), isNull);
      expect(w.sent, hasLength(1));
    });

    test('a replacement refused by one node while another already has a nonce taken is not an error either', () async {
      final w = world();
      w.fake.on['eth_sendRawTransaction'] = (_) => RpcError('insufficient funds', null, false, ['insufficient funds', 'nonce too low']);
      expect(await w.fake.sender().cancelPolygon(record, _words), isNull);
    });

    test('an ambiguous or nonce refusal of the replacement is followed by looking at the chain, not an error', () async {
      final w = world();
      w.fake.on['eth_sendRawTransaction'] = (_) => RpcError('replacement transaction underpriced');
      expect(await w.fake.sender().cancelPolygon(record, _words), isNull);
    });
  });


  group('Solana history is only trusted soon after the send', () {
    test('reconcile: expired and unknown is "not sent" within the hour, but stays open once stale', () async {
      expect((await Fake(sol(height: 2000)).sender().reconcile(solRecord(age: const Duration(minutes: 59)))), isA<Outcome>().having((o) => o.result, 'result', Result.notSent));
      expect(await Fake(sol(height: 2000)).sender().reconcile(solRecord(age: const Duration(minutes: 61))), isNull);
      expect(await Fake(sol(height: 2000)).sender().reconcile(solRecord(age: const Duration(days: 3))), isNull);
    });

    test('reconcile: a finalized status still settles a stale record, whichever way', () async {
      final old = solRecord(age: const Duration(days: 3));
      expect((await Fake(sol(status: {'confirmationStatus': 'finalized', 'err': null})).sender().reconcile(old))?.result, Result.confirmed);
      expect((await Fake(sol(status: {'confirmationStatus': 'finalized', 'err': 'x'})).sender().reconcile(old))?.result, Result.reverted);
    });

    test('discard: only a stale Solana record, and only when the chain does not settle it just then', () async {
      final f = Fake(sol(height: 2000));
      final stale = solRecord(age: const Duration(hours: 5));
      f.store.items.add(stale);
      expect(await f.sender().discardStale(stale), isNull);
      expect(f.store.items, isEmpty);
      // settled by the chain at that very moment: reported, not discarded on trust
      final g = Fake(sol(status: {'confirmationStatus': 'finalized', 'err': null}));
      g.store.items.add(stale);
      expect((await g.sender().discardStale(stale))?.result, Result.confirmed);
      expect(g.store.items, isEmpty);
    });

    test('discard is refused for any RECENT record, on either network, and leaves it open', () async {
      final f = Fake(sol(height: 2000));
      final fresh = solRecord(age: const Duration(minutes: 20));
      f.store.items.add(fresh);
      await expectLater(f.sender().discardStale(fresh), throwsA(isA<SendError>()));
      expect(f.store.items, hasLength(1));
      final g = Fake(poly()..['eth_getTransactionCount'] = (_) => '0x8');
      final p = polyRecord(age: const Duration(minutes: 59));
      g.store.items.add(p);
      await expectLater(g.sender().discardStale(p), throwsA(isA<SendError>()));
      expect(g.store.items, hasLength(1));
    });

    test('Polygon: "not sent" (nonce used, no receipt anywhere) is only concluded within the hour', () async {
      final used = poly()..['eth_getTransactionCount'] = (_) => '0x8';
      expect((await Fake(used).sender().reconcile(polyRecord(age: const Duration(minutes: 59))))?.result, Result.notSent);
      expect(await Fake(used).sender().reconcile(polyRecord(age: const Duration(minutes: 61))), isNull);
      expect(await Fake(used).sender().reconcile(polyRecord(age: const Duration(days: 4))), isNull);
      // a final receipt still settles it at any age: that is positive evidence, not an absence
      final mined = Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x64'})..['eth_getTransactionCount'] = (_) => '0x8');
      expect((await mined.sender().reconcile(polyRecord(age: const Duration(days: 4))))?.result, Result.confirmed);
    });

    test('Polygon: a stale record can be discarded (after a last look at the chain); the cancel is refused for it', () async {
      final f = Fake(poly()..['eth_getTransactionCount'] = (_) => '0x8');
      final old = polyRecord(age: const Duration(hours: 6));
      f.store.items.add(old);
      await expectLater(f.sender().cancelPolygon(old, _words), _sendError('Polygonscan'));
      expect(f.calls.contains('eth_sendRawTransaction'), isFalse);
      expect(await f.sender().discardStale(old), isNull);
      expect(f.store.items, isEmpty);
      // settled by a final receipt at that moment: reported instead
      final g = Fake(poly(receipt: {'status': '0x1', 'blockNumber': '0x64'}));
      g.store.items.add(old);
      expect((await g.sender().discardStale(old))?.result, Result.confirmed);
      expect(g.store.items, isEmpty);
    });
  });
}
