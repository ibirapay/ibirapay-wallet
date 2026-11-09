// Send / redeem flow as one bottom sheet: input -> (amount) -> confirm -> processing -> result.
// Every outgoing payment is confirmed with its amount and fee, and capped while Spark is in its mainnet firetest.
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'i18n.dart';
import 'scan_page.dart';
export 'scan_page.dart' show ScanPage;

import 'limits.dart';
import 'onchain.dart';
import 'theme.dart';

String _clean(String s) => s.trim().replaceFirst(RegExp(r'^lightning:', caseSensitive: false), '');

String _short(String s) => s.length <= 28 ? s : '${s.substring(0, 14)}...${s.substring(s.length - 10)}';

enum _Step { input, amount, confirm, busy, done, pending }

/// Opens the send sheet the only way it may be opened: not dismissible (no swipe, no tap outside), and the sheet itself blocks Back
/// while a send runs. Walked away from mid-send, the outcome would be hidden and a second payment invited.
Future<bool?> showSendSheet(
  BuildContext context, {
  required breez.BreezSdk sdk,
  required OnchainPendingStore pending,
  String? initial,
  required Future<bool> Function() confirmPin,
}) => showAppSheet<bool>(
  context,
  (_) => SendSheet(sdk: sdk, pending: pending, initial: initial, confirmPin: confirmPin),
  dismissible: false,
);

class SendSheet extends StatefulWidget {
  const SendSheet({super.key, required this.sdk, required this.pending, this.initial, required this.confirmPin});
  final breez.BreezSdk sdk;

  /// Where an on-chain send is written down before it is made, so a kill or a walk-away cannot lead to a second payment.
  final OnchainPendingStore pending;

  /// Asks the PIN before anything is paid; false (wrong, cancelled) leaves the confirm step as it is.
  final Future<bool> Function() confirmPin;

