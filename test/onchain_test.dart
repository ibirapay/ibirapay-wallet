import 'dart:async';
import 'dart:math' show Random;

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/onchain.dart';
import 'package:wallet/send_sheet.dart';
import 'package:wallet/theme.dart' show fmtSats;

import 'memory_secret_store.dart';

OnchainPendingStore _pend([MemorySecretStore? s]) => OnchainPendingStore(s ?? MemorySecretStore());

breez.SendOnchainSpeedFeeQuote _q(int user, int l1) => breez.SendOnchainSpeedFeeQuote(userFeeSat: BigInt.from(user), l1BroadcastFeeSat: BigInt.from(l1));

breez.SendOnchainFeeQuote _quote({int expiresAt = 0}) => breez.SendOnchainFeeQuote(
  id: 'q1',
  expiresAt: BigInt.from(expiresAt),
  speedFast: _q(100, 400),
  speedMedium: _q(80, 220),
  speedSlow: _q(60, 110),
  isEstimate: false,
);

breez.DepositInfo _dep({bool mature = false, breez.DepositClaimError? err, int sats = 20000}) =>
    breez.DepositInfo(txid: 'ab' * 32, vout: 0, amountSats: BigInt.from(sats), isMature: mature, claimError: err);

const _addr = 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh';

breez.Bolt11InvoiceDetails _bolt11(String invoice) => breez.Bolt11InvoiceDetails(
  amountMsat: BigInt.from(7000000),
  expiry: BigInt.from(3600),
  invoice: breez.Bolt11Invoice(bolt11: invoice, source: const breez.PaymentRequestSource()),
  minFinalCltvExpiryDelta: BigInt.from(18),
  network: breez.BitcoinNetwork.bitcoin,
  payeePubkey: '02' * 33,
  paymentHash: 'aa' * 32,
  paymentSecret: 'bb' * 32,
  routingHints: const [],
  timestamp: BigInt.zero,
);

breez.BitcoinAddressDetails _btc(String address, [breez.BitcoinNetwork n = breez.BitcoinNetwork.bitcoin]) =>
    breez.BitcoinAddressDetails(address: address, network: n, source: const breez.PaymentRequestSource());

/// Stands in for the SDK. Like the real one it pays once per idempotency key and hands back the stored payment on a repeat.
class _FakeSdk implements breez.BreezSdk {
  _FakeSdk(this.quote, {this.quotes});
  final breez.SendOnchainFeeQuote quote;

  /// Quotes handed out one per prepare (the last one repeats); lets a test start with an expired one.
  final List<breez.SendOnchainFeeQuote>? quotes;
  int prepares = 0;
  final sent = <breez.OnchainConfirmationSpeed>[];
  final keys = <String?>[];
  final preparedInputs = <String>[];
  BigInt? preparedAmount;
  bool throwAfterAccept = false;
  /// With [throwAfterAccept]: false = the exit is lost, nothing is stored under the key (getPayment finds nothing).
  bool storeOnThrow = true;
  /// Thrown by sendPayment before anything is stored (the SDK refused up front).
  Object? failBeforeSend;
  /// Runs at the start of sendPayment, to look at the world at the moment of the send.
  Future<void> Function()? onSend;
  /// sendPayment waits for this after storing the payment (the exit is slow).
  Completer<void>? hold;
  String? answerAddress; // what prepareSendPayment reports back as the destination
  final _stored = <String, breez.Payment>{};

  @override
  Future<breez.InputType> parse({required String input}) async {
    if (input.startsWith('bitcoin:')) {
      final uri = Uri.parse(input);
      final raw = uri.queryParameters['amount'];
      // BIP21 amounts are in BTC; the SDK parser converts to sats, so does the fake.
      final amount = raw == null ? null : BigInt.from((double.parse(raw) * 100000000).round());
      final addr = breez.InputType.bitcoinAddress(_btc(uri.path, uri.path.startsWith('tb1') ? breez.BitcoinNetwork.testnet3 : breez.BitcoinNetwork.bitcoin));
      final ln = uri.queryParameters['lightning'];
      return breez.InputType.bip21(
        breez.Bip21Details(amountSat: amount, uri: input, extras: const [], paymentMethods: [addr, if (ln != null) breez.InputType.bolt11Invoice(_bolt11(ln))]),
      );
    }
    return breez.InputType.bitcoinAddress(_btc(input, input.startsWith('tb1') ? breez.BitcoinNetwork.testnet3 : breez.BitcoinNetwork.bitcoin));
  }

