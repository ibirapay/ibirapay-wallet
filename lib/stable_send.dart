// Sending USDT / USDC on Polygon and Solana, without UI: validate the recipient and the amount, quote (balance, gas, recipient
// account), then submit (sign, broadcast, track). Network calls go through an injected [RpcFn] so each decision is testable.
//
// Outcome rule: only say "not sent" when that is certain (the network refused it, or a Solana blockhash expired). Anything
// unknown is `pending` with the transaction id, because a new send after an unseen one can pay twice.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'base58.dart';
import 'chain_balances.dart';
import 'evm_tx.dart';
import 'i18n.dart';
import 'pending_sends.dart';
import 'sol_tx.dart';
import 'wallet_seed.dart';

enum Net { polygon, solana }

class StableToken {
  const StableToken(this.net, this.symbol, this.id);
  final Net net;
  final String symbol;

  /// The ERC-20 contract on Polygon, the mint on Solana.
  final String id;
  String get netName => net == Net.polygon ? 'Polygon' : 'Solana';
  String get gasSymbol => net == Net.polygon ? 'POL' : 'SOL';
}

/// What Enviar offers per network. USDC.e (the older bridged USDC) is listed here and shown by the sheet only when held.
final polygonSendTokens = [for (final e in polygonTokens.entries) StableToken(Net.polygon, e.key, e.value)];
final solanaSendTokens = [for (final e in solanaMints.entries) StableToken(Net.solana, e.key, e.value)];

/// A refusal with a message for the user. Thrown only when nothing was broadcast.
class SendError implements Exception {
  SendError(this.message);
  final String message;
  @override
  String toString() => message;
}

enum Result { confirmed, reverted, notSent, pending }

class Outcome {
  const Outcome(this.result, this.id, this.explorer);
  final Result result;

  /// The transaction hash (Polygon) or signature (Solana), always known once a send was signed.
  final String id;
  final String explorer;
}

const stableDecimals6 = 6;

/// How long after a send the public nodes can still be trusted to remember it. Their history is pruned (a Solana status, a Polygon
/// receipt), so past this an unanswered lookup proves nothing: the send stays open instead of becoming "not sent".
const staleAfter = Duration(hours: 1);

bool isStale(PendingSend r) => DateTime.now().millisecondsSinceEpoch - r.createdMs > staleAfter.inMilliseconds;

/// "1", "1,5", "1.5", "0,000001" -> smallest units. Never a double. Rejects what could be read two ways: "1.000" is one thousand
/// in pt-BR and one in en-US, so it is refused instead of guessed.
BigInt parseStableAmount(String text) {
  final t = text.trim();
  if (t.isEmpty) throw SendError(tr('st.enterAmount'));
  final m = RegExp(r'^(\d+)(?:[.,](\d+))?$').firstMatch(t);
  if (m == null) throw SendError(tr('st.badAmount'));
  final frac = m[2] ?? '';
  if (frac.length > stableDecimals6) throw SendError(tr('st.decimals', {'n': stableDecimals6}));
  if (frac.length == 3 && m[1]!.length <= 3 && !m[1]!.startsWith('0')) {
    final decimal = frac.replaceFirst(RegExp(r'0+$'), '');
    throw SendError(tr('st.ambiguous', {'t': t, 'a': '${m[1]}$frac', 'b': '${m[1]}${decimalSeparator()}${decimal.isEmpty ? '0' : decimal}'}));
  }
  final v = BigInt.parse(m[1]!) * BigInt.from(10).pow(stableDecimals6) + BigInt.parse(frac.padRight(stableDecimals6, '0'));
  if (v == BigInt.zero) throw SendError(tr('st.zero'));
  return v;
}

