import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/pending_sends.dart';
import 'package:wallet/pending_sheet.dart';
import 'package:wallet/stable_send.dart';
import 'package:wallet/theme.dart';

import 'stable_vectors.dart';

PendingSend _poly({Duration age = const Duration(minutes: 5)}) => PendingSend(
  id: '0xabc',
  net: 'polygon',
  symbol: 'USDT',
  amount: '1500000',
  to: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
  from: vEvmAddress,
  createdMs: DateTime.now().millisecondsSinceEpoch - age.inMilliseconds,
  nonce: 7,
  tip: '30000000000',
  maxFee: '100000000000',
);

PendingSend _sol({Duration age = const Duration(minutes: 5)}) => PendingSend(
  id: 'solsig',
  net: 'solana',
  symbol: 'USDC',
  amount: '2500000',
  to: vSolRecipient,
  from: vSolAddress,
  createdMs: DateTime.now().millisecondsSinceEpoch - age.inMilliseconds,
  lastValid: 1000,
);

/// A Polygon node where the original never mined; sending the cancelling transaction uses the nonce.
class _Node {
  _Node({this.receipt, this.pol, this.cancelWins = true});
  final Object? receipt;
  final BigInt? pol;
  final bool cancelWins;
  final sent = <String>[];
  var nonceUsed = false;
  Future<dynamic> call(List<String> nodes, String m, List<dynamic> p) async {
    switch (m) {
      case 'eth_getTransactionReceipt':
        return receipt;
      case 'eth_getTransactionByHash':
        return null;
      case 'eth_getTransactionCount':
        return nonceUsed ? '0x8' : '0x7';
      case 'eth_getBlockByNumber':
        return p[0] == 'finalized' ? {'number': '0x64'} : {'baseFeePerGas': '0x${(BigInt.from(30) * BigInt.from(1000000000)).toRadixString(16)}'};
      case 'eth_maxPriorityFeePerGas':
        return '0x1';
      case 'eth_getBalance':
        return '0x${(pol ?? BigInt.from(10).pow(18)).toRadixString(16)}';
      case 'eth_sendRawTransaction':
        sent.add(p[0] as String);
        nonceUsed = cancelWins;
        return '0xcancel';
    }
    throw UnimplementedError(m);
  }
}

/// Opens the sheet from a button and keeps what it pops with.
Future<({MemoryPendingStore store, List<String?> told, _Node node})> _open(WidgetTester t, PendingSend record, {_Node? node, Future<bool> Function()? confirmPin}) async {
  t.view.physicalSize = const Size(800, 2600); // the whole sheet fits, so every button can be tapped
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final n = node ?? _Node();
  final store = MemoryPendingStore()..items.add(record);
  final told = <String?>[];
  final sender = StableSender(store: store, call: n.call, pollEvery: const Duration(milliseconds: 2), maxWait: const Duration(milliseconds: 60));
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => told.add(await showAppSheet<String>(ctx, (_) => PendingSheet(record: record, sender: sender, words: vMnemonic.split(' '), confirmPin: confirmPin ?? () async => true))),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
  return (store: store, told: told, node: n);
}