  @override
  Future<breez.PrepareSendPaymentResponse> prepareSendPayment({required breez.PrepareSendPaymentRequest request}) async {
    preparedAmount = request.amount;
    final input = (request.paymentRequest as breez.PaymentRequest_Input).input;
    preparedInputs.add(input);
    final q = quotes == null ? quote : quotes![prepares < quotes!.length ? prepares : quotes!.length - 1];
    prepares++;
    if (input.startsWith('lnbc')) throw StateError('bolt11-branch');
    return breez.PrepareSendPaymentResponse(
      paymentMethod: breez.SendPaymentMethod.bitcoinAddress(address: _btc(answerAddress ?? input), feeQuote: q),
      amount: request.amount ?? BigInt.zero,
      feePolicy: breez.FeePolicy.feesExcluded,
    );
  }

  @override
  Future<breez.SendPaymentResponse> sendPayment({required breez.SendPaymentRequest request}) async {
    keys.add(request.idempotencyKey);
    await onSend?.call();
    if (failBeforeSend != null) throw failBeforeSend!;
    final key = request.idempotencyKey;
    final again = key == null ? null : _stored[key];
    if (again != null) return breez.SendPaymentResponse(payment: again);
    final o = request.options;
    sent.add((o as breez.SendPaymentOptions_BitcoinAddress).confirmationSpeed);
    final payment = breez.Payment(
      id: key ?? 'p${sent.length}',
      paymentType: breez.PaymentType.send,
      status: breez.PaymentStatus.pending,
      amount: request.prepareResponse.amount,
      fees: BigInt.zero,
      timestamp: BigInt.zero,
      method: breez.PaymentMethod.withdraw,
    );
    if (key != null && (!throwAfterAccept || storeOnThrow)) _stored[key] = payment;
    if (hold != null) await hold!.future;
    if (throwAfterAccept) throw StateError('apply_payment_update failed after the exit was accepted');
    return breez.SendPaymentResponse(payment: payment);
  }

  int lookups = 0;

  @override
  Future<breez.GetPaymentResponse> getPayment({required breez.GetPaymentRequest request}) async {
    lookups++;
    final p = _stored[request.paymentId];
    if (p == null) throw StateError('payment not found');
    return breez.GetPaymentResponse(payment: p);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<void> _openSend(WidgetTester t, _FakeSdk sdk, {required Future<bool> Function() pin, OnchainPendingStore? pending}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: SingleChildScrollView(child: SendSheet(sdk: sdk, pending: pending ?? _pend(), initial: _addr, confirmPin: pin))),
    ),
  );
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField), '5000');
  await t.tap(find.text('Continuar'));
  await t.pumpAndSettle();
}

Future<void> _openInSheet(WidgetTester t, _FakeSdk sdk, OnchainPendingStore store) =>
    _openSend(t, sdk, pin: () async => true, pending: store);

