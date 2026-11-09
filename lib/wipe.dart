// Deleting the wallet from this device. The only thing that brings it back is the 12 words, so this is the one irreversible action in the app.
// The order is the safety. Everything that is still a wallet's responsibility (Spark, the open sends, the PIN) stays until the words go:
// a failure before that leaves a wallet that still works AND still remembers what it owes (run the wipe again). The words are the commit
// point; what follows is leftovers that start-up clears when it finds no wallet.
import 'i18n.dart';
import 'pending_sends.dart';
import 'pin.dart';
import 'secret_store.dart';
import 'stable_send.dart' show isStale;
import 'wallet.dart' show walletWordsKey;

/// The wipe was not done, with the reason for the user. Nothing was changed.
class WipeRefused implements Exception {
  WipeRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

class WalletOps {
  WalletOps({required this.store, required this.pins, required this.pending, required this.closeSpark, required this.deleteSparkData});
  final SecretStore store;
  final PinStore pins;
  final PendingStore pending;

  /// Disconnects the Spark SDK (its data directory cannot be removed while it is open).
  final Future<void> Function() closeSpark;
  final Future<void> Function() deleteSparkData;

  /// A USDT/USDC send from the last hour that is not settled: it may still land, and without this wallet nothing could cancel or
  /// follow it. Older unsettled ones are not held against the wipe (they need an explorer anyway).
  Future<PendingSend?> recentOpenSend() async {
    for (final r in await pending.all()) {
      if (!isStale(r)) return r;
    }
    return null;
  }

  /// Every send that is not settled, recent or not.
  Future<List<PendingSend>> openSends() => pending.all();

  /// Deletes the wallet. A send open for under an hour always refuses it. Older unsettled sends refuse it too, unless
  /// [acknowledgedOldSends]: that is only for the lock screen ("Esqueci o PIN"), where the app cannot be opened to settle or discard them,
  /// and only after the user was shown them and agreed to check them on an explorer before sending again.
  Future<void> wipe({bool acknowledgedOldSends = false}) async {
    if (await recentOpenSend() != null) {
      throw WipeRefused(tr('del.openSend'));
    }
    if (!acknowledgedOldSends && (await openSends()).isNotEmpty) {
      throw WipeRefused(tr('del.oldSends'));
    }
    await closeSpark();
    await deleteSparkData();
    await store.delete(walletWordsKey); // the commit point: from here there is no wallet on this device
    for (final r in await pending.all()) {
      await pending.remove(r.id);
    }
    await pins.clear();
  }

  /// At start-up with no wallet: a PIN or open-send records left by a wipe that was cut short belong to nothing.
  Future<void> clearLeftovers() async {
    if (await store.read(walletWordsKey) != null) return;
    await pins.clear();
    for (final r in await pending.all()) {
      await pending.remove(r.id);
    }
  }
}
