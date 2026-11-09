// On-chain Bitcoin through Spark: receive = a deposit address plus a claim once the deposit matures; send = a cooperative exit paid
// by the SSP. Everything the screens decide lives here as plain functions, so it is tested without the SDK; the SDK is reached through
// [OnchainApi], which tests replace.
import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'i18n.dart';
import 'limits.dart';
import 'secret_store.dart';
import 'theme.dart';

/// Confirmations before Spark credits a deposit (the SDK may claim earlier when its fee ceiling allows).
const depositConfirmations = 3;

/// A random (v4) UUID, as the SDK wants for `SendPaymentRequest.idempotencyKey`: sending twice with the same key pays once.
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Why an address cannot be paid by this wallet, or null. Spark would refuse another network at send time, after the fee quote and the PIN.
String? networkError(breez.BitcoinNetwork n) =>
    n == breez.BitcoinNetwork.bitcoin ? null : tr('onc.wrongNetwork', {'net': n.name});

/// The send may have gone out although the SDK threw (it can fail after the provider accepted it). Never shown as a plain failure:
/// a retry from here could pay twice.
class UnconfirmedSend implements Exception {
  UnconfirmedSend(this.detail);
  final String detail;
  @override
  String toString() => detail;
}

String get unconfirmedSendMessage => tr('onc.unconfirmed');

/// SDK errors that prove the exit was NOT started (the SDK checks these before it asks the provider for anything). Every other
/// error after the send began may have come after the provider accepted it.
bool sendNeverStarted(Object e) => e is breez.SdkError_InvalidInput || e is breez.SdkError_InsufficientFunds || e is breez.SdkError_InvalidUuid;

/// An on-chain send that was handed to the SDK and has no known outcome. Written BEFORE the send, so an app killed mid-send still
/// knows about it; `key` is the idempotency key, which is also the id of the payment the SDK stores for it.
class OnchainPending {
  const OnchainPending({required this.key, required this.address, required this.sats});
  final String key;
  final String address;
  final int sats;

  Map<String, Object?> toJson() => {'key': key, 'address': address, 'sats': sats};
  factory OnchainPending.fromJson(Map<String, dynamic> j) => OnchainPending(key: j['key'] as String, address: j['address'] as String, sats: j['sats'] as int);
}

/// At most one open on-chain send. A store that cannot be read or written stops a send, it is never skipped; an unreadable record
/// throws, it is not "empty" (empty would let a second send through while the first is unaccounted for).
class OnchainPendingStore {
  OnchainPendingStore(this._store);
  final SecretStore _store;
  static const _name = 'pending.onchain';