/// [raw] in units of 10^-[decimals], exact, with at least [minPlaces] places and no trailing zeros beyond them.
String fmtUnits(BigInt raw, int decimals, {int minPlaces = 2}) {
  final base = BigInt.from(10).pow(decimals);
  var frac = (raw % base).toString().padLeft(decimals, '0');
  while (frac.length > minPlaces && frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  return '${raw ~/ base}${decimalSeparator()}$frac';
}

// ---- recipient parsing

/// EIP-681: `[ethereum:|polygon:][pay-]TARGET[@chain][/function][?query]`. With a function, TARGET is the CONTRACT being called and
/// the beneficiary is in the query, so the two must never be mixed up.
final _evmInput = RegExp(r'^(?:ethereum:|polygon:)?(?:pay-)?(0x[0-9a-fA-F]{40})(?:@(\d+))?(?:/([A-Za-z_]\w*))?(?:\?(.*))?$', caseSensitive: false);

/// The checksummed Polygon recipient in [input]: a plain address, or an EIP-681 link. A link that names another chain is refused:
/// the same 0x address exists on every EVM chain and tokens sent on the wrong one are lost. A link that calls a function is only
/// accepted as `transfer` on the [token] contract the user selected, and then the recipient is its `address` parameter, never the
/// contract itself.
String parsePolygonRecipient(String input, {String? token}) {
  final m = _evmInput.firstMatch(input.trim());
  if (m == null) throw SendError(tr('st.badPolygon'));
  final chain = m[2];
  if (chain != null && int.parse(chain) != polygonChainId) {
    throw SendError(tr('st.qrOtherChain', {'chain': chain}));
  }
  var a = m[1]!;
  final function = m[3];
  if (function != null) {
    if (function != 'transfer') throw SendError(tr('st.qrFunction', {'fn': function}));
    if (token == null || a.toLowerCase() != token.toLowerCase()) {
      throw SendError(tr('st.qrOtherToken'));
    }
    final to = RegExp(r'(?:^|&)address=(0x[0-9a-fA-F]{40})(?:&|$)', caseSensitive: false).firstMatch(m[4] ?? '');
    if (to == null) throw SendError(tr('st.qrNoRecipient'));
    a = to[1]!;
  }
  final body = a.substring(2);
  final mixed = body != body.toLowerCase() && body != body.toUpperCase();
  final checksummed = checksumEvmAddress(a);
  if (mixed && checksummed != a) throw SendError(tr('st.typo'));
  if (RegExp(r'^0x0{40}$').hasMatch(a)) throw SendError(tr('st.zeroAddress'));
  if (polygonTokens.values.any((c) => c.toLowerCase() == a.toLowerCase())) {
    throw SendError(tr('st.tokenContract'));
  }
  return checksummed;
}

String parseSolanaRecipient(String input) {
  var t = input.trim();
  if (t.toLowerCase().startsWith('solana:')) t = t.substring(7);
  t = t.split(RegExp(r'[?/]')).first;
  try {
    solPubkey(t);
  } on FormatException {
    throw SendError(tr('st.badSolana'));
  }
  return t;
}

// ---- the quote

class Quote {
  const Quote._({
    required this.token,
    required this.from,
    required this.to,
    required this.amount,
    required this.balance,
    required this.fee,
    required this.gasBalance,
    required this.rent,
    required this.warnings,
    required this.plan,
  });
  final StableToken token;
  final String from;
  final String to;
  final BigInt amount;
  final BigInt balance;

  /// Gas in wei (Polygon, the worst case) or lamports (Solana, the exact fee).
  final BigInt fee;
  final BigInt gasBalance;

  /// Lamports to create the recipient's token account (Solana), zero otherwise.
  final BigInt rent;
  final List<String> warnings;
  final Object plan;
}

class _EvmPlan {
  const _EvmPlan(this.tip, this.maxFee, this.gasLimit);
  final BigInt tip;
  final BigInt maxFee;
  final int gasLimit;
}

class _SolPlan {
  const _SolPlan(this.source, this.dest, this.createOwner);
  final Uint8List source;
  final Uint8List dest;

  /// The recipient wallet when its token account has to be created, else null.
  final Uint8List? createOwner;
}

final _gwei = BigInt.from(1000000000);
final _polygonTipFloor = BigInt.from(25) * _gwei; // the network's minimum priority fee

BigInt _hb(Object? v) {
  final s = '$v'.replaceFirst('0x', '');
  return s.isEmpty ? BigInt.zero : BigInt.parse(s, radix: 16);
}

class StableSender {
  /// [store] is required on purpose: a default would let a send go out without being remembered.
  StableSender({required this.store, RpcFn? call, this.pollEvery = const Duration(seconds: 2), this.maxWait = const Duration(seconds: 90)}) : _rpc = call ?? rpc;
  final PendingStore store;
  final RpcFn _rpc;
  final Duration pollEvery;
  final Duration maxWait;

  Future<dynamic> _poly(String m, List<dynamic> p) => _rpc(polygonRpcs, m, p);
  Future<dynamic> _sol(String m, List<dynamic> p) => _rpc(solanaRpcs, m, p);

  /// What EVERY node says on its own, not the first answer: a node that lags returns "unknown" for a transaction another node has.
  Future<List<({Object? v, bool ok})>> _eachNode(List<String> nodes, String method, List<dynamic> params) => Future.wait([
    for (final n in nodes)
      () async {
        try {
          return (v: await _rpc([n], method, params) as Object?, ok: true);
        } catch (_) {
          return (v: null as Object?, ok: false);
        }
      }(),
  ]);

  /// Runs a store operation; a store that cannot be used stops the send before anything is broadcast.
  Future<T> _stored<T>(Future<T> Function() op) async {
    try {
      return await op();
    } catch (_) {
      throw SendError(tr('st.noRegistry'));
    }
  }

  /// Best effort: a record that cannot be removed only shows a stale notice that the next check clears.
  Future<void> _forget(String id) async {
    try {
      await store.remove(id);
    } catch (_) {
      // see above
    }
  }

  Future<Quote> quote({required StableToken token, required String from, required String to, required BigInt amount}) async {
    try {
      return token.net == Net.polygon ? await _quotePolygon(token, from, to, amount) : await _quoteSolana(token, from, to, amount);
    } on RpcError catch (e) {
      throw SendError(tr('st.queryRefused', {'e': e.message}));
    } on StateError {
      throw SendError(tr('st.noNodeRetry', {'net': token.netName}));
    }
  }

  /// Signs and broadcasts [q]. Whatever throws here threw BEFORE anything was broadcast; once it is out the result is an [Outcome].
  /// The send is written to the device's record before it is broadcast and stays there until its outcome is certain.
  Future<Outcome> submit(Quote q, List<String> words) async {
    try {
      final open = (await _stored(store.all)).where((r) => r.net == q.token.net.name);
      if (open.isNotEmpty) {
        throw SendError(tr('st.openSend', {'net': q.token.netName}));
      }
      return q.token.net == Net.polygon ? await _submitPolygon(q, words) : await _submitSolana(q, words);
    } on WalletError {
      throw SendError(tr('st.internal')); // e.message is a developer text (Portuguese): not shown
    } on RpcError catch (e) {
      throw SendError(tr('st.netRefusedNothing', {'e': e.message}));
    } on StateError {
      throw SendError(tr('st.noNodeNothing', {'net': q.token.netName}));
    }
  }

  /// Takes the network's one slot for this send, in one atomic step; if another send got it first, nothing is broadcast.
  Future<void> _reserve(Quote q, PendingSend rec) async {
    if (!await _stored(() => store.putIfNoneOpen(q.token.net.name, rec))) {
      throw SendError(tr('st.openSend', {'net': q.token.netName}));
    }
  }

  PendingSend _record(Quote q, String id, {int? nonce, int? lastValid, BigInt? tip, BigInt? maxFee}) => PendingSend(
    id: id,
    net: q.token.net.name,
    symbol: q.token.symbol,
    amount: q.amount.toString(),
    to: q.to,
    from: q.from,
    createdMs: DateTime.now().millisecondsSinceEpoch,
    nonce: nonce,
    lastValid: lastValid,
    tip: tip?.toString(),
    maxFee: maxFee?.toString(),
  );

  /// Broadcasts and follows an already-recorded send through [run]. A refusal before broadcasting clears the record; anything
  /// unexpected AFTER signing is "unknown", never "not sent"; a certain outcome clears the record, an uncertain one keeps it.
  Future<Outcome> _finish(String id, String explorer, Future<Outcome> Function() run) async {
    Outcome out;
    try {
      out = await run();
    } on SendError {
      await _forget(id);
      rethrow;
    } catch (_) {
      out = Outcome(Result.pending, id, explorer);
    }
    if (out.result != Result.pending) await _forget(id);
    return out;
  }


  // ---- Polygon

  /// The priority fee (the network's 25 gwei floor, or the node's if higher) and the max fee (twice the base fee, plus the tip).
  Future<({BigInt tip, BigInt maxFee})> _polygonFees() async {
    final block = await _poly('eth_getBlockByNumber', ['latest', false]) as Map;
    if (block['baseFeePerGas'] == null) throw SendError(tr('st.noBaseFee'));
    final baseFee = _hb(block['baseFeePerGas']);
    var tip = _polygonTipFloor;
    try {
      final node = _hb(await _poly('eth_maxPriorityFeePerGas', const []));
      if (node > tip) tip = node;
    } catch (_) {
      // a node without that method: the network floor is enough
    }
    return (tip: tip, maxFee: baseFee * BigInt.two + tip);
  }

  Future<Quote> _quotePolygon(StableToken token, String from, String toInput, BigInt amount) async {
    final to = parsePolygonRecipient(toInput, token: token.id);
    if (_hb(await _poly('eth_chainId', const [])) != BigInt.from(polygonChainId)) {
      throw SendError(tr('st.wrongChainNode'));
    }
    final balanceData = '0x70a08231${from.toLowerCase().replaceFirst('0x', '').padLeft(64, '0')}';
    final balance = _hb(await _poly('eth_call', [{'to': token.id, 'data': balanceData}, 'latest']));
    if (amount > balance) {
      throw SendError(tr('st.lowBalancePoly', {'sym': token.symbol, 'have': fmtUnits(balance, stableDecimals6)}));
    }
    final pol = _hb(await _poly('eth_getBalance', [from, 'latest']));
    final (:tip, :maxFee) = await _polygonFees();
    final data = '0x${bytesToHex(erc20TransferData(to, amount))}';
    final BigInt estimate;
    try {
      estimate = _hb(await _poly('eth_estimateGas', [{'from': from, 'to': token.id, 'data': data}]));
    } on RpcError catch (e) {
      throw SendError(tr('st.polyRefusedTransfer', {'e': e.message}));
    }
    final gasLimit = (estimate * BigInt.from(125) ~/ BigInt.from(100)).toInt();
    final fee = maxFee * BigInt.from(gasLimit);
    if (pol < fee) {
      throw SendError(tr('st.lowPol', {'need': fmtUnits(fee, 18, minPlaces: 4), 'have': fmtUnits(pol, 18, minPlaces: 4)}));
    }
    return Quote._(
      token: token,
      from: from,
      to: to,
      amount: amount,
      balance: balance,
      fee: fee,
      gasBalance: pol,
      rent: BigInt.zero,
      warnings: [if (to == checksumEvmAddress(from)) tr('st.ownWallet')],
      plan: _EvmPlan(tip, maxFee, gasLimit),
    );
  }

  Future<Outcome> _submitPolygon(Quote q, List<String> words) async {
    final plan = q.plan as _EvmPlan;
    final nonce = _hb(await _poly('eth_getTransactionCount', [q.from, 'pending'])).toInt();
    final tx = Eip1559Tx(
      nonce: nonce,
      maxPriorityFee: plan.tip,
      maxFee: plan.maxFee,
      gasLimit: plan.gasLimit,
      to: evmAddressBytes(q.token.id),
      data: erc20TransferData(q.to, q.amount),
    );
    final seed = mnemonicToSeed(words);
    Uint8List? key;
    final SignedTx signed;
    try {
      key = deriveEvmPrivateKey(seed);
      signed = signTx(tx, key, expectedAddress: q.from);
    } finally {
      wipe(seed);
      if (key != null) wipe(key);
    }
    final explorer = 'https://polygonscan.com/tx/${signed.hashHex}';
    // remembered BEFORE it can be on the network: if the app dies from here on, the next start still knows about it
    await _reserve(q, _record(q, signed.hashHex, nonce: nonce, tip: plan.tip, maxFee: plan.maxFee));
    return _finish(signed.hashHex, explorer, () => _broadcastPolygon(signed, explorer));
  }

  /// A refusal that talks about the nonce ("already known", "nonce too low", "underpriced") is the one case where the
  /// transaction may still be this very one, somewhere a lagging node cannot see yet: that is never reported as "not sent".
  static final _nonceTalk = RegExp(r'already known|known transaction|already imported|nonce too low|underpriced', caseSensitive: false);

  Future<Outcome> _broadcastPolygon(SignedTx signed, String explorer) async {
    final pending = Outcome(Result.pending, signed.hashHex, explorer);
    try {
      await _poly('eth_sendRawTransaction', [signed.rawHex]);
    } on RpcError catch (e) {
      final bool known;
      try {
        known = await _polygonKnows(signed.hashHex);
      } catch (_) {
        return pending; // cannot tell
      }
      if (!known) {
        // only "taken" evidence matters, and ANY node's word counts: an earlier node may have taken it without our hearing
        // (ambiguous), or another node may already know it, or the refusal is about the nonce itself
        if (e.ambiguous || [e.message, ...e.messages].any(_nonceTalk.hasMatch)) return pending;
        throw SendError(tr('st.polyRefusedSend', {'e': e.message}));
      }
    } on StateError {
      // no node answered: it may still have been delivered to one of them
      var known = false;
      try {
        known = await _polygonKnows(signed.hashHex);
      } catch (_) {
        // cannot tell
      }
      if (!known) return pending;
    }
    final end = DateTime.now().add(maxWait);
    while (true) {
      try {
        final r = await _poly('eth_getTransactionReceipt', [signed.hashHex]);
        if (r is Map && r['status'] != null && await _polygonFinal(r)) {
          return Outcome(_hb(r['status']) == BigInt.one ? Result.confirmed : Result.reverted, signed.hashHex, explorer);
        }
      } catch (_) {
        // a flaky node: ask again until the deadline
      }
      if (!DateTime.now().isBefore(end)) return pending;
      await Future<void>.delayed(pollEvery);
    }
  }

  /// The newest block that can no longer be reorganised. A node that lags reports an older one, which only makes us wait longer.
  Future<BigInt> _finalizedBlock() async => _hb(((await _poly('eth_getBlockByNumber', ['finalized', false])) as Map)['number']);

  /// Whether the block that holds [receipt] is final. A receipt in a block that may still be reorganised settles nothing: its
  /// outcome could change, and "failed" or "not sent" would invite a second payment.
  Future<bool> _polygonFinal(Map receipt) async => _hb(receipt['blockNumber']) <= await _finalizedBlock();

  /// Whether ANY node has [hash]. False only when every node answered that it does not; throws when none had it and some could
  /// not answer: an unknown is never read as "not there".
  Future<bool> _polygonKnows(String hash) async {
    final each = await _eachNode(polygonRpcs, 'eth_getTransactionByHash', [hash]);
    if (each.any((a) => a.ok && a.v != null)) return true;
    if (each.any((a) => !a.ok)) throw StateError('algum nó não respondeu');
    return false;
  }

  // ---- Solana

  Future<List<({String pubkey, BigInt amount, String state})>> _tokenAccounts(String owner, String mint) async {
    final r = await _sol('getTokenAccountsByOwner', [owner, {'mint': mint}, {'encoding': 'jsonParsed', 'commitment': 'confirmed'}]) as Map;
    return [
      for (final a in (r['value'] as List))
        (
          pubkey: a['pubkey'] as String,
          amount: BigInt.parse(a['account']['data']['parsed']['info']['tokenAmount']['amount'] as String),
          state: a['account']['data']['parsed']['info']['state'] as String,
        ),
    ];
  }

  /// The accounts [token] can be sent from. The wallet's associated account is read directly (every node serves that); the
  /// indexed by-owner lookup, which some public nodes refuse, is only needed when it is missing or too small.
  Future<List<({String pubkey, BigInt amount, String state})>> _sourceAccounts(Uint8List owner, Uint8List mint, String from, StableToken token, BigInt amount) async {
    final ata = base58Encode(associatedTokenAccount(owner, mint));
    final info = await _accountInfo(ata);
    final parsed = info?['data'] is Map ? info!['data']['parsed'] : null;
    if (info != null && info['owner'] == tokenProgramId && parsed is Map && parsed['info']['mint'] == token.id) {
      final held = BigInt.parse(parsed['info']['tokenAmount']['amount'] as String);
      if (held >= amount) return [(pubkey: ata, amount: held, state: parsed['info']['state'] as String)];
    }
    return _tokenAccounts(from, token.id);
  }

  Future<Map?> _accountInfo(String address) async {
    final r = await _sol('getAccountInfo', [address, {'encoding': 'jsonParsed', 'commitment': 'confirmed'}]) as Map;
    return r['value'] as Map?;
  }

  Future<int> _lamports(String address) async => ((await _sol('getBalance', [address, {'commitment': 'confirmed'}]) as Map)['value'] as int);

  String _b64(Uint8List b) => base64Encode(b);

  List<Ix> _solIxs(Uint8List owner, Uint8List mint, _SolPlan p, BigInt amount) => [
    if (p.createOwner != null) createAtaIdempotent(payer: owner, ata: p.dest, owner: p.createOwner!, mint: mint),
    transferChecked(source: p.source, mint: mint, dest: p.dest, authority: owner, amount: amount, decimals: stableDecimals6),
  ];

  Future<({Uint8List blockhash, int lastValid})> _blockhash() async {
    final v = (await _sol('getLatestBlockhash', [{'commitment': 'confirmed'}]) as Map)['value'] as Map;
    return (blockhash: solPubkey(v['blockhash'] as String), lastValid: v['lastValidBlockHeight'] as int);
  }

  Future<Quote> _quoteSolana(StableToken token, String from, String toInput, BigInt amount) async {
    final to = parseSolanaRecipient(toInput);
    final owner = solPubkey(from);
    final recipient = solPubkey(to);
    final mint = solPubkey(token.id);

    final held = await _sourceAccounts(owner, mint, from, token, amount);
    final accounts = held.where((a) => a.state == 'initialized').toList()..sort((a, b) => b.amount.compareTo(a.amount));
    if (accounts.isEmpty && held.any((a) => a.amount > BigInt.zero)) {
      throw SendError(tr('st.frozenOwn', {'sym': token.symbol}));
    }
    final total = accounts.fold(BigInt.zero, (s, a) => s + a.amount);
    if (accounts.isEmpty || total < amount) {
      throw SendError(tr('st.lowBalanceSol', {'sym': token.symbol, 'have': fmtUnits(total, stableDecimals6)}));
    }
    if (accounts.first.amount < amount) {
      throw SendError(tr('st.splitAccounts', {'sym': token.symbol}));
    }
    final source = solPubkey(accounts.first.pubkey);

    // where it lands: the recipient's token account, which may have to be created
    Uint8List dest;
    Uint8List? createOwner;
    final warnings = <String>[];
    final info = await _accountInfo(to);
    final owningProgram = info?['owner'];
    if (info == null || owningProgram == systemProgramId) {
      dest = associatedTokenAccount(recipient, mint);
      final ataInfo = await _accountInfo(base58Encode(dest));
      if (ataInfo == null) {
        createOwner = recipient;
      } else {
        final parsed = ataInfo['data'] is Map ? ataInfo['data']['parsed'] : null;
        final okAccount = ataInfo['owner'] == tokenProgramId && parsed is Map && parsed['info']['mint'] == token.id && parsed['info']['state'] == 'initialized';
        if (!okAccount) throw SendError(tr('st.destFrozenOrInvalid', {'sym': token.symbol}));
      }
    } else if (owningProgram == tokenProgramId) {
      final parsed = info['data'] is Map ? info['data']['parsed'] : null;
      if (parsed is! Map || parsed['type'] != 'account' || parsed['info']['mint'] != token.id) {
        throw SendError(tr('st.otherTokenAccount'));
      }
      if (parsed['info']['state'] != 'initialized') throw SendError(tr('st.destFrozen', {'sym': token.symbol}));
      dest = recipient;
    } else {
      throw SendError(tr('st.notWallet'));
    }
    if (to == from) warnings.add(tr('st.ownWallet'));

    final plan = _SolPlan(source, dest, createOwner);
    final bh = await _blockhash();
    final message = compileMessage(payer: owner, blockhash: bh.blockhash, instructions: _solIxs(owner, mint, plan, amount));

    final rent = createOwner == null ? BigInt.zero : BigInt.from(await _sol('getMinimumBalanceForRentExemption', [165]) as int);
    var feeLamports = 5000;
    try {
      final f = (await _sol('getFeeForMessage', [_b64(message), {'commitment': 'confirmed'}]) as Map)['value'];
      if (f is int) feeLamports = f;
    } catch (_) {
      // the base fee per signature is a fixed 5000 lamports
    }
    final fee = BigInt.from(feeLamports);
    final sol = BigInt.from(await _lamports(from));
    if (sol < fee + rent) {
      throw SendError(
        tr('st.lowSol', {'need': fmtUnits(fee + rent, 9, minPlaces: 4), 'rent': rent > BigInt.zero ? tr('st.rentNote') : '', 'have': fmtUnits(sol, 9, minPlaces: 4)}),
      );
    }
    final left = sol - fee - rent;
    final minAccount = BigInt.from(await _sol('getMinimumBalanceForRentExemption', [0]) as int);
    if (left > BigInt.zero && left < minAccount) {
      throw SendError(tr('st.belowMinSol', {'min': fmtUnits(minAccount, 9, minPlaces: 4)}));
    }

    // a dry run of the unsigned transaction: the network says whether it would run
    final sim = (await _sol('simulateTransaction', [
      _b64(wireTransaction(message, Uint8List(64))),
      {'encoding': 'base64', 'sigVerify': false, 'replaceRecentBlockhash': true, 'commitment': 'confirmed'},
    ]) as Map)['value'] as Map;
    if (sim['err'] != null) throw SendError(tr('st.simRefused', {'e': jsonEncode(sim['err'])}));

    return Quote._(
      token: token,
      from: from,
      to: to,
      amount: amount,
      balance: total,
      fee: fee,
      gasBalance: sol,
      rent: rent,
      warnings: warnings,
      plan: plan,
    );
  }

  Future<Outcome> _submitSolana(Quote q, List<String> words) async {
    final plan = q.plan as _SolPlan;
    final owner = solPubkey(q.from);
    final mint = solPubkey(q.token.id);
    final bh = await _blockhash();
    final message = compileMessage(payer: owner, blockhash: bh.blockhash, instructions: _solIxs(owner, mint, plan, q.amount));
    final seed = mnemonicToSeed(words);
    Uint8List? key;
    final SolSigned signed;
    try {
      key = slip10Ed25519(seed, const [44, 501, 0, 0]);
      signed = await signMessage(message, key, expectedPubkey: owner);
    } finally {
      wipe(seed);
      if (key != null) wipe(key);
    }
    final id = signed.id;
    final explorer = 'https://solscan.io/tx/$id';
    // remembered BEFORE it can be on the network: if the app dies from here on, the next start still knows about it
    await _reserve(q, _record(q, id, lastValid: bh.lastValid));
    return _finish(id, explorer, () => _broadcastSolana(signed, bh.lastValid, explorer));
  }

  static final _solTaken = RegExp(r'already (been )?processed|AlreadyProcessed', caseSensitive: false);

  Future<Outcome> _broadcastSolana(SolSigned signed, int lastValid, String explorer) async {
    final id = signed.id;
    final pending = Outcome(Result.pending, id, explorer);
    try {
      await _sol('sendTransaction', [_b64(signed.wire), {'encoding': 'base64', 'preflightCommitment': 'confirmed', 'maxRetries': 5}]);
    } on RpcError catch (e) {
      // the network refuses before broadcasting, unless an earlier try of THIS transaction already went through
      Map? seen;
      try {
        seen = await _solStatus(id, history: true);
      } catch (_) {
        return pending; // cannot tell
      }
      if (seen == null) {
        if (e.ambiguous || [e.message, ...e.messages].any(_solTaken.hasMatch)) return pending; // see the Polygon side
        throw SendError(tr('st.solRefusedSend', {'e': e.message}));
      }
    } on StateError {
      // no node answered: it may still have been delivered to one of them
      Map? seen;
      try {
        seen = await _solStatus(id, history: true);
      } catch (_) {
        // cannot tell
      }
      if (seen == null) return pending;
    }
    final end = DateTime.now().add(maxWait);
    while (true) {
      try {
        var s = await _solStatus(id);
        if (s == null && await _sol('getBlockHeight', [{'commitment': 'confirmed'}]) as int > lastValid) {
          // past its last valid block it can never land; one last look at the history, on every node, in case it did just before
          s = await _solStatus(id, history: true);
          if (s == null) return Outcome(Result.notSent, id, explorer);
        }
        if (s != null && s['confirmationStatus'] == 'finalized') {
          // only finality settles it: a confirmed block can, rarely, still be undone
          return Outcome(s['err'] != null ? Result.reverted : Result.confirmed, id, explorer);
        }
      } catch (_) {
        // a flaky node: ask again until the deadline
      }
      if (!DateTime.now().isBefore(end)) return pending;
      await Future<void>.delayed(pollEvery);
    }
  }

  /// The status of [signature] on ANY node (the most advanced one wins). Null only when EVERY node answered that it does not know
  /// it; throws when none knew it and some could not answer: an unknown is never read as "not there".
  Future<Map?> _solStatus(String signature, {bool history = false}) async {
    final each = await _eachNode(solanaRpcs, 'getSignatureStatuses', [[signature], {'searchTransactionHistory': history}]);
    const rank = {'processed': 1, 'confirmed': 2, 'finalized': 3};
    int level(Map s) => rank[s['confirmationStatus']] ?? 0;
    Map? found;
    for (final a in each) {
      if (!a.ok) continue;
      final s = ((a.v as Map)['value'] as List).first as Map?;
      if (s != null && (found == null || level(s) > level(found))) found = s;
    }
    if (found != null) return found;
    if (each.any((a) => !a.ok)) throw StateError('algum nó não respondeu');
    return null;
  }

  // ---- open sends

  /// Settles a send left open by an earlier run (or an earlier moment): its [Outcome] when that is now certain, null when it is
  /// still unknown. Never guesses: "not sent" needs every node to say unknown AND proof the transaction can no longer land.
  Future<Outcome?> reconcile(PendingSend r) async {
    try {
      return r.net == Net.polygon.name ? await _reconcilePolygon(r) : await _reconcileSolana(r);
    } catch (_) {
      return null; // cannot tell now; it stays open
    }
  }

  Future<Outcome?> _reconcilePolygon(PendingSend r) async {
    final explorer = 'https://polygonscan.com/tx/${r.id}';
    final receipts = await _eachNode(polygonRpcs, 'eth_getTransactionReceipt', [r.id]);
    final mined = [for (final a in receipts) if (a.ok && a.v is Map && (a.v as Map)['status'] != null) a.v as Map];
    if (mined.isNotEmpty) {
      final final_ = await _finalizedBlock();
      for (final v in mined) {
        if (_hb(v['blockNumber']) <= final_) return Outcome(_hb(v['status']) == BigInt.one ? Result.confirmed : Result.reverted, r.id, explorer);
      }
      return null; // mined, not yet final
    }
    if (receipts.any((a) => !a.ok)) return null;
    // no node has a receipt. It can still be on its way (or in a mempool), unless its nonce was taken by another transaction:
    // that must be true on EVERY node at the finalized level, and then it can never be mined, however long a pool keeps listing it
    final nonce = r.nonce;
    if (nonce == null || isStale(r)) return null; // a receipt could have been pruned since: no receipt proves nothing any more
    final used = await _eachNode(polygonRpcs, 'eth_getTransactionCount', [r.from, 'finalized']);
    if (used.every((a) => a.ok && _hb(a.v) > BigInt.from(nonce))) return Outcome(Result.notSent, r.id, explorer);
    return null;
  }

  static BigInt _max(BigInt a, BigInt b) => a > b ? a : b;

  /// Stops an open Polygon send that cannot be settled: signs a zero-value transfer to the wallet ITSELF with the SAME nonce and
  /// twice the fee (a replacement must outbid the original) and waits for that nonce to be used. Then either the original landed
  /// (confirmed) or this one took its place and the original can never land (not sent): both certain. Null while the nonce is free.
  Future<Outcome?> cancelPolygon(PendingSend r, List<String> words) async {
    final nonce = r.nonce;
    if (r.net != Net.polygon.name || nonce == null) throw SendError(tr('st.onlyPolyCancel'));
    if (isStale(r)) throw SendError(tr('st.tooOldCancel'));
    try {
      final settled = await reconcile(r);
      if (settled != null) return settled; // nothing left to cancel
      final now = await _polygonFees();
      final two = BigInt.two;
      final tip = _max(BigInt.tryParse(r.tip ?? '') ?? BigInt.zero, now.tip) * two;
      final maxFee = _max(_max(BigInt.tryParse(r.maxFee ?? '') ?? BigInt.zero, now.maxFee) * two, tip);
      const gas = 21000; // a plain transfer with no data
      final pol = _hb(await _poly('eth_getBalance', [r.from, 'latest']));
      if (pol < maxFee * BigInt.from(gas)) {
        throw SendError(tr('st.lowPolCancel', {'need': fmtUnits(maxFee * BigInt.from(gas), 18, minPlaces: 4), 'have': fmtUnits(pol, 18, minPlaces: 4)}));
      }
      final tx = Eip1559Tx(nonce: nonce, maxPriorityFee: tip, maxFee: maxFee, gasLimit: gas, to: evmAddressBytes(r.from), data: Uint8List(0));
      final seed = mnemonicToSeed(words);
      Uint8List? key;
      final SignedTx signed;
      try {
        key = deriveEvmPrivateKey(seed);
        signed = signTx(tx, key, expectedAddress: r.from);
      } finally {
        wipe(seed);
        if (key != null) wipe(key);
      }
      try {
        await _poly('eth_sendRawTransaction', [signed.rawHex]);
      } on RpcError catch (e) {
        // a nonce refusal means the original (or another) already took it: the check below says which
        if (!e.ambiguous && ![e.message, ...e.messages].any(_nonceTalk.hasMatch)) throw SendError(tr('st.polyRefusedCancel', {'e': e.message}));
      } on StateError {
        // no node answered: it may still have been delivered, the check below looks
      }
      final end = DateTime.now().add(maxWait);
      while (true) {
        final o = await reconcile(r);
        if (o != null) return o;
        if (!DateTime.now().isBefore(end)) return null;
        await Future<void>.delayed(pollEvery);
      }
    } on WalletError {
      throw SendError(tr('st.internal')); // e.message is a developer text (Portuguese): not shown
    } on RpcError catch (e) {
      throw SendError(tr('st.netRefused', {'e': e.message}));
    } on StateError {
      throw SendError(tr('st.noNodePoly'));
    }
  }

  Future<Outcome?> _reconcileSolana(PendingSend r) async {
    final explorer = 'https://solscan.io/tx/${r.id}';
    final s = await _solStatus(r.id, history: true);
    if (s != null) {
      if (s['confirmationStatus'] == 'finalized') return Outcome(s['err'] != null ? Result.reverted : Result.confirmed, r.id, explorer);
      return null; // seen but not final yet
    }
    final last = r.lastValid;
    // "not sent" needs the history to be trusted, and it is only within [staleAfter] of the send (see there)
    if (last != null && !isStale(r) && await _sol('getBlockHeight', [{'commitment': 'confirmed'}]) as int > last) return Outcome(Result.notSent, r.id, explorer);
    return null;
  }

  /// Clears a send that is older than [staleAfter] and still unsettled, on the user's word that they looked it up on an explorer with
  /// the full history (Solscan, Polygonscan). Anything younger has no such way out: the chain settles it, or the cancel does. If the
  /// chain does settle it just now, that outcome is returned instead and nothing is discarded on trust.
  Future<Outcome?> discardStale(PendingSend r) async {
    if (!isStale(r)) throw SendError(tr('st.recentSend'));
    final settled = await reconcile(r);
    await _stored(() => store.remove(r.id));
    return settled;
  }
}