void main() {
  testWidgets('Polygon: shows what the send was, warns not to send again, offers a cancel and no free discard', (t) async {
    await _open(t, _poly());
    expect(find.text('Envio em aberto'), findsOneWidget);
    expect(find.text('1,50 USDT'), findsOneWidget);
    expect(find.text('Polygon'), findsOneWidget);
    expect(find.textContaining('Não envie de novo'), findsOneWidget);
    expect(find.text('Cancelar envio'), findsOneWidget);
    expect(find.textContaining('Descartar'), findsNothing);
  });

  testWidgets('Solana, over an hour old and unsettled: a discard that says to check Solscan first, two taps', (t) async {
    final o = await _open(t, _sol(age: const Duration(hours: 3)));
    expect(find.textContaining('mais de 1 hora'), findsOneWidget);
    expect(find.text('Cancelar envio'), findsNothing);
    await t.tap(find.text('Descartar (conferi no Solscan)'));
    await t.pumpAndSettle();
    expect(o.store.items, hasLength(1)); // one tap does nothing
    expect(find.textContaining('Toque de novo'), findsOneWidget);
    await t.tap(find.textContaining('Toque de novo'));
    await t.pumpAndSettle();
    expect(o.store.items, isEmpty);
    expect(o.told, ['Envio descartado do registro']);
  });

  testWidgets('Polygon, over an hour old and unsettled: no cancel, a discard that says to check Polygonscan first, two taps', (t) async {
    final o = await _open(t, _poly(age: const Duration(hours: 4)));
    expect(find.text('Cancelar envio'), findsNothing);
    expect(find.textContaining('mais de 1 hora'), findsOneWidget);
    await t.tap(find.text('Descartar (conferi no Polygonscan)'));
    await t.pumpAndSettle();
    expect(o.store.items, hasLength(1));
    await t.tap(find.textContaining('Toque de novo'));
    await t.pumpAndSettle();
    expect(o.store.items, isEmpty);
    expect(o.told, ['Envio descartado do registro']);
  });

  testWidgets('Solana: nothing to cancel or discard, it settles by itself', (t) async {
    await _open(t, _sol());
    expect(find.text('Cancelar envio'), findsNothing);
    expect(find.textContaining('Descartar'), findsNothing);
    expect(find.textContaining('A Solana resolve esse envio sozinha'), findsOneWidget);
  });

  testWidgets('"Conferir agora" settles a confirmed send: told, forgotten, closed', (t) async {
    final o = await _open(t, _poly(), node: _Node(receipt: {'status': '0x1', 'blockNumber': '0x64'}));
    await t.tap(find.text('Conferir agora'));
    await t.pumpAndSettle();
    expect(o.told, ['Envio de 1,50 USDT: confirmado']);
    expect(o.store.items, isEmpty);
    expect(find.text('Envio em aberto'), findsNothing);
  });

  testWidgets('"Conferir agora" on a receipt that is not final yet keeps it open', (t) async {
    final o = await _open(t, _poly(), node: _Node(receipt: {'status': '0x1', 'blockNumber': '0x65'}));
    await t.tap(find.text('Conferir agora'));
    await t.pumpAndSettle();
    expect(find.text('Envio em aberto'), findsOneWidget);
    expect(find.textContaining('Ainda não dá para saber'), findsOneWidget);
    expect(o.store.items, hasLength(1));
  });

  testWidgets('cancelling takes two taps; the first sends nothing, the second sends ONE replacement and settles it', (t) async {
    final o = await _open(t, _poly());
    await t.tap(find.text('Cancelar envio'));
    await t.pumpAndSettle();
    expect(find.text('Toque de novo para cancelar o envio'), findsOneWidget);
    expect(o.node.sent, isEmpty);
    expect(o.store.items, hasLength(1));
    await t.tap(find.text('Toque de novo para cancelar o envio'));
    await t.pumpAndSettle();
    expect(o.node.sent, hasLength(1));
    expect(o.store.items, isEmpty);
    expect(o.told.single, contains('cancelado: não entrou na rede'));
  });

  testWidgets('a cancel the network has not confirmed yet keeps the record and says so', (t) async {
    final o = await _open(t, _poly(), node: _Node(cancelWins: false));
    await t.tap(find.text('Cancelar envio'));
    await t.pumpAndSettle();
    await t.tap(find.text('Toque de novo para cancelar o envio'));
    await t.pumpAndSettle();
    expect(o.node.sent, hasLength(1));
    expect(o.store.items, hasLength(1));
    expect(find.textContaining('Cancelamento enviado, mas a rede ainda não o confirmou'), findsOneWidget);
  });

  testWidgets('a cancel without the POL to pay for it says so and sends nothing', (t) async {
    final o = await _open(t, _poly(), node: _Node(pol: BigInt.from(1000)));
    await t.tap(find.text('Cancelar envio'));
    await t.pumpAndSettle();
    await t.tap(find.text('Toque de novo para cancelar o envio'));
    await t.pumpAndSettle();
    expect(find.textContaining('POL insuficiente para cancelar'), findsOneWidget);
    expect(o.node.sent, isEmpty);
    expect(o.store.items, hasLength(1));
  });

  testWidgets('closing leaves the record alone', (t) async {
    final o = await _open(t, _poly());
    await t.tap(find.text('Fechar'));
    await t.pumpAndSettle();
    expect(o.store.items, hasLength(1));
    expect(o.told, [null]);
  });

  testWidgets('the PIN is asked right before the cancelling transaction is signed: refused sends nothing and the button resets', (t) async {
    var allow = false;
    var asked = 0;
    final o = await _open(t, _poly(), confirmPin: () async {
      asked++;
      return allow;
    });
    await t.tap(find.text('Cancelar envio'));
    await t.pumpAndSettle();
    expect(asked, 0); // the first tap only arms it
    await t.tap(find.text('Toque de novo para cancelar o envio'));
    await t.pumpAndSettle();
    expect(asked, 1);
    expect(o.node.sent, isEmpty);
    expect(o.store.items, hasLength(1));
    expect(find.text('Cancelar envio'), findsOneWidget); // back to the start, nothing signed
    allow = true;
    await t.tap(find.text('Cancelar envio'));
    await t.pumpAndSettle();
    await t.tap(find.text('Toque de novo para cancelar o envio'));
    await t.pumpAndSettle();
    expect(asked, 2);
    expect(o.node.sent, hasLength(1));
  });
}