  Future<OnchainPending?> open() async {
    final raw = await _store.read(_name);
    if (raw == null || raw.isEmpty) return null;
    return OnchainPending.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Records [p] before the send. Throws when a DIFFERENT send is still open.
  Future<void> reserve(OnchainPending p) async {
    final cur = await open();
    if (cur != null && cur.key != p.key) throw StateError('há outro envio on-chain em aberto');
    await _store.write(_name, jsonEncode(p.toJson()));
  }

  Future<void> clear() => _store.delete(_name);
}

/// The open on-chain send after asking the SDK about it, or null when there is none. A stored payment under the key means the SDK
/// took the send: the record is cleared and null returned. Any error from the lookup leaves the record open (it may be "not found",
/// it may be a sync problem: either way nothing is assumed).
Future<OnchainPending?> openOnchainSend(OnchainPendingStore store, breez.BreezSdk sdk) async {
  final rec = await store.open();
  if (rec == null) return null;
  try {
    await sdk.getPayment(request: breez.GetPaymentRequest(paymentId: rec.key));
  } catch (_) {
    return rec;
  }
  await store.clear();
  return null;
}

/// `bitcoin:` URI for a QR: lowercase address, no amount (the sender chooses it).
String bitcoinUri(String address) => 'bitcoin:${address.trim()}';

/// Total fee of one confirmation speed in a send quote: our fee plus the L1 broadcast fee, both paid by the sender.
int onchainFeeSats(breez.SendOnchainFeeQuote q, breez.OnchainConfirmationSpeed s) {
  final speed = switch (s) {
    breez.OnchainConfirmationSpeed.fast => q.speedFast,
    breez.OnchainConfirmationSpeed.medium => q.speedMedium,
    breez.OnchainConfirmationSpeed.slow => q.speedSlow,
  };
  return (speed.userFeeSat + speed.l1BroadcastFeeSat).toInt();
}

/// True when the provider will no longer honour [q]. An estimate (`expiresAt` 0) never expires but is only an upper bound.
bool onchainQuoteExpired(breez.SendOnchainFeeQuote q, {DateTime? now, int marginSecs = 30}) {
  if (q.expiresAt == BigInt.zero) return false;
  final nowSecs = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  return nowSecs + marginSecs >= q.expiresAt.toInt();
}

String speedLabel(breez.OnchainConfirmationSpeed s) => switch (s) {
  breez.OnchainConfirmationSpeed.fast => tr('onc.fast'),
  breez.OnchainConfirmationSpeed.medium => tr('onc.medium'),
  breez.OnchainConfirmationSpeed.slow => tr('onc.slow'),
};

/// What the user should read for one unclaimed deposit.
String depositStatus(breez.DepositInfo d) {
  final e = d.claimError;
  if (e is breez.DepositClaimError_MaxDepositClaimFeeExceeded) {
    return tr('onc.feeAboveLimit', {'n': e.requiredFeeSats});
  }
  if (e is breez.DepositClaimError_DepositTooSmall) return tr('onc.tooSmall');
  if (e is breez.DepositClaimError_MissingUtxo) return tr('onc.noTx');
  if (e is breez.DepositClaimError_Generic) return tr('onc.cannotClaim', {'e': e.message});
  if (!d.isMature) return tr('onc.waiting', {'n': depositConfirmations});
  return tr('onc.confirmed');
}

/// The fee (sats) the SDK says a refused claim needs, or null when the deposit did not fail on the fee ceiling.
int? depositFeeNeeded(breez.DepositInfo d) {
  final e = d.claimError;
  return e is breez.DepositClaimError_MaxDepositClaimFeeExceeded ? e.requiredFeeSats.toInt() : null;
}

/// A deposit that failed for a reason a later retry can fix (fee market), as opposed to waiting for confirmations.
bool depositCanRetry(breez.DepositInfo d) => d.claimError != null && d.claimError is! breez.DepositClaimError_DepositTooSmall;

class OnchainApi {
  const OnchainApi({required this.address, required this.deposits, required this.claim, required this.receivedDeposits});

  /// The wallet's (static, reusable) deposit address.
  final Future<String> Function() address;
  final Future<List<breez.DepositInfo>> Function() deposits;

  /// Claims one deposit; throws when the SDK refuses. [maxFeeSats] raises the fee ceiling for this one claim (the user agreed to it).
  final Future<void> Function(breez.DepositInfo, {int? maxFeeSats}) claim;

  /// Completed on-chain receive payments (credited deposits): id -> sats.
  final Future<Map<String, int>> Function() receivedDeposits;

