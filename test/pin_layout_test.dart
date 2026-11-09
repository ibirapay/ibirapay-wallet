import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/pin_pad.dart';
import 'package:wallet/theme.dart';

const _ids = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', 'ok'];

Future<void> _pump(WidgetTester t, Size size, {String? subtitle}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: appTheme(), home: Scaffold(body: SafeArea(child: PinPad(title: 'Digite o PIN', subtitle: subtitle, onSubmit: (_) async {})))));
}

Rect _r(WidgetTester t, String id) => t.getRect(find.byKey(Key('pin-$id')));

void main() {
  for (final size in const [Size(360, 640), Size(412, 915), Size(320, 480)]) {
    testWidgets('keys fill the screen inside a small frame on ${size.width.toInt()}x${size.height.toInt()}', (t) async {
      await _pump(t, size, subtitle: 'De 4 a 8 números. Você vai usá-lo para abrir o app, enviar e ver as 12 palavras.');
      expect(t.takeException(), isNull, reason: 'no overflow');
      final keys = [for (final id in _ids) _r(t, id)];
      for (final k in keys) {
        expect(k.left, greaterThanOrEqualTo(12), reason: 'left frame');
        expect(k.right, lessThanOrEqualTo(size.width - 12), reason: 'right frame');
        expect(k.bottom, lessThanOrEqualTo(size.height), reason: 'inside the screen');
        expect(k.width, closeTo(k.height, .01), reason: 'round');
      }
      // the pad is a block of 3 columns in the middle, not a thin strip
      expect(keys[2].right - keys[0].left, greaterThan(size.width * .5));
      // no two keys overlap
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          expect(keys[i].overlaps(keys[j]), isFalse, reason: '${_ids[i]} x ${_ids[j]}');
        }
      }
    });
  }

  testWidgets('on a tall phone the keys are bigger than the old 68 dp but not screen-filling, and every key still types', (t) async {
    await _pump(t, const Size(412, 915));
    expect(_r(t, '5').width, greaterThan(68));
    expect(_r(t, '5').width, lessThanOrEqualTo(88), reason: 'the full-screen pad was too big');
    await t.tap(find.byKey(const Key('pin-5')));
    await t.pump();
    final filled = find.descendant(of: find.byKey(const Key('pin-dots')), matching: find.byType(Container)).evaluate().map((e) => (e.widget as Container).decoration).whereType<BoxDecoration>().where((d) => d.color != Colors.transparent);
    expect(filled.length, 1);
  });
}
