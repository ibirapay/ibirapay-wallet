import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/backup_crypto.dart' show Argon2Params;
import 'package:wallet/pending_sends.dart';
import 'package:wallet/pin.dart';
import 'package:wallet/secret_store.dart';
import 'package:wallet/wallet.dart' show walletWordsKey;
import 'package:wallet/wipe.dart';

const _tiny = Argon2Params(memory: 8, iterations: 1);

PendingSend _send(String id, {required Duration age}) => PendingSend(
  id: id,
  net: 'polygon',
  symbol: 'USDT',
  amount: '1500000',
  to: '0xto',
  from: '0xfrom',
  createdMs: DateTime.now().millisecondsSinceEpoch - age.inMilliseconds,
  nonce: 1,
);

void main() {
  late Directory dir;
  late Directory backups;
  late SecretStore store;
  late PinStore pins;
  late MemoryPendingStore pending;
  late List<String> log;

  WalletOps ops({Future<void> Function()? closeSpark, Future<void> Function()? deleteSpark, PendingStore? pendingStore, Future<void> Function(String)? onDelete}) {
    return WalletOps(
      store: store,
      pins: pins,
      pending: pendingStore ?? pending,
      closeSpark: closeSpark ?? () async => log.add('close'),
      deleteSparkData: deleteSpark ?? () async => log.add('delete-spark'),
    );
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('wipe_test');
    backups = Directory.systemTemp.createTempSync('wipe_backups');
    File('${backups.path}/ibirapay-wallet-1.ibirapay').writeAsStringSync('encrypted backup');
    store = SecretStore.dir(dir);
    pins = PinStore(store, params: _tiny);
    pending = MemoryPendingStore();
    log = [];
    await store.write(walletWordsKey, 'word ' * 11 + 'last');
    await pins.set('4821');
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
    backups.deleteSync(recursive: true);
  });

  test('a wipe closes Spark, deletes its data, forgets open sends, deletes the words and the PIN, in that order', () async {
    pending.items.add(_send('old', age: const Duration(days: 2)));
    final order = <String>[];
    final o = WalletOps(
      store: store,
      pins: pins,
      pending: pending,
      closeSpark: () async => order.add('close'),
      deleteSparkData: () async {
        order.add('delete-spark');
        expect(await store.read(walletWordsKey), isNotNull); // the words are still there: this is not the commit point yet
      },
    );
    await o.wipe(acknowledgedOldSends: true);
    expect(order, ['close', 'delete-spark']);
    expect(await store.read(walletWordsKey), isNull);
    expect(await pins.has(), isFalse);
    expect(pending.items, isEmpty);
  });

  test('backup files in Documents are never touched', () async {
    await ops().wipe();
    expect(File('${backups.path}/ibirapay-wallet-1.ibirapay').readAsStringSync(), 'encrypted backup');
  });

  test('a send open for less than an hour refuses the wipe and changes NOTHING', () async {
    pending.items.add(_send('recent', age: const Duration(minutes: 10)));
    await expectLater(ops().wipe(), throwsA(isA<WipeRefused>().having((e) => e.message, 'message', contains('em aberto'))));
    expect(log, isEmpty);
    expect(await store.read(walletWordsKey), isNotNull);
    expect(await pins.has(), isTrue);
    expect(pending.items, hasLength(1));
  });

  test('an unsettled send OLDER than an hour still refuses the wipe (a stuck Polygon transaction can be mined at any time) and changes nothing', () async {
    pending.items.add(_send('stale', age: const Duration(hours: 3)));
    await expectLater(ops().wipe(), throwsA(isA<WipeRefused>().having((e) => e.message, 'message', contains('antigos'))));
    expect(log, isEmpty);
    expect(await store.read(walletWordsKey), isNotNull);
    expect(pending.items, hasLength(1));
  });

  test('only with the acknowledgement (the lock screen) does an old send not stop it; a RECENT one stops it even then', () async {
    pending.items.add(_send('stale', age: const Duration(hours: 3)));
    await ops().wipe(acknowledgedOldSends: true);
    expect(await store.read(walletWordsKey), isNull);
    expect(pending.items, isEmpty);
    await store.write(walletWordsKey, 'again');
    pending.items.add(_send('recent', age: const Duration(minutes: 5)));
    await expectLater(ops().wipe(acknowledgedOldSends: true), throwsA(isA<WipeRefused>()));
    expect(await store.read(walletWordsKey), isNotNull);
  });

  test('a crash at each step leaves either the whole wallet (run it again) or no wallet; running it again finishes', () async {
    for (final failAt in ['close', 'delete-spark']) {
      final o = ops(
        closeSpark: () async {
          if (failAt == 'close') throw StateError('boom');
        },
        deleteSpark: () async {
          if (failAt == 'delete-spark') throw StateError('boom');
        },
      );
      await expectLater(o.wipe(), throwsStateError);
      // before the words went: the wallet is intact and still has its PIN
      expect(await store.read(walletWordsKey), isNotNull, reason: failAt);
      expect(await pins.has(), isTrue, reason: failAt);
      await ops().wipe(); // the retry
      expect(await store.read(walletWordsKey), isNull, reason: failAt);
      expect(await pins.has(), isFalse, reason: failAt);
      await store.write(walletWordsKey, 'again');
      await pins.set('4821');
    }
  });

  test('a cut between deleting the words and the PIN leaves a stale PIN that start-up clears, and nothing else', () async {
    await store.delete(walletWordsKey); // the commit point happened, the PIN step did not
    pending.items.add(_send('x', age: const Duration(minutes: 1)));
    expect(await pins.has(), isTrue);
    await ops().clearLeftovers();
    expect(await pins.has(), isFalse);
    expect(pending.items, isEmpty);
  });

  test('start-up leftovers are only cleared when there is NO wallet', () async {
    pending.items.add(_send('x', age: const Duration(minutes: 1)));
    await ops().clearLeftovers();
    expect(await pins.has(), isTrue);
    expect(pending.items, hasLength(1));
  });

  test('an unreadable open-send record stops the wipe before anything is deleted', () async {
    final broken = MemoryPendingStore()..failReads = true;
    await expectLater(ops(pendingStore: broken).wipe(), throwsStateError);
    expect(log, isEmpty);
    expect(await store.read(walletWordsKey), isNotNull);
  });

  test('if deleting the words fails, the PIN is still there: a half wipe never leaves a wallet WITHOUT its PIN', () async {
    final flaky = _FlakyStore(dir);
    final p = PinStore(flaky, params: _tiny);
    await flaky.write(walletWordsKey, 'a b c');
    await p.set('4821');
    final o = WalletOps(store: flaky, pins: p, pending: pending, closeSpark: () async {}, deleteSparkData: () async {});
    flaky.failOn = walletWordsKey;
    await expectLater(o.wipe(), throwsStateError);
    expect(await flaky.read(walletWordsKey), isNotNull);
    expect(await p.has(), isTrue);
    expect(await p.verify('4821'), isA<PinOk>());
  });

  test('if deleting the words fails, the open-send records are still there: a wallet that stays never forgets what it owes', () async {
    final flaky = _FlakyStore(dir);
    final p = PinStore(flaky, params: _tiny);
    await flaky.write(walletWordsKey, 'a b c');
    await p.set('4821');
    pending.items.add(_send('old', age: const Duration(days: 2)));
    final o = WalletOps(store: flaky, pins: p, pending: pending, closeSpark: () async {}, deleteSparkData: () async {});
    flaky.failOn = walletWordsKey;
    await expectLater(o.wipe(acknowledgedOldSends: true), throwsStateError);
    expect(pending.items.map((e) => e.id), ['old']);
  });
}

/// A store whose delete of one name fails, to cut a wipe between two steps.
class _FlakyStore extends SecretStore {
  _FlakyStore(super.dir) : super.dir();
  String? failOn;

  @override
  Future<void> delete(String name) async {
    if (name == failOn) throw StateError('disk error');
    return super.delete(name);
  }
}
