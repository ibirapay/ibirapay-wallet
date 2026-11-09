// The app's languages: Portuguese, English and Spanish, chosen on the Carteira page. No codegen and no package: every text is one entry
// of [strings] with its three translations side by side, so a missing translation does not compile, and `tr` works anywhere (the send
// errors are born in logic code that has no BuildContext). The language lives in [lang]; [setLang] rebuilds the whole tree.
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'i18n_strings.dart';

export 'i18n_strings.dart';

enum Lang {
  pt('Português'),
  en('English'),
  es('Español');

  const Lang(this.label);

  /// The language's own name: it is never translated, so a person lost in the wrong language can still find theirs.
  final String label;
}

/// The language in use. Tests and a fresh process start in Portuguese; `main` sets the real one before the first frame.
final ValueNotifier<Lang> lang = ValueNotifier(Lang.pt);

String tr(String key, [Map<String, Object> args = const {}]) {
  final t = strings[key];
  assert(t != null, 'tr: no text for "$key"');
  if (t == null) return key;
  var s = switch (lang.value) {
    Lang.pt => t.$1,
    Lang.en => t.$2,
    Lang.es => t.$3,
  };
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  assert(!RegExp(r'\{[a-zA-Z]\w*\}').hasMatch(s), 'tr: "$key" has an argument that was not given: $s');
  return s;
}

/// A balance line that says it is still loading, in whichever language it was written.
bool isLoadingLine(String l) {
  final t = strings['bal.loading']!;
  return [t.$1, t.$2, t.$3].any((x) => l.endsWith(x.substring(x.indexOf('}') + 1)));
}

/// The decimal separator of amounts the user reads: a dot in English, a comma in Portuguese and Spanish. Typing accepts both.
String decimalSeparator() => lang.value == Lang.en ? '.' : ',';

/// The phone's language when it is one of ours, English for any other.
Lang langForPhone(String? code) => switch (code) {
  'pt' => Lang.pt,
  'es' => Lang.es,
  _ => Lang.en,
};

/// Changes the language and repaints everything. Marking every element dirty is what reaches `const` widgets, which a plain
/// rebuild of the parent skips (their widget object is identical), so their `tr(...)` would keep the old text.
void setLang(Lang l) {
  if (lang.value == l) return;
  lang.value = l;
  void dirty(Element e) {
    e.markNeedsBuild();
    e.visitChildren(dirty);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(dirty);
}

/// The saved choice: one small file in the app's data folder (not a secret). No file, or one that is not a language of ours,
/// means "follow the phone".
class LangPrefs {
  LangPrefs([this._dir]);
  final Directory? _dir;

  Future<File> _file() async => File('${(_dir ?? await getApplicationSupportDirectory()).path}/language');

  Future<Lang> load({String? phone}) async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final saved = (await f.readAsString()).trim();
        for (final l in Lang.values) {
          if (l.name == saved) return l;
        }
      }
    } catch (_) {
      // an unreadable file is the same as none: follow the phone
    }
    return langForPhone(phone ?? PlatformDispatcher.instance.locale.languageCode);
  }

  Future<void> save(Lang l) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(l.name, flush: true);
  }
}
