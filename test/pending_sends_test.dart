import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/pending_sends.dart';
import 'package:wallet/secret_store.dart';

PendingSend _s(String id, {int? nonce, int? lastValid}) =>
    PendingSend(id: id, net: 'polygon', symbol: 'USDT', amount: '1500000', to: '0xto', from: '0xfrom', createdMs: 42, nonce: nonce, lastValid: lastValid);

/// A write that empties the file first and finishes later, like a write that is not atomic.
class _SlowStore extends SecretStore {
  _SlowStore(super.dir) : super.dir();
  @override
  Future<void> write(String name, String value) async {
    await super.write(name, '');
    await Future<void>.delayed(const Duration(milliseconds: 4));
    await super.write(name, value);
  }
}

void main() {
  late Directory dir;
  late SecretPendingStore store;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('pending_test');
    store = SecretPendingStore(SecretStore.dir(dir));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('what was written comes back exactly, across a new store object (a restart)', () async {
    await store.put(_s('a', nonce: 7));
    await store.put(_s('b', lastValid: 99));
    final again = SecretPendingStore(SecretStore.dir(dir));
    final all = await again.all();
    expect(all.map((e) => e.id), ['a', 'b']);
    expect(all.first.nonce, 7);
    expect(all.first.lastValid, isNull);
    expect(all.last.lastValid, 99);
    expect([all.first.amount, all.first.to, all.first.from, all.first.createdMs], ['1500000', '0xto', '0xfrom', 42]);
  });

  test('putting the same id twice keeps one record; remove drops only that one; empty is empty', () async {
    expect(await store.all(), isEmpty);
    await store.put(_s('a'));
    await store.put(_s('a', nonce: 1));
    await store.put(_s('b'));
    expect((await store.all()).map((e) => e.id), ['a', 'b']);
    expect((await store.all()).first.nonce, 1);
    await store.remove('a');
    expect((await store.all()).map((e) => e.id), ['b']);
    await store.remove('missing');
    expect(await store.all(), hasLength(1));
  });

  test('an unreadable record is an error, not an empty list (an empty list would let a send through)', () async {
    File('${dir.path}/pending.sends').writeAsStringSync('{not json');
    await expectLater(store.all(), throwsA(isA<FormatException>()));
    File('${dir.path}/pending.sends').writeAsStringSync('[{"id": 1}]');
    await expectLater(store.all(), throwsA(isA<TypeError>()));
  });

  PendingSend net(String id, String n) => PendingSend(id: id, net: n, symbol: 'USDT', amount: '1', to: 't', from: 'f', createdMs: 0);

  test('many operations at once never lose a record (no read-modify-write races)', () async {
    await Future.wait([for (var i = 0; i < 40; i++) store.put(_s('id$i'))]);
    expect((await store.all()).map((e) => e.id).toSet(), {for (var i = 0; i < 40; i++) 'id$i'});
    // a stale background removal beside new puts: only the removed ids are gone
    await Future.wait([
      for (var i = 0; i < 40; i += 2) store.remove('id$i'),
      for (var i = 40; i < 60; i++) store.put(_s('id$i')),
    ]);
    expect((await store.all()).map((e) => e.id).toSet(), {for (var i = 1; i < 40; i += 2) 'id$i', for (var i = 40; i < 60; i++) 'id$i'});
  });

  test('a read never catches a write half done: once there is a record, no read sees an empty list', () async {
    // a store whose write is slow and truncates first, so a read that is not queued behind it WOULD see an empty file
    final slow = SecretPendingStore(_SlowStore(dir));
    await slow.put(_s('first'));
    final reads = <int>[];
    await Future.wait([
      for (var i = 0; i < 6; i++) slow.put(_s('w$i')),
      for (var i = 0; i < 12; i++) Future<void>.delayed(Duration(milliseconds: i * 2)).then((_) => slow.all()).then((l) => reads.add(l.length)),
    ]);
    expect(reads, hasLength(12));
    expect(reads.every((n) => n >= 1), isTrue, reason: '$reads');
  });

  test('putIfNoneOpen: only one of many racing for a network gets in; other networks are free', () async {
    final results = await Future.wait([for (var i = 0; i < 12; i++) store.putIfNoneOpen('polygon', net('p$i', 'polygon'))]);
    expect(results.where((r) => r), hasLength(1));
    expect(await store.putIfNoneOpen('solana', net('s1', 'solana')), isTrue);
    expect(await store.putIfNoneOpen('solana', net('s2', 'solana')), isFalse);
    expect((await store.all()).map((e) => e.net).toList()..sort(), ['polygon', 'solana']);
    await store.remove((await store.all()).firstWhere((e) => e.net == 'polygon').id);
    expect(await store.putIfNoneOpen('polygon', net('p-again', 'polygon')), isTrue);
  });

  test('the in-memory store used by tests has the same reservation rule', () async {
    final m = MemoryPendingStore();
    expect(await m.putIfNoneOpen('polygon', net('a', 'polygon')), isTrue);
    expect(await m.putIfNoneOpen('polygon', net('b', 'polygon')), isFalse);
    expect(await m.putIfNoneOpen('solana', net('c', 'solana')), isTrue);
  });
}
