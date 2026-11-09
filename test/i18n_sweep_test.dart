// Fails when a Portuguese sentence is typed straight into lib/ instead of going through tr('key') and lib/i18n_strings.dart.
// Developer-facing exceptions (StateError, FormatException, ArgumentError, WalletError, BackupError) and toString() are not shown
// as a screen text on their own and are left in Portuguese; everything else must be translated.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _literal = RegExp(r"'([^'\\\n]|\\.)*'");
final _accent = RegExp('[áéíóúâêôãõçÁÉÍÓÚÂÊÔÃÕÇ]');
final _words = RegExp(r'\b(não|nada|você|para|erro|envio|envios|valor|saldo|taxa|carteira|palavras|endereço|rede|tente|digite|toque|confira|aguardando|enviar|receber|copiar|cancelar|voltar|fechar|concluir|descartar|continuar|colar)\b', caseSensitive: false);
// the app's name and the language's own name are never translated
// names that are the same in every language
const _names = {'Polygon', 'Solana', 'Bitcoin', 'Lightning', 'USDT', 'USDC', 'USDC.e', 'POL', 'SOL', 'IBIRAPAY', 'sats', 'Polygonscan', 'Solscan', 'IBIRAPAY Carteira'};
final _shownLiteral = RegExp(r"(label:|Text\(|hintText:|title:|content:|SheetTitle\()\s*(const )?'([A-Za-zÀ-ú][^'\\$]*)'");
const _neverTranslated = {"'IBIRAPAY Carteira'", "'Português'"};
final _devOnly = RegExp(r'throw (const )?(StateError|FormatException|ArgumentError|WalletError|BackupError)\(|String toString\(\)');

void main() {
  test('no Portuguese text is typed straight into lib/: every shown text goes through tr()', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('i18n_strings.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('import ') || line.trimLeft().startsWith('export ')) continue;
        if (_devOnly.hasMatch(line)) continue;
        for (final m in _literal.allMatches(line)) {
          final s = m.group(0)!;
          if (s.contains("tr('") || _neverTranslated.contains(s)) continue;
          if (_accent.hasMatch(s) || (s.contains(' ') && _words.hasMatch(s))) found.add('${f.path}:${i + 1}: $s');
        }
        // a word shown as a label or title with no space in it is still a text of the screen ("Colar", "Escanear")
        for (final m in _shownLiteral.allMatches(line)) {
          final word = m.group(3)!;
          if (!_names.contains(word) && !found.any((x) => x.startsWith('${f.path}:${i + 1}:'))) found.add('${f.path}:${i + 1}: \'$word\'');
        }
      }
    }
    expect(found, isEmpty, reason: 'move these into lib/i18n_strings.dart and call tr():\n${found.join('\n')}');
  });
}