  /// A code already scanned on the home screen: the sheet opens straight on its confirm step.
  final String? initial;
  @override
  State<SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<SendSheet> {
  final _input = TextEditingController();
  final _amount = TextEditingController();
  _Step _step = _Step.input;
  String? _error;
  bool _working = false;

  // what the confirm step shows and runs
  String _verb = 'enviar';
  BigInt _sats = BigInt.zero;
  BigInt _fee = BigInt.zero;
  String _dest = '';
  Future<breez.Payment?> Function()? _exec;
  // on-chain send: the quote and the speed the user picked (the fee shown follows the speed)
  breez.SendOnchainFeeQuote? _quote;
  breez.OnchainConfirmationSpeed _speed = breez.OnchainConfirmationSpeed.medium;
  // what the amount step runs once it has a value
  Future<void> Function(int sats)? _withAmount;
  String _amountFor = '';

  bool _ok = false;
  bool _unconfirmed = false;
  String _result = '';
  String _detail = '';
  // the on-chain send being confirmed, kept so an expired quote can be re-asked in place
  String _onchainAddress = '';
  int _onchainSats = 0;
  String _onchainKey = '';
  /// True when this sheet retries a record an EARLIER attempt left open: that attempt may have gone out, so no error of this run can clear it.
  bool _resumed = false;
  // an earlier on-chain send with no known outcome, shown on the pending step
  OnchainPending? _open;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _input.text = i;
      WidgetsBinding.instance.addPostFrameCallback((_) => _continue());
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _input.text = d!.text!.trim());
  }

  Future<void> _scan() async {
    final v = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (v != null && mounted) {
      setState(() => _input.text = v.trim());
      _continue();
    }
  }

  Future<void> _continue() async {
    final text = _clean(_input.text);
    if (text.isEmpty) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final parsed = await widget.sdk.parse(input: text);
      if (parsed is breez.InputType_Bolt11Invoice) {
        await _bolt11(parsed.field0, text);
      } else if (parsed is breez.InputType_LnurlWithdraw) {
        _prepareWithdraw(parsed.field0);
      } else if (parsed is breez.InputType_LnurlPay) {
        _askAmount(parsed.field0.address ?? parsed.field0.domain, (sats) => _prepareLnurlPay(parsed.field0, sats));
      } else if (parsed is breez.InputType_LightningAddress) {
        final d = parsed.field0;
        _askAmount(d.address, (sats) => _prepareLnurlPay(d.payRequest, sats));
      } else if (parsed is breez.InputType_BitcoinAddress) {
        final bad = networkError(parsed.field0.network);
        if (bad != null) throw bad;
        final address = parsed.field0.address;
        if (!await _onchainFree()) return;
        _askAmount(_short(address), (sats) => _prepareOnchain(address, sats));
      } else if (parsed is breez.InputType_Bip21 &&
          parsed.field0.paymentMethods.any((m) => m is breez.InputType_BitcoinAddress || m is breez.InputType_Bolt11Invoice)) {
        final d = parsed.field0;
        // A unified QR carries a Lightning invoice next to the on-chain address: Lightning is cheaper and faster, so it goes first.
        final ln = d.paymentMethods.whereType<breez.InputType_Bolt11Invoice>().firstOrNull;
        if (ln != null) {
          await _bolt11(ln.field0, ln.field0.invoice.bolt11);
        } else {
          final details = d.paymentMethods.whereType<breez.InputType_BitcoinAddress>().first.field0;
          final bad = networkError(details.network);
          if (bad != null) throw bad;
          final address = details.address;
          final amount = d.amountSat?.toInt();
          if (!await _onchainFree()) return;
          if (amount == null) {
            _askAmount(_short(address), (sats) => _prepareOnchain(address, sats));
          } else {
            await _prepareOnchain(address, amount);
          }
        }
      } else {
        setState(() => _error = tr('send.unsupported'));
      }
    } catch (e) {
      setState(() => _error = tr('err.generic', {'e': e}));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// True when a new on-chain send may start. An earlier one with no known outcome comes first: the SDK is asked about it, and if it
  /// is still unaccounted for the sheet shows it instead of letting a second payment through.
  Future<bool> _onchainFree() async {
    final before = await widget.pending.open();
    if (before == null) return true;
    final still = await openOnchainSend(widget.pending, widget.sdk);
    if (still == null) {
      _error = tr('send.prevInHistoryAmt', {'n': fmtSats(before.sats)});
      return false;
    }
    _open = still;
    if (mounted) setState(() => _step = _Step.pending);
    return false;
  }

  Future<void> _recheck() async {
    setState(() => _working = true);
    try {
      final still = await openOnchainSend(widget.pending, widget.sdk);
      if (!mounted) return;
      if (still == null) {
        setState(() {
          _open = null;
          _step = _Step.input;
          _error = tr('send.prevInHistory');
        });
      } else {
        setState(() => _error = tr('send.noRecord'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = tr('err.generic', {'e': e}));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Sends the same payment again under the SAME key: if the first try went out, the SDK hands back that payment instead of paying twice.
  Future<void> _resume() async {
    final r = _open;
    if (r == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    _resumed = true;
    try {
      await _prepareOnchain(r.address, r.sats, key: r.key);
    } catch (e) {
      if (mounted) setState(() => _error = tr('err.generic', {'e': e}));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _discard() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('send.discardTitle')),
        content: Text(tr('send.discardBody')),
        actions: [
          TextButton(key: const Key('discard-no'), onPressed: () => Navigator.pop(c, false), child: Text(tr('scan.back'))),
          TextButton(key: const Key('discard-yes'), onPressed: () => Navigator.pop(c, true), child: Text(tr('common.discard'))),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.pending.clear();
      if (mounted) {
        setState(() {
          _open = null;
          _step = _Step.input;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = tr('err.generic', {'e': e}));
    }
  }

  Future<void> _bolt11(breez.Bolt11InvoiceDetails d, String invoice) async {
    if (d.amountMsat == null) {
      _askAmount(tr('send.invoice'), (sats) => _prepareBolt11(invoice, BigInt.from(sats)));
    } else {
      await _prepareBolt11(invoice, null);
    }
  }

  void _askAmount(String dest, Future<void> Function(int sats) next) {
    _amountFor = dest;
    _withAmount = next;
    setState(() => _step = _Step.amount);
  }

  Future<void> _submitAmount() async {
    final a = int.tryParse(_amount.text.trim());
    final bad = satsError(a);
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    if (a == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _withAmount!(a);
    } catch (e) {
      setState(() => _error = tr('err.generic', {'e': e}));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _prepareBolt11(String invoice, BigInt? amount) async {
    final prep = await widget.sdk.prepareSendPayment(
      request: breez.PrepareSendPaymentRequest(paymentRequest: breez.PaymentRequest.input(input: invoice), amount: amount),
    );
    final bad = satsError(prep.amount.toInt());
    if (bad != null) throw bad;
    final m = prep.paymentMethod;
    _quote = null;
    _verb = 'enviar';
    _sats = prep.amount;
    _fee = m is breez.SendPaymentMethod_Bolt11Invoice ? m.lightningFeeSats : BigInt.zero;
    _dest = _short(invoice);
    _exec = () async => (await widget.sdk.sendPayment(
      request: breez.SendPaymentRequest(
        prepareResponse: prep,
        options: const breez.SendPaymentOptions.bolt11Invoice(preferSpark: false, completionTimeoutSecs: 30),
      ),
    )).payment;
    setState(() => _step = _Step.confirm);
  }

  Future<void> _prepareOnchain(String address, int sats, {String? key}) async {
    final bad = satsError(sats);
    if (bad != null) throw bad;
    final prep = await widget.sdk.prepareSendPayment(
      request: breez.PrepareSendPaymentRequest(paymentRequest: breez.PaymentRequest.input(input: address), amount: BigInt.from(sats)),
    );
    final m = prep.paymentMethod;
    if (m is! breez.SendPaymentMethod_BitcoinAddress) throw tr('send.badAddress');
    // What is confirmed (and read on screen) must be what will be paid.
    if (m.address.address != address) throw tr('send.addressChanged');
    // One key per prepared send, reused by every run of it: the SDK pays once per key and hands back the stored payment on a repeat.
    final sendKey = key ?? newIdempotencyKey();
    _onchainKey = sendKey;
    _onchainAddress = address;
    _onchainSats = sats;
    _quote = m.feeQuote;
    _speed = breez.OnchainConfirmationSpeed.medium;
    _verb = 'enviar';
    _sats = prep.amount;
    _fee = BigInt.from(onchainFeeSats(m.feeQuote, _speed));
    _dest = address; // the confirm step shows it in full
    _exec = () async {
      final q = _quote;
      // Nothing has been sent yet here, so this one is a plain failure.
      if (q == null || onchainQuoteExpired(q)) throw tr('send.quoteExpired');
      // Written down BEFORE the send: if the app dies or the sheet goes away mid-send, the next on-chain send finds this and asks first.
      try {
        await widget.pending.reserve(OnchainPending(key: sendKey, address: address, sats: sats));
      } catch (e) {
        throw tr('send.notRecorded', {'e': e});
      }
      final breez.Payment payment;
      try {
        payment = (await widget.sdk.sendPayment(
          request: breez.SendPaymentRequest(
            prepareResponse: prep,
            options: breez.SendPaymentOptions.bitcoinAddress(confirmationSpeed: _speed),
            idempotencyKey: sendKey,
          ),
        )).payment;
      } catch (e) {
        if (sendNeverStarted(e)) {
          // Refused before anything went out: a plain failure. On a RETRY that only proves THIS call did not start, not the earlier
          // attempt under the same key (it may have been committed without the SDK saving it), so the record stays.
          if (!_resumed) await _forget();
          rethrow;
        }
        // The SDK can throw after the provider accepted the exit: the outcome is unknown, never "failed". The record stays.
        throw UnconfirmedSend('$e');
      }
      await _forget();
      return payment;
    };
    setState(() => _step = _Step.confirm);
  }

  /// The outcome is known (sent, or refused before it started): the record can go. If clearing fails the next on-chain send asks the
  /// SDK about the key and finds the payment, so the worst case is one extra question.
  Future<void> _forget() async {
    try {
      await widget.pending.clear();
    } catch (_) {}
  }

  void _prepareWithdraw(breez.LnurlWithdrawRequestDetails d) {
    // the endpoint's limits are in millisats; the voucher pays its max
    final sats = d.maxWithdrawable ~/ BigInt.from(1000);
    final bad = satsError(sats.toInt());
    if (bad != null) throw bad;
    _quote = null;
    _verb = 'resgatar';
    _sats = sats;
    _fee = BigInt.zero;
    _dest = d.defaultDescription.isEmpty ? _short(d.url) : d.defaultDescription;
    _exec = () async => (await widget.sdk.lnurlWithdraw(
      request: breez.LnurlWithdrawRequest(amountSats: sats, withdrawRequest: d, completionTimeoutSecs: 30),
    )).payment;
    setState(() => _step = _Step.confirm);
  }

  Future<void> _prepareLnurlPay(breez.LnurlPayRequestDetails d, int sats) async {
    final prep = await widget.sdk.prepareLnurlPay(
      request: breez.PrepareLnurlPayRequest(amount: BigInt.from(sats), payRequest: d),
    );
    _quote = null;
    _verb = 'enviar';
    _sats = prep.amountSats;
    _fee = prep.feeSats;
    _dest = d.address ?? d.domain;
    _exec = () async => (await widget.sdk.lnurlPay(request: breez.LnurlPayRequest(prepareResponse: prep))).payment;
    setState(() => _step = _Step.confirm);
  }

  bool _asking = false;

  Future<void> _run() async {
    if (_asking || _step != _Step.confirm || _working) return;
    // An on-chain quote that expired while the user read the screen is re-asked in place, before the PIN, not after it.
    final q = _quote;
    if (q != null && onchainQuoteExpired(q)) {
      setState(() => _working = true);
      try {
        final picked = _speed;
        await _prepareOnchain(_onchainAddress, _onchainSats, key: _onchainKey);
        // the speed the user picked survives the new quote; the fee shown follows it
        _speed = picked;
        _fee = BigInt.from(onchainFeeSats(_quote!, picked));
        if (mounted) setState(() => _error = tr('send.quoteRefreshed'));
      } catch (e) {
        if (mounted) setState(() => _error = tr('send.quoteExpiredE', {'e': e}));
      } finally {
        if (mounted) setState(() => _working = false);
      }
      return;
    }
    _asking = true;
    final ok = await widget.confirmPin();
    _asking = false;
    if (!ok || !mounted) return;
    setState(() {
      _step = _Step.busy;
      _error = null;
    });
    try {
      final p = await _exec!();
      final s = p?.status;
      _ok = s != breez.PaymentStatus.failed;
      _result = s == null
          ? tr('send.sentWaiting')
          : s == breez.PaymentStatus.completed
          ? (_verb == 'resgatar' ? tr('send.redeemed') : tr('send.paid'))
          : s == breez.PaymentStatus.pending
          ? tr('send.processing')
          : tr('send.failed');
    } on UnconfirmedSend catch (e) {
      _ok = false;
      _unconfirmed = true;
      _result = unconfirmedSendMessage;
      _detail = e.detail;
    } catch (e) {
      _ok = false;
      _result = '$e';
    }
    if (mounted) setState(() => _step = _Step.done);
  }

  // While a send is running nothing closes the sheet (back included): walking away would hide the outcome and invite a second payment.
  @override
  Widget build(BuildContext context) => PopScope(canPop: _step != _Step.busy, child: _body(context));

  Widget _body(BuildContext context) {
    switch (_step) {
      case _Step.input:
        return Column(
          children: [
            SheetTitle(tr('send.title'), Icons.arrow_upward),
            const SizedBox(height: 20),
            TextField(
              controller: _input,
              minLines: 3,
              maxLines: 3,
              style: const TextStyle(fontFamily: monoFamily, fontSize: 14),
              decoration: InputDecoration(hintText: tr('send.inputHint')),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: OutlineButton(label: tr('common.paste'), icon: Icons.content_paste, onPressed: _paste)),
                const SizedBox(width: 10),
                Expanded(child: OutlineButton(label: tr('common.scan'), icon: Icons.qr_code_scanner, onPressed: _scan)),
              ],
            ),
            if (_error != null) _Err(_error!),
            const SizedBox(height: 16),
            GradientButton(label: _working ? tr('send.reading') : tr('common.continue'), onPressed: _working ? null : _continue),
            const SizedBox(height: 10),
            TextButton(onPressed: _working ? null : () => Navigator.pop(context), child: Text(tr('common.cancel'), style: const TextStyle(color: C.muted))),
          ],
        );
      case _Step.amount:
        return Column(
          children: [
            SheetTitle(tr('send.howMuch'), Icons.arrow_upward),
            const SizedBox(height: 8),
            Text(_amountFor, style: const TextStyle(color: C.muted, fontFamily: monoFamily, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontFamily: monoFamily, fontSize: 24, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: 'sats', suffixText: 'sats'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final v in const [500, 1000, 2500, 5000])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: OutlinedButton(
                        onPressed: () => setState(() => _amount.text = '$v'),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: C.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(fmtSats(v), style: const TextStyle(fontFamily: monoFamily, fontSize: 13)),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr('send.minimum', {'n': minPaymentSats}), style: const TextStyle(color: C.muted, fontSize: 12)),
            ),
            if (_error != null) _Err(_error!),
            const SizedBox(height: 16),
            GradientButton(label: _working ? tr('send.calculating') : tr('common.continue'), onPressed: _working ? null : _submitAmount),
            const SizedBox(height: 10),
            TextButton(onPressed: _working ? null : () => Navigator.pop(context), child: Text(tr('common.cancel'), style: const TextStyle(color: C.muted))),
          ],
        );
      case _Step.confirm:
        final resgate = _verb == 'resgatar';
        return Column(
          children: [
            Text(resgate ? tr('send.youWillRedeem') : tr('send.youWillSend'), style: const TextStyle(color: C.textSec, fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              '${fmtSats(_sats.toInt() + (resgate ? 0 : _fee.toInt()))} sats',
              style: const TextStyle(fontFamily: monoFamily, fontSize: 36, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Panel(
              child: Column(
                children: [
                  if (_quote != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('common.to'), style: const TextStyle(color: C.muted, fontSize: 13)),
                        const SizedBox(height: 4),
                        SelectableText(_dest, key: const Key('full-address'), style: const TextStyle(fontFamily: monoFamily, fontSize: 13)),
                      ],
                    )
                  else
                    RowKV(resgate ? tr('send.voucher') : tr('common.to'), _dest),
                  const Divider(height: 8),
                  RowKV(tr('common.amount'), '${fmtSats(_sats.toInt())} sats'),
                  if (_quote != null) ...[
                    const Divider(height: 8),
                    Row(
                      children: [
                        for (final sp in breez.OnchainConfirmationSpeed.values)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: ChoiceChip(
                                key: Key('speed-${sp.name}'),
                                label: Text('${speedLabel(sp)}\n${fmtSats(onchainFeeSats(_quote!, sp))}', textAlign: TextAlign.center),
                                selected: _speed == sp,
                                onSelected: (_) => setState(() {
                                  _speed = sp;
                                  _fee = BigInt.from(onchainFeeSats(_quote!, sp));
                                }),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (!resgate) RowKV(tr('send.networkFee'), '${fmtSats(_fee.toInt())} sats'),
                  if (!resgate) RowKV(tr('send.total'), '${fmtSats(_sats.toInt() + _fee.toInt())} sats', strong: true),
                ],
              ),
            ),
            if (_error != null) _Err(_error!),
            const SizedBox(height: 20),
            GradientButton(
              label: resgate ? tr('send.redeem') : tr('btn.send'),
              colors: resgate ? const [C.success, Color(0xFF059669)] : const [C.electric, Color(0xFF0099CC)],
              onPressed: _run,
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('common.cancel'), style: const TextStyle(color: C.muted))),
          ],
        );
      case _Step.pending:
        final r = _open;
        return Column(
          children: [
            SheetTitle(tr('send.openTitle'), Icons.help_outline),
            const SizedBox(height: 12),
            Text(
              tr('send.openBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: C.textSec, fontSize: 14),
            ),
            const SizedBox(height: 14),
            if (r != null)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RowKV(tr('common.amount'), '${fmtSats(r.sats)} sats'),
                    const Divider(height: 8),
                    Text(tr('common.to'), style: const TextStyle(color: C.muted, fontSize: 13)),
                    const SizedBox(height: 4),
                    SelectableText(r.address, key: const Key('pending-address'), style: const TextStyle(fontFamily: monoFamily, fontSize: 13)),
                  ],
                ),
              ),
            if (_error != null) _Err(_error!),
            const SizedBox(height: 16),
            GradientButton(label: tr('send.recheck'), onPressed: _working ? null : _recheck),
            const SizedBox(height: 8),
            OutlineButton(label: tr('send.resume'), icon: Icons.replay, onPressed: _working ? null : _resume),
            const SizedBox(height: 8),
            TextButton(key: const Key('discard'), onPressed: _working ? null : _discard, child: Text(tr('send.discardRecord'), style: const TextStyle(color: C.warn))),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('common.close'), style: const TextStyle(color: C.muted))),
          ],
        );
      case _Step.busy:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 3, color: C.primaryLight)),
              const SizedBox(height: 24),
              Text(tr('send.sending'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(tr('send.keepOpen'), style: const TextStyle(color: C.textSec, fontSize: 14)),
            ],
          ),
        );
      case _Step.done:
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_ok ? C.success : C.warn).withValues(alpha: .15),
                  border: Border.all(color: _ok ? C.success : C.warn, width: 2),
                ),
                child: Icon(_ok ? Icons.check : (_unconfirmed ? Icons.help_outline : Icons.close), size: 36, color: _ok ? C.success : C.warn),
              ),
              const SizedBox(height: 20),
              Text(_result, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _ok ? C.primaryLight : C.warn)),
              if (_unconfirmed && _detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_detail, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 12)),
                ),
              const SizedBox(height: 24),
              GradientButton(label: tr('common.done'), onPressed: () => Navigator.pop(context, true)),
            ],
          ),
        );
    }
  }
}

class _Err extends StatelessWidget {
  const _Err(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(text, style: const TextStyle(color: C.warn, fontSize: 13)),
  );
}