void main() {
  group('helpers', () {
    test('fee of a speed = our fee + L1 broadcast fee', () {
      final q = _quote();
      expect(onchainFeeSats(q, breez.OnchainConfirmationSpeed.fast), 500);
      expect(onchainFeeSats(q, breez.OnchainConfirmationSpeed.medium), 300);
      expect(onchainFeeSats(q, breez.OnchainConfirmationSpeed.slow), 170);
    });

    test('quote expiry: an estimate never expires, a real quote expires with a safety margin', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000 * 1000);
      expect(onchainQuoteExpired(_quote(), now: now), isFalse);
      expect(onchainQuoteExpired(_quote(expiresAt: 1100), now: now), isFalse);
      expect(onchainQuoteExpired(_quote(expiresAt: 1020), now: now), isTrue); // inside the 30 s margin
      expect(onchainQuoteExpired(_quote(expiresAt: 900), now: now), isTrue);
    });

    test('deposit status says what is going on, and only fixable errors offer a retry', () {
      expect(depositStatus(_dep()), contains('3 confirmações'));
      expect(depositStatus(_dep(mature: true)), contains('resgatando'));
      final fee = _dep(err: breez.DepositClaimError.maxDepositClaimFeeExceeded(tx: 't', vout: 0, requiredFeeSats: BigInt.from(900)));
      expect(depositStatus(fee), contains('900'));
      expect(depositCanRetry(fee), isTrue);
      final small = _dep(err: const breez.DepositClaimError.depositTooSmall(tx: 't', vout: 0));
      expect(depositStatus(small), contains('pequeno'));
      expect(depositCanRetry(small), isFalse);
      expect(depositCanRetry(_dep()), isFalse);
    });

    test('idempotency key: a v4 UUID, random each time', () {
      final re = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final keys = {for (var i = 0; i < 50; i++) newIdempotencyKey()};
      expect(keys.length, 50);
      expect(keys.every(re.hasMatch), isTrue);
      expect(newIdempotencyKey(Random(1)), newIdempotencyKey(Random(1)), reason: 'deterministic only for a seeded Random');
    });

    test('only bitcoin mainnet addresses are accepted', () {
      expect(networkError(breez.BitcoinNetwork.bitcoin), isNull);
      for (final n in [breez.BitcoinNetwork.testnet3, breez.BitcoinNetwork.testnet4, breez.BitcoinNetwork.signet, breez.BitcoinNetwork.regtest]) {
        expect(networkError(n), contains('outra rede'));
        expect(networkError(n), contains(n.name));
      }
    });

    test('fee needed to claim: only the fee-ceiling error carries one', () {
      expect(depositFeeNeeded(_dep(err: breez.DepositClaimError.maxDepositClaimFeeExceeded(tx: 't', vout: 0, requiredFeeSats: BigInt.from(900)))), 900);
      expect(depositFeeNeeded(_dep(err: const breez.DepositClaimError.generic(message: 'x'))), isNull);
      expect(depositFeeNeeded(_dep()), isNull);
    });

    test('QR carries the plain bitcoin: URI', () => expect(bitcoinUri(' $_addr '), 'bitcoin:$_addr'));
  });

  group('receive view', () {
    OnchainApi api({
      required List<breez.DepositInfo> Function() deposits,
      required Map<String, int> Function() received,
      List<String>? claimed,
      List<int?>? fees,
    }) => OnchainApi(
      address: () async => _addr,
      deposits: () async => deposits(),
      claim: (d, {int? maxFeeSats}) async {
        claimed?.add(d.txid);
        fees?.add(maxFeeSats);
      },
      receivedDeposits: () async => received(),
    );

    testWidgets('shows the address and the waiting deposit', (t) async {
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: OnchainReceiveView(api: api(deposits: () => [_dep()], received: () => {}), onReceived: (_) {})))));
      await t.pumpAndSettle();
      expect(find.text(_addr), findsOneWidget);
      expect(find.textContaining('3 confirmações'), findsWidgets);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('pops with the sats only for a NEW credited deposit, never for an old one', (t) async {
      var received = <String, int>{'old': 111};
      int? got;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnchainReceiveView(api: api(deposits: () => [], received: () => received), onReceived: (s) => got = s, pollEvery: const Duration(milliseconds: 50)),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(got, isNull);
      received = {'old': 111, 'new': 19500};
      await t.pump(const Duration(milliseconds: 200));
      expect(got, 19500);
      await t.pumpWidget(const SizedBox());
    });

    Future<void> pumpReceive(WidgetTester t, OnchainApi a) async {
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: OnchainReceiveView(api: a, onReceived: (_) {})))));
      await t.pumpAndSettle();
    }

    final feeFailed = _dep(err: breez.DepositClaimError.maxDepositClaimFeeExceeded(tx: 't', vout: 0, requiredFeeSats: BigInt.from(900)));

    testWidgets('a deposit the fee ceiling refused: the button names the fee, a confirmation comes first, then the claim carries that fee', (t) async {
      final claimed = <String>[], fees = <int?>[];
      await pumpReceive(t, api(deposits: () => [feeFailed], received: () => {}, claimed: claimed, fees: fees));
      expect(find.text('Tentar de novo'), findsNothing);
      await t.tap(find.text('Resgatar pagando 900 sats'));
      await t.pumpAndSettle();
      expect(claimed, isEmpty, reason: 'nothing is claimed before the user agrees to the fee');
      expect(find.text('Pagar a taxa de rede?'), findsOneWidget);
      await t.tap(find.byKey(const Key('claim-fee-cancel')));
      await t.pumpAndSettle();
      expect(claimed, isEmpty);
      await t.tap(find.text('Resgatar pagando 900 sats'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('claim-fee-confirm')));
      await t.pumpAndSettle();
      expect(claimed, ['ab' * 32]);
      expect(fees, [900]);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('another retryable error retries as before: no dialog, no raised ceiling', (t) async {
      final claimed = <String>[], fees = <int?>[];
      final other = _dep(err: const breez.DepositClaimError.generic(message: 'x'));
      await pumpReceive(t, api(deposits: () => [other], received: () => {}, claimed: claimed, fees: fees));
      await t.tap(find.text('Tentar de novo'));
      await t.pumpAndSettle();
      expect(claimed, ['ab' * 32]);
      expect(fees, [null]);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('send sheet on-chain', () {
    testWidgets('medium by default: total = amount + medium fee; switching speed changes fee and total', (t) async {
      final sdk = _FakeSdk(_quote());
      await _openSend(t, sdk, pin: () async => true);
      expect(sdk.preparedAmount, BigInt.from(5000));
      expect(find.text('${fmtSats(5300)} sats'), findsWidgets); // 5000 + 300
      await t.tap(find.byKey(const Key('speed-fast')));
      await t.pumpAndSettle();
      expect(find.text('${fmtSats(5500)} sats'), findsWidgets);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk.sent, [breez.OnchainConfirmationSpeed.fast]);
    });

    testWidgets('a refused PIN sends nothing', (t) async {
      final sdk = _FakeSdk(_quote());
      await _openSend(t, sdk, pin: () async => false);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk.sent, isEmpty);
    });

    testWidgets('an expired quote is refused before anything is sent', (t) async {
      final sdk = _FakeSdk(_quote(expiresAt: 1));
      await _openSend(t, sdk, pin: () async => true);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk.sent, isEmpty);
      expect(find.textContaining('expirou'), findsOneWidget);
    });

    testWidgets('a bitcoin: URI carrying an amount below the minimum (0.000001 BTC = 100 sats) is refused before any quote is asked', (t) async {
      final sdk = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SendSheet(sdk: sdk, pending: _pend(), initial: 'bitcoin:$_addr?amount=0.000001', confirmPin: () async => true))));
      await t.pumpAndSettle();
      expect(sdk.preparedAmount, isNull);
      expect(find.textContaining('Mínimo'), findsWidgets);
    });

    testWidgets('a bitcoin: URI with a valid amount (0.00007 BTC = 7000 sats, BIP21 is in BTC) goes straight to the confirm step', (t) async {
      final sdk = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SendSheet(sdk: sdk, pending: _pend(), initial: 'bitcoin:$_addr?amount=0.00007', confirmPin: () async => true))));
      await t.pumpAndSettle();
      expect(sdk.preparedAmount, BigInt.from(7000));
      expect(find.text('Enviar'), findsWidgets);
    });

    testWidgets('below the minimum is refused before any quote is asked', (t) async {
      final sdk = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SendSheet(sdk: sdk, pending: _pend(), initial: _addr, confirmPin: () async => true))));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '100');
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();
      expect(sdk.preparedAmount, isNull);
      expect(find.textContaining('Mínimo'), findsWidgets);
    });

    testWidgets('the on-chain send carries a v4 UUID idempotency key, and each prepared send has its own', (t) async {
      final sdk = _FakeSdk(_quote());
      await _openSend(t, sdk, pin: () async => true);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk.keys, hasLength(1));
      expect(sdk.keys.single, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      await t.pumpWidget(const SizedBox()); // a fresh sheet, not the finished one
      final sdk2 = _FakeSdk(_quote());
      await _openSend(t, sdk2, pin: () async => true);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk2.keys.single, isNot(sdk.keys.single));
    });

    testWidgets('the SDK throws after accepting the exit: shown as NOT CONFIRMED, never as a failure, and nothing invites a second send', (t) async {
      final sdk = _FakeSdk(_quote())..throwAfterAccept = true;
      await _openSend(t, sdk, pin: () async => true);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk.sent, hasLength(1));
      expect(find.text(unconfirmedSendMessage), findsOneWidget);
      expect(find.text('Falhou'), findsNothing);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(find.text('Enviar'), findsNothing, reason: 'no send button left on the result screen');
      expect(find.text('Concluir'), findsOneWidget);
      // the stored payment is what a repeat with the same key would return: the exit was recorded once
      expect(sdk.keys.toSet(), hasLength(1));
    });

    testWidgets('a repeated send with the same key does not pay twice (what the key buys)', (t) async {
      final sdk = _FakeSdk(_quote());
      final prep = await sdk.prepareSendPayment(request: breez.PrepareSendPaymentRequest(paymentRequest: breez.PaymentRequest.input(input: _addr), amount: BigInt.from(5000)));
      final key = newIdempotencyKey();
      final req = breez.SendPaymentRequest(prepareResponse: prep, options: const breez.SendPaymentOptions.bitcoinAddress(confirmationSpeed: breez.OnchainConfirmationSpeed.medium), idempotencyKey: key);
      final a = await sdk.sendPayment(request: req);
      final b = await sdk.sendPayment(request: req);
      expect(sdk.sent, hasLength(1));
      expect(b.payment.id, a.payment.id);
    });

    testWidgets('a testnet address is refused right after parse, before any quote', (t) async {
      final sdk = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SendSheet(sdk: sdk, pending: _pend(), initial: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx', confirmPin: () async => true))));
      await t.pumpAndSettle();
      expect(find.textContaining('outra rede'), findsOneWidget);
      expect(sdk.prepares, 0);
      expect(find.text('Continuar'), findsOneWidget, reason: 'stays on the input step');
    });

    testWidgets('a testnet address inside a bitcoin: URI is refused too', (t) async {
      final sdk = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SendSheet(sdk: sdk, pending: _pend(), initial: 'bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.00007', confirmPin: () async => true))));
      await t.pumpAndSettle();
      expect(find.textContaining('outra rede'), findsOneWidget);
      expect(sdk.prepares, 0);
    });

    testWidgets('the confirm step shows the FULL address, selectable', (t) async {
      final sdk = _FakeSdk(_quote());
      await _openSend(t, sdk, pin: () async => true);
      final w = t.widget<SelectableText>(find.byKey(const Key('full-address')));
      expect(w.data, _addr);
      expect(_addr.length, greaterThan(28), reason: 'the old short form would have hidden the middle');
    });

    testWidgets('if the SDK prepares a different destination than the one entered, nothing reaches the confirm step', (t) async {
      final sdk = _FakeSdk(_quote())..answerAddress = 'bc1qattackerattackerattackerattackerattacke';
      await _openSend(t, sdk, pin: () async => true);
      expect(find.textContaining('endereço mudou'), findsOneWidget);
      expect(find.byKey(const Key('full-address')), findsNothing);
      expect(sdk.sent, isEmpty);
    });

    testWidgets('a unified bitcoin: URI with a lightning= invoice goes through Lightning, not on-chain', (t) async {
      final sdk = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SendSheet(sdk: sdk, pending: _pend(), initial: 'bitcoin:$_addr?amount=0.00007&lightning=lnbc70u1fake', confirmPin: () async => true))));
      await t.pumpAndSettle();
      expect(sdk.preparedInputs, ['lnbc70u1fake']);
      expect(find.textContaining('bolt11-branch'), findsOneWidget); // the fake's Lightning prepare ran; on-chain never did
    });

    testWidgets('an expired quote is re-asked in place BEFORE the PIN, then the send goes through', (t) async {
      final sdk = _FakeSdk(_quote(), quotes: [_quote(expiresAt: 1), _quote()]);
      var pins = 0;
      await _openSend(t, sdk, pin: () async {
        pins++;
        return true;
      });
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(pins, 0, reason: 'the PIN is not asked for a quote that is already dead');
      expect(sdk.sent, isEmpty);
      expect(sdk.prepares, 2);
      expect(find.textContaining('atualizada'), findsOneWidget);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(pins, 1);
      expect(sdk.sent, hasLength(1));
    });
  });

  group('on-chain send safety', () {
    Future<void> openInRoute(WidgetTester t, _FakeSdk sdk, OnchainPendingStore store, {String? initial = _addr}) async {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(onPressed: () => showSendSheet(c, sdk: sdk, pending: store, initial: initial, confirmPin: () async => true), child: const Text('abrir')),
            ),
          ),
        ),
      );
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
    }

    Future<void> amountAndConfirm(WidgetTester t) async {
      await t.enterText(find.byType(TextField), '5000');
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();
    }

    testWidgets('H1: while the send runs, Back, a tap outside and a swipe down do not close the sheet; the outcome is shown at the end', (t) async {
      final sdk = _FakeSdk(_quote())..hold = Completer<void>();
      final store = _pend();
      await openInRoute(t, sdk, store);
      await amountAndConfirm(t);
      await t.tap(find.text('Enviar').last);
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Enviando...'), findsOneWidget);
      await t.binding.handlePopRoute(); // Android Back
      await t.pump();
      expect(find.text('Enviando...'), findsOneWidget, reason: 'Back is blocked while sending');
      await t.tapAt(const Offset(5, 5)); // the barrier
      await t.pump();
      expect(find.text('Enviando...'), findsOneWidget, reason: 'a tap outside does not dismiss');
      await t.fling(find.text('Enviando...'), const Offset(0, 500), 1000); // swipe down
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Enviando...'), findsOneWidget, reason: 'a swipe does not dismiss');
      sdk.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text('Concluir'), findsOneWidget);
      expect(sdk.sent, hasLength(1));
    });

    testWidgets('H1: outside a running send the sheet is still not dismissible by tap or swipe (Cancelar is the way out)', (t) async {
      final sdk = _FakeSdk(_quote());
      await openInRoute(t, sdk, _pend());
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text('Continuar'), findsOneWidget);
      await t.fling(find.text('Continuar'), const Offset(0, 500), 1000);
      await t.pumpAndSettle();
      expect(find.text('Continuar'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(find.text('Continuar'), findsNothing);
    });

    testWidgets('M1: the send is written down BEFORE it goes out, and forgotten once it is known', (t) async {
      final sdk = _FakeSdk(_quote());
      final store = _pend();
      OnchainPending? atSend;
      sdk.onSend = () async => atSend = await store.open();
      await _openInSheet(t, sdk, store);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(atSend, isNotNull, reason: 'recorded before sendPayment ran');
      expect(atSend!.key, sdk.keys.single);
      expect(atSend!.address, _addr);
      expect(atSend!.sats, 5000);
      expect(await store.open(), isNull, reason: 'the SDK returned a payment: outcome known');
    });

    testWidgets('M1: if the record cannot be written, NOTHING is sent', (t) async {
      final sdk = _FakeSdk(_quote());
      await _openInSheet(t, sdk, _pend(_FailingWrites()));
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk.sent, isEmpty);
      expect(sdk.keys, isEmpty, reason: 'sendPayment was never called');
      expect(find.textContaining('Não consegui registrar'), findsOneWidget);
    });

    testWidgets('M1: unconfirmed keeps the record; the next on-chain send finds the payment under the key and clears it', (t) async {
      final sdk = _FakeSdk(_quote())..throwAfterAccept = true;
      final store = _pend();
      await _openInSheet(t, sdk, store);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(find.text(unconfirmedSendMessage), findsOneWidget);
      expect(await store.open(), isNotNull);
      await t.pumpWidget(const SizedBox());
      // a new sheet: the SDK has the payment under the key, so the record is settled and the user is told
      final prepares = sdk.prepares;
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SendSheet(sdk: sdk, pending: store, initial: _addr, confirmPin: () async => true))));
      await t.pumpAndSettle();
      expect(sdk.lookups, 1);
      expect(find.textContaining('já consta no histórico'), findsOneWidget);
      expect(await store.open(), isNull);
      expect(sdk.prepares, prepares, reason: 'no new quote was asked');
      expect(find.text('Envio em aberto'), findsNothing);
    });

    Future<OnchainPendingStore> lostSend(WidgetTester t) async {
      final sdk = _FakeSdk(_quote())
        ..throwAfterAccept = true
        ..storeOnThrow = false;
      final store = _pend();
      await _openInSheet(t, sdk, store);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(find.text(unconfirmedSendMessage), findsOneWidget);
      return store;
    }

    testWidgets('M1: a send with no stored payment BLOCKS a new on-chain send and shows the open one in full', (t) async {
      final store = await lostSend(t);
      final first = (await store.open())!;
      await t.pumpWidget(const SizedBox());
      final sdk2 = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: SendSheet(sdk: sdk2, pending: store, initial: _addr, confirmPin: () async => true)))));
      await t.pumpAndSettle();
      expect(find.text('Envio em aberto'), findsOneWidget);
      expect(t.widget<SelectableText>(find.byKey(const Key('pending-address'))).data, first.address);
      expect(find.textContaining(fmtSats(first.sats)), findsWidgets);
      expect(sdk2.prepares, 0, reason: 'no new send was even quoted');
      expect(find.text('Enviar'), findsNothing);
      expect(sdk2.sent, isEmpty);
    });

    testWidgets('M1: "retry with the same key" re-sends the SAME address, amount and key, and clears the record on success', (t) async {
      final store = await lostSend(t);
      final first = (await store.open())!;
      await t.pumpWidget(const SizedBox());
      final sdk2 = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: SendSheet(sdk: sdk2, pending: store, initial: _addr, confirmPin: () async => true)))));
      await t.pumpAndSettle();
      await t.tap(find.text('Tentar de novo com a mesma chave'));
      await t.pumpAndSettle();
      expect(sdk2.preparedInputs, [first.address]);
      expect(sdk2.preparedAmount, BigInt.from(first.sats));
      expect(t.widget<SelectableText>(find.byKey(const Key('full-address'))).data, first.address);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk2.keys, [first.key], reason: 'the same key, so the SDK pays once');
      expect(await store.open(), isNull);
      expect(find.text('Concluir'), findsOneWidget);
    });

    testWidgets('L3: re-asking an expired quote keeps the speed the user picked, and the fee shown is that speed', (t) async {
      final sdk = _FakeSdk(_quote(), quotes: [_quote(expiresAt: 1), _quote()]);
      await _openSend(t, sdk, pin: () async => true);
      await t.tap(find.byKey(const Key('speed-fast')));
      await t.pumpAndSettle();
      await t.tap(find.text('Enviar').last); // expired: re-asked
      await t.pumpAndSettle();
      expect(sdk.prepares, 2);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('speed-fast'))).selected, isTrue);
      expect(find.text('${fmtSats(5500)} sats'), findsWidgets);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk.sent, [breez.OnchainConfirmationSpeed.fast]);
    });

    testWidgets('M1: a retry whose quote expired is re-asked in place and STILL goes out under the first key', (t) async {
      final store = await lostSend(t);
      final first = (await store.open())!;
      await t.pumpWidget(const SizedBox());
      final sdk2 = _FakeSdk(_quote(), quotes: [_quote(expiresAt: 1), _quote()]);
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: SendSheet(sdk: sdk2, pending: store, initial: _addr, confirmPin: () async => true)))));
      await t.pumpAndSettle();
      await t.tap(find.text('Tentar de novo com a mesma chave'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enviar').last); // expired: re-asked, nothing sent
      await t.pumpAndSettle();
      expect(sdk2.prepares, 2);
      expect(sdk2.keys, isEmpty);
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect(sdk2.keys, [first.key]);
    });

    testWidgets('M1: a RETRY refused up front (fee rose) keeps the record, so a later send is still guarded', (t) async {
      final store = await lostSend(t);
      final first = (await store.open())!;
      await t.pumpWidget(const SizedBox());
      final sdk2 = _FakeSdk(_quote())..failBeforeSend = const breez.SdkError.invalidInput('fee rose, re-prepare');
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: SendSheet(sdk: sdk2, pending: store, initial: _addr, confirmPin: () async => true)))));
      await t.pumpAndSettle();
      await t.tap(find.text('Tentar de novo com a mesma chave'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enviar').last);
      await t.pumpAndSettle();
      expect((await store.open())?.key, first.key, reason: 'the earlier attempt under this key may have gone out');
      await t.pumpWidget(const SizedBox());
      final sdk3 = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: SendSheet(sdk: sdk3, pending: store, initial: _addr, confirmPin: () async => true)))));
      await t.pumpAndSettle();
      expect(find.text('Envio em aberto'), findsOneWidget);
      expect(sdk3.prepares, 0);
    });

    testWidgets('M1: discard asks first; "Voltar" keeps the record, "Descartar" clears it and returns to the input step', (t) async {
      final store = await lostSend(t);
      await t.pumpWidget(const SizedBox());
      final sdk2 = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: SendSheet(sdk: sdk2, pending: store, initial: _addr, confirmPin: () async => true)))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('discard')));
      await t.pumpAndSettle();
      expect(find.text('Descartar o registro?'), findsOneWidget);
      expect(await store.open(), isNotNull, reason: 'nothing is discarded before the user agrees');
      await t.tap(find.byKey(const Key('discard-no')));
      await t.pumpAndSettle();
      expect(await store.open(), isNotNull);
      expect(find.text('Envio em aberto'), findsOneWidget);
      await t.tap(find.byKey(const Key('discard')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('discard-yes')));
      await t.pumpAndSettle();
      expect(await store.open(), isNull);
      expect(find.text('Continuar'), findsOneWidget);
    });

    testWidgets('M1: an open on-chain send does not block a Lightning payment', (t) async {
      final store = await lostSend(t);
      await t.pumpWidget(const SizedBox());
      final sdk2 = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SendSheet(sdk: sdk2, pending: store, initial: 'bitcoin:$_addr?lightning=lnbc70u1fake', confirmPin: () async => true))));
      await t.pumpAndSettle();
      expect(sdk2.preparedInputs, ['lnbc70u1fake']);
      expect(find.text('Envio em aberto'), findsNothing);
    });

    testWidgets('M1: "check again" settles the record when the payment turns up', (t) async {
      final store = await lostSend(t);
      final key = (await store.open())!.key;
      await t.pumpWidget(const SizedBox());
      final sdk2 = _FakeSdk(_quote());
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: SendSheet(sdk: sdk2, pending: store, initial: _addr, confirmPin: () async => true)))));
      await t.pumpAndSettle();
      await t.tap(find.text('Conferir de novo'));
      await t.pumpAndSettle();
      expect(find.textContaining('Ainda sem registro'), findsOneWidget);
      expect(await store.open(), isNotNull);
      // the SDK now has it
      await sdk2.sendPayment(
        request: breez.SendPaymentRequest(
          prepareResponse: await sdk2.prepareSendPayment(request: breez.PrepareSendPaymentRequest(paymentRequest: breez.PaymentRequest.input(input: _addr), amount: BigInt.from(5000))),
          options: const breez.SendPaymentOptions.bitcoinAddress(confirmationSpeed: breez.OnchainConfirmationSpeed.medium),
          idempotencyKey: key,
        ),
      );
      await t.tap(find.text('Conferir de novo'));
      await t.pumpAndSettle();
      expect(await store.open(), isNull);
      expect(find.text('Continuar'), findsOneWidget);
    });

    testWidgets('L1: an SDK error that proves nothing started is a plain failure and the record goes; any other error stays unconfirmed', (t) async {
      for (final e in <Object>[const breez.SdkError.invalidInput('Amount is below the minimum'), const breez.SdkError.insufficientFunds(), const breez.SdkError.invalidUuid('x')]) {
        final sdk = _FakeSdk(_quote())..failBeforeSend = e;
        final store = _pend();
        await _openInSheet(t, sdk, store);
        await t.tap(find.text('Enviar').last);
        await t.pumpAndSettle();
        expect(find.text(unconfirmedSendMessage), findsNothing, reason: '$e');
        expect(find.byIcon(Icons.close), findsOneWidget, reason: '$e');
        expect(await store.open(), isNull, reason: '$e');
        await t.pumpWidget(const SizedBox());
      }
      for (final e in <Object>[const breez.SdkError.networkError('reset'), const breez.SdkError.sparkError('x'), StateError('boom')]) {
        final sdk = _FakeSdk(_quote())..failBeforeSend = e;
        final store = _pend();
        await _openInSheet(t, sdk, store);
        await t.tap(find.text('Enviar').last);
        await t.pumpAndSettle();
        expect(find.text(unconfirmedSendMessage), findsOneWidget, reason: '$e');
        expect(await store.open(), isNotNull, reason: '$e');
        await t.pumpWidget(const SizedBox());
      }
    });

    test('store: one open send; a different key is refused, the same key is fine, an unreadable record throws instead of reading as empty', () async {
      final mem = MemorySecretStore();
      final s = _pend(mem);
      expect(await s.open(), isNull);
      const a = OnchainPending(key: 'k1', address: _addr, sats: 5000);
      await s.reserve(a);
      await s.reserve(a);
      expect((await s.open())!.sats, 5000);
      await expectLater(s.reserve(const OnchainPending(key: 'k2', address: _addr, sats: 1)), throwsStateError);
      expect((await s.open())!.key, 'k1');
      mem.map['pending.onchain'] = '{not json';
      await expectLater(s.open(), throwsA(anything));
      await s.clear();
      expect(await s.open(), isNull);
    });

    test('openOnchainSend: found clears, not found keeps, none is none', () async {
      final s = _pend();
      final sdk = _FakeSdk(_quote());
      expect(await openOnchainSend(s, sdk), isNull);
      await s.reserve(const OnchainPending(key: 'k1', address: _addr, sats: 5000));
      expect((await openOnchainSend(s, sdk))!.key, 'k1');
      expect(await s.open(), isNotNull);
    });

    test('sendNeverStarted: only the up-front SDK refusals', () {
      expect(sendNeverStarted(const breez.SdkError.invalidInput('x')), isTrue);
      expect(sendNeverStarted(const breez.SdkError.insufficientFunds()), isTrue);
      expect(sendNeverStarted(const breez.SdkError.invalidUuid('x')), isTrue);
      expect(sendNeverStarted(const breez.SdkError.networkError('x')), isFalse);
      expect(sendNeverStarted(const breez.SdkError.storageError('x')), isFalse);
      expect(sendNeverStarted(StateError('x')), isFalse);
    });

    testWidgets('L5: a double tap on a claim retry asks once and claims once', (t) async {
      final claimed = <String>[];
      final gate = Completer<void>();
      final dep = _dep(err: breez.DepositClaimError.maxDepositClaimFeeExceeded(tx: 't', vout: 0, requiredFeeSats: BigInt.from(900)));
      final a = OnchainApi(
        address: () async => _addr,
        deposits: () async => [dep],
        claim: (d, {int? maxFeeSats}) async {
          claimed.add(d.txid);
          await gate.future;
        },
        receivedDeposits: () async => {},
      );
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: OnchainReceiveView(api: a, onReceived: (_) {})))));
      await t.pumpAndSettle();
      final btn = find.text('Resgatar pagando 900 sats');
      await t.tap(btn);
      await t.pumpAndSettle();
      expect(find.text('Pagar a taxa de rede?'), findsOneWidget);
      await t.tap(find.byKey(const Key('claim-fee-confirm')));
      await t.pumpAndSettle();
      expect(claimed, hasLength(1));
      await t.tap(btn); // second tap while the claim is still running
      await t.pumpAndSettle();
      expect(find.text('Pagar a taxa de rede?'), findsNothing, reason: 'no second dialog');
      expect(claimed, hasLength(1));
      gate.complete();
      await t.pumpAndSettle();
      expect(claimed, hasLength(1));
      await t.pumpWidget(const SizedBox());
    });
  });
}

class _FailingWrites extends MemorySecretStore {
  @override
  Future<void> write(String name, String value) async => throw StateError('disk full');
}
