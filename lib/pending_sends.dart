// Stablecoin sends that were signed and may be on the network, remembered across an app restart. Without this an app killed right
// after a broadcast forgets the payment and lets the user make it a second time. Only what a block explorer shows is kept, no keys.
import 'dart:convert';

import 'secret_store.dart';

class PendingSend {
  const PendingSend({
    required this.id,
    required this.net,
    required this.symbol,
    required this.amount,
    required this.to,
    required this.from,
    required this.createdMs,
    this.nonce,
    this.lastValid,
    this.tip,
    this.maxFee,
  });

  /// The transaction hash (Polygon) or signature (Solana).
  final String id;

  /// `Net.name`: 'polygon' or 'solana'.
  final String net;
  final String symbol;

  /// Smallest units, as text so it round-trips through JSON exactly.
  final String amount;
  final String to;
  final String from;
  final int createdMs;

  /// Polygon: the nonce this transaction took. Once the account's nonce is past it and the hash is unknown, it can never be mined.
  final int? nonce;

  /// Solana: the last block height at which this transaction could still be included.
  final int? lastValid;

  /// Polygon: the fees it was signed with (wei, as text), so a cancelling transaction can outbid it.
  final String? tip;
  final String? maxFee;

  Map<String, Object?> toJson() => {
    'id': id,
    'net': net,
    'symbol': symbol,
    'amount': amount,
    'to': to,
    'from': from,
    'createdMs': createdMs,
    if (nonce != null) 'nonce': nonce,
    if (lastValid != null) 'lastValid': lastValid,
    if (tip != null) 'tip': tip,
    if (maxFee != null) 'maxFee': maxFee,
  };

  factory PendingSend.fromJson(Map<String, dynamic> j) => PendingSend(
    id: j['id'] as String,
    net: j['net'] as String,
    symbol: j['symbol'] as String,
    amount: j['amount'] as String,
    to: j['to'] as String,
    from: j['from'] as String,
    createdMs: j['createdMs'] as int,
    nonce: j['nonce'] as int?,
    lastValid: j['lastValid'] as int?,
    tip: j['tip'] as String?,
    maxFee: j['maxFee'] as String?,
  );
}

/// Where the open sends live. A store that cannot be read or written must stop a send, never be skipped.
abstract interface class PendingStore {
  Future<List<PendingSend>> all();
  Future<void> put(PendingSend s);
  Future<void> remove(String id);

  /// Saves [s] only if no send of network [net] is open, as ONE step: two sends racing for the same network cannot both get in.
  Future<bool> putIfNoneOpen(String net, PendingSend s);
}

/// The app's store: one JSON list in the secret store (Keystore on Android). A list that cannot be parsed throws: it is not
/// treated as empty, because "empty" would let a send through while an earlier one is unaccounted for.
///
/// Every operation, reads included, runs one at a time under one lock shared by all instances: a background check removing an old
/// record must not overwrite a newer one it never saw, and a read must not catch a file half written.
class SecretPendingStore implements PendingStore {
  SecretPendingStore(this._store);
  final SecretStore _store;
  static const _key = 'pending.sends';

  static Future<void> _tail = Future<void>.value();
  static Future<T> _locked<T>(Future<T> Function() f) {
    final run = _tail.then((_) => f());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<List<PendingSend>> _read() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) return const [];
    return [for (final j in jsonDecode(raw) as List) PendingSend.fromJson(j as Map<String, dynamic>)];
  }

  Future<void> _write(List<PendingSend> l) => _store.write(_key, jsonEncode([for (final s in l) s.toJson()]));

  @override
  Future<List<PendingSend>> all() => _locked(_read);

  @override
  Future<void> put(PendingSend s) => _locked(() async => _write([...(await _read()).where((o) => o.id != s.id), s]));

  @override
  Future<void> remove(String id) => _locked(() async => _write([...(await _read()).where((o) => o.id != id)]));

  @override
  Future<bool> putIfNoneOpen(String net, PendingSend s) => _locked(() async {
    final current = await _read();
    if (current.any((o) => o.net == net)) return false;
    await _write([...current, s]);
    return true;
  });
}

/// Tests, and nothing else: it forgets on restart.
class MemoryPendingStore implements PendingStore {
  final items = <PendingSend>[];

  /// Tests make it fail on demand.
  bool failWrites = false;
  bool failReads = false;

  @override
  Future<List<PendingSend>> all() async {
    if (failReads) throw StateError('read failed');
    return List.of(items);
  }

  @override
  Future<void> put(PendingSend s) async {
    if (failWrites) throw StateError('write failed');
    items
      ..removeWhere((o) => o.id == s.id)
      ..add(s);
  }

  @override
  Future<void> remove(String id) async => items.removeWhere((o) => o.id == id);

  @override
  Future<bool> putIfNoneOpen(String net, PendingSend s) async {
    if (failWrites) throw StateError('write failed');
    if (items.any((o) => o.net == net)) return false;
    items.add(s);
    return true;
  }
}
