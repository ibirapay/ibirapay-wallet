import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/chain_balances.dart';
import 'package:wallet/pending_sends.dart';
import 'package:wallet/stable_send.dart';
import 'package:wallet/theme.dart';
import 'package:wallet/stable_send_sheet.dart';

import 'stable_vectors.dart';

const _bob = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';

/// A Polygon node that answers the happy path; [receipt] decides how the send ends.
class _Node {
  _Node({this.receipt});
  final Object? receipt;
  final calls = <String>[];
  Future<dynamic> call(List<String> nodes, String m, List<dynamic> p) async {
    calls.add(m);
    switch (m) {
      case 'eth_chainId':
        return '0x89';
      case 'eth_call':
        return '0x${(5000000).toRadixString(16).padLeft(64, '0')}';
      case 'eth_getBalance':
        return '0x${(BigInt.from(10).pow(19)).toRadixString(16)}';
      case 'eth_getBlockByNumber':
        if (p[0] == 'finalized') return {'number': '0x64'};
        return {'baseFeePerGas': '0x${(BigInt.from(30) * BigInt.from(1000000000)).toRadixString(16)}'};
      case 'eth_maxPriorityFeePerGas':
        return '0x1';
      case 'eth_estimateGas':
        return '0xfde8';
      case 'eth_getTransactionCount':
        return '0x0';
      case 'eth_sendRawTransaction':
        return '0xhash';
      case 'eth_getTransactionReceipt':
        return receipt;
    }
    throw UnimplementedError(m);
  }
}

Widget _app(_Node node, {Future<bool> Function()? confirmPin}) => MaterialApp(
  theme: appTheme(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: StableSendSheet(
        net: Net.polygon,
        from: vEvmAddress,
        words: vMnemonic.split(' '),
        balances: [StableBalance('Polygon', 'USDT', BigInt.from(5000000)), StableBalance('Polygon', 'USDC', BigInt.zero)],
        confirmPin: confirmPin ?? () async => true,
        sender: StableSender(store: MemoryPendingStore(), call: node.call, pollEvery: const Duration(milliseconds: 2), maxWait: const Duration(milliseconds: 30)),
      ),
    ),
  ),
);

Future<void> _fill(WidgetTester t, {required String to, required String amount}) async {
  await t.enterText(find.byType(TextField).at(0), to);
  await t.enterText(find.byType(TextField).at(1), amount);
}

void main() {
  testWidgets('form: the network is named, the balance is shown, USDC.e is hidden when not held', (t) async {
    await t.pumpWidget(_app(_Node()));
    expect(find.text('Rede Polygon'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'USDT'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'USDC'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'USDC.e'), findsNothing);
    expect(find.text('Saldo: 5,00 USDT'), findsOneWidget);
    await t.tap(find.text('Tudo'));
    await t.pump();
    expect(find.widgetWithText(TextField, '5,000000'), findsOneWidget);
  });

  testWidgets('an ambiguous amount is refused on the form and never reaches the network', (t) async {
    final node = _Node();
    await t.pumpWidget(_app(node));
    await _fill(t, to: _bob, amount: '1.000');
    await t.tap(find.text('Continuar'));
    await t.pump();
    expect(find.textContaining('ambíguo'), findsOneWidget);
    expect(node.calls, isEmpty);
  });

  testWidgets('confirm names the network, the exact amount and the whole address; sending ends confirmed', (t) async {
    final node = _Node(receipt: {'status': '0x1', 'blockNumber': '0x64'});
    await t.pumpWidget(_app(node));
    await _fill(t, to: _bob.toLowerCase(), amount: '1,5');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    expect(find.text('Você vai enviar'), findsOneWidget);
    expect(find.text('1,50 USDT'), findsOneWidget);
    expect(find.text('Rede Polygon'), findsOneWidget);
    // the recipient comes back checksummed and complete (SelectableText.rich keeps the spans in one widget)
    expect(find.textContaining(_bob.substring(6, 30), findRichText: true), findsOneWidget);
    expect(node.calls.contains('eth_sendRawTransaction'), isFalse); // nothing is sent before the button
    await t.tap(find.text('Enviar'));
    await t.pumpAndSettle();
    expect(find.text('Enviado'), findsOneWidget);
    expect(node.calls.where((c) => c == 'eth_sendRawTransaction'), hasLength(1));
  });

  testWidgets('an unconfirmed send tells the user NOT to send again', (t) async {
    await t.pumpWidget(_app(_Node()));
    await _fill(t, to: _bob, amount: '1');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Enviar'));
    await t.pumpAndSettle();
    expect(find.text('Enviado, ainda sem confirmação'), findsOneWidget);
    expect(find.textContaining('NÃO envie de novo'), findsOneWidget);
    expect(find.text('Copiar link do explorador'), findsOneWidget);
  });

  testWidgets('a refusal from the quote is shown on the form with its own reason', (t) async {
    await t.pumpWidget(_app(_Node()));
    await _fill(t, to: 'ethereum:$_bob@1', amount: '1');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    expect(find.textContaining('outra rede'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget); // still on the form
  });

  testWidgets('the PIN is asked before anything is signed: refused keeps the confirm step and sends nothing; accepted sends once', (t) async {
    final node = _Node(receipt: {'status': '0x1', 'blockNumber': '0x64'});
    var allow = false;
    var asked = 0;
    await t.pumpWidget(_app(node, confirmPin: () async {
      asked++;
      return allow;
    }));
    await _fill(t, to: _bob, amount: '1');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Enviar'));
    await t.pumpAndSettle();
    expect(asked, 1);
    expect(node.calls.contains('eth_sendRawTransaction'), isFalse);
    expect(find.text('Você vai enviar'), findsOneWidget); // still on the confirm step
    allow = true;
    await t.tap(find.text('Enviar'));
    await t.pumpAndSettle();
    expect(node.calls.where((c) => c == 'eth_sendRawTransaction'), hasLength(1));
    expect(find.text('Enviado'), findsOneWidget);
  });

  testWidgets('tapping Enviar twice while the PIN is being asked sends once and asks once', (t) async {
    final node = _Node(receipt: {'status': '0x1', 'blockNumber': '0x64'});
    var asked = 0;
    await t.pumpWidget(_app(node, confirmPin: () async {
      asked++;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return true;
    }));
    await _fill(t, to: _bob, amount: '1');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Enviar'));
    await t.pump(const Duration(milliseconds: 10));
    await t.tap(find.text('Enviar'), warnIfMissed: false);
    await t.pumpAndSettle(const Duration(milliseconds: 50));
    expect(asked, 1);
    expect(node.calls.where((c) => c == 'eth_sendRawTransaction'), hasLength(1));
  });
}
