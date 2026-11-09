import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/i18n.dart';
import 'package:wallet/stable_send.dart' show fmtUnits;

final _arg = RegExp(r'\{([a-zA-Z]\w*)\}');
Set<String> _args(String s) => {for (final m in _arg.allMatches(s)) m.group(1)!};

void main() {
  tearDown(() => lang.value = Lang.pt);

  test('every text exists in the three languages, is not empty and carries the same {arguments} in all of them', () {
    expect(strings, isNotEmpty);
    strings.forEach((key, t) {
      for (final s in [t.$1, t.$2, t.$3]) {
        expect(s.trim(), isNotEmpty, reason: key);
      }
      expect(_args(t.$2), _args(t.$1), reason: '$key: en vs pt arguments');
      expect(_args(t.$3), _args(t.$1), reason: '$key: es vs pt arguments');
    });
  });

  test('tr gives the text of the language in use and fills the arguments', () {
    expect(tr('lang.title'), 'Idioma');
    lang.value = Lang.en;
    expect(tr('lang.title'), 'Language');
    lang.value = Lang.es;
    expect(tr('lang.title'), 'Idioma');
  });

  test('amounts read with a dot in English and a comma in Portuguese and Spanish, whatever the language the amount was typed in', () {
    final v = BigInt.from(4500000);
    expect(fmtUnits(v, 6), '4,50');
    lang.value = Lang.en;
    expect(fmtUnits(v, 6), '4.50');
    lang.value = Lang.es;
    expect(fmtUnits(v, 6), '4,50');
    expect(decimalSeparator(), ',');
  });

  test('the phone language: pt and es are ours, English and anything else is English', () {
    expect(langForPhone('pt'), Lang.pt);
    expect(langForPhone('es'), Lang.es);
    expect(langForPhone('en'), Lang.en);
    for (final c in ['de', 'fr', 'ja', '', null]) {
      expect(langForPhone(c), Lang.en, reason: '$c');
    }
  });

  group('saved choice', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('langprefs'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('nothing saved follows the phone; a saved choice wins over the phone', () async {
      final p = LangPrefs(dir);
      expect(await p.load(phone: 'es'), Lang.es);
      expect(await p.load(phone: 'ja'), Lang.en);
      await p.save(Lang.pt);
      expect(await p.load(phone: 'es'), Lang.pt);
      await p.save(Lang.en);
      expect(await LangPrefs(dir).load(phone: 'pt'), Lang.en, reason: 'read again by another instance, as after a restart');
    });

    test('a file that is not a language of ours is ignored, and a folder that does not exist yet is created on save', () async {
      File('${dir.path}/language').writeAsStringSync('klingon');
      expect(await LangPrefs(dir).load(phone: 'es'), Lang.es);
      final nested = Directory('${dir.path}/a/b');
      await LangPrefs(nested).save(Lang.es);
      expect(await LangPrefs(nested).load(phone: 'en'), Lang.es);
    });
  });

  testWidgets('setLang repaints everything, even a const widget that reads tr() in its build', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: _Const())));
    expect(find.text('Idioma'), findsOneWidget);
    setLang(Lang.en);
    await t.pump();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Idioma'), findsNothing);
    setLang(Lang.en); // the same language again: nothing to do
    await t.pump();
    expect(find.text('Language'), findsOneWidget);
  });
}

class _Const extends StatelessWidget {
  const _Const();
  @override
  Widget build(BuildContext context) => Text(tr('lang.title'));
}