  factory OnchainApi.fromSdk(breez.BreezSdk sdk) => OnchainApi(
    address: () async =>
        (await sdk.receivePayment(request: const breez.ReceivePaymentRequest(paymentMethod: breez.ReceivePaymentMethod.bitcoinAddress()))).paymentRequest,
    deposits: () async => (await sdk.listUnclaimedDeposits(request: const breez.ListUnclaimedDepositsRequest())).deposits,
    claim: (d, {int? maxFeeSats}) async {
      await sdk.claimDeposit(
        request: breez.ClaimDepositRequest(
          txid: d.txid,
          vout: d.vout,
          maxFee: maxFeeSats == null ? null : breez.MaxFee.fixed(amount: BigInt.from(maxFeeSats)),
        ),
      );
    },
    receivedDeposits: () async => {
      for (final p in (await sdk.listPayments(
        request: const breez.ListPaymentsRequest(typeFilter: [breez.PaymentType.receive], limit: 20),
      )).payments.where((p) => p.method == breez.PaymentMethod.deposit && p.status == breez.PaymentStatus.completed))
        p.id: p.amount.toInt(),
    },
  );
}

/// Receive on-chain: the address as a QR, the deposits still waiting, and a pop with the sats when a new deposit is credited.
class OnchainReceiveView extends StatefulWidget {
  const OnchainReceiveView({super.key, required this.api, required this.onReceived, this.pollEvery = const Duration(seconds: 5)});
  final OnchainApi api;
  final void Function(int sats) onReceived;
  final Duration pollEvery;
  @override
  State<OnchainReceiveView> createState() => _OnchainReceiveViewState();
}

class _OnchainReceiveViewState extends State<OnchainReceiveView> {
  String? _address;
  String? _error;
  bool _copied = false;
  List<breez.DepositInfo> _deposits = const [];
  Set<String> _seen = {};
  bool _seenReady = false;
  Timer? _poll;
  bool _checking = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _seen = (await widget.api.receivedDeposits()).keys.toSet();
      _seenReady = true;
      final a = await widget.api.address();
      if (!mounted) return;
      setState(() => _address = a);
      _poll = Timer.periodic(widget.pollEvery, (_) => _check());
      await _check();
    } catch (e) {
      if (mounted) setState(() => _error = tr('onc.addressErr', {'e': e}));
    }
  }

  Future<void> _check() async {
    if (_checking || !_seenReady) return;
    _checking = true;
    try {
      final d = await widget.api.deposits();
      if (mounted) setState(() => _deposits = d);
      final now = await widget.api.receivedDeposits();
      final fresh = now.entries.where((e) => !_seen.contains(e.key));
      if (fresh.isNotEmpty && mounted) {
        _poll?.cancel();
        widget.onReceived(fresh.first.value);
      }
    } catch (_) {
      // transient sync error: the next tick retries
    } finally {
      _checking = false;
    }
  }

  Future<void> _retry(breez.DepositInfo d) async {
    if (_retrying) return; // a double tap would open two fee dialogs and send two claims for the same UTXO
    _retrying = true;
    try {
      final fee = depositFeeNeeded(d);
      if (fee != null && !await _confirmFee(d, fee)) return;
      try {
        await widget.api.claim(d, maxFeeSats: fee);
        if (mounted) setState(() => _error = null);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
      await _check();
    } finally {
      _retrying = false;
    }
  }

  /// A claim that the fee ceiling refused only goes through with a higher ceiling, which is the user's money: ask first.
  Future<bool> _confirmFee(breez.DepositInfo d, int fee) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('onc.payFeeTitle')),
          content: Text(tr('onc.payFeeBody', {'amount': fmtSats(d.amountSats.toInt()), 'fee': fmtSats(fee)})),
          actions: [
            TextButton(key: const Key('claim-fee-cancel'), onPressed: () => Navigator.pop(c, false), child: Text(tr('common.cancel'))),
            TextButton(key: const Key('claim-fee-confirm'), onPressed: () => Navigator.pop(c, true), child: Text(tr('onc.payAndClaim'))),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final a = _address;
    if (a == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: C.warn, fontSize: 13))
            : const Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.primaryLight)),
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: QrImageView(data: bitcoinUri(a), size: 200, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 12),
        SelectableText(a, textAlign: TextAlign.center, style: const TextStyle(fontFamily: monoFamily, fontSize: 12, color: C.primaryLight)),
        const SizedBox(height: 12),
        GradientButton(
          label: _copied ? tr('recv.copied') : tr('onc.copyAddress'),
          icon: Icons.copy,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: a));
            setState(() => _copied = true);
          },
        ),
        const SizedBox(height: 10),
        Text(
          tr('onc.note', {'n': depositConfirmations, 'min': minPaymentSats}),
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.muted, fontSize: 12),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: C.warn, fontSize: 13))),
        for (final d in _deposits)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RowKV(tr('onc.deposit'), '${fmtSats(d.amountSats.toInt())} sats', strong: true),
                  Text(depositStatus(d), key: const Key('deposit-status'), style: const TextStyle(color: C.muted, fontSize: 12)),
                  if (depositCanRetry(d))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _retry(d),
                        child: Text(depositFeeNeeded(d) == null ? tr('main.retry') : tr('onc.claimPaying', {'fee': fmtSats(depositFeeNeeded(d)!)})),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
