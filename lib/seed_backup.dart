// The wallet backup: the 12 words written on paper, plus a passphrase-encrypted file in the device's shared
// Documents/IBIRAPAY (it outlives an uninstall, unlike the Keystore and the app's own dirs).
// Same file format and AAD as the PDV's one-wallet backup, so a PDV wallet file restores here.
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import 'backup_crypto.dart';

const walletBackupId = 'wallet';
const _channel = MethodChannel('ibirapay/seed_backup');

/// [count] distinct word positions (0-based, ascending) to retype from the paper.
List<int> checkPositions(int words, {int count = 3, Random? random}) {
  final r = random ?? Random.secure();
  final picked = <int>{};
  while (picked.length < count) {
    picked.add(r.nextInt(words));
  }
  return picked.toList()..sort();
}

/// The retyped words match the seed at [positions], every one of them.
bool checkWords(List<String> seed, List<int> positions, List<String> typed) {
  if (typed.length != positions.length) return false;
  for (var i = 0; i < positions.length; i++) {
    if (typed[i].trim().toLowerCase() != seed[positions[i]]) return false;
  }
  return true;
}

String backupFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'ibirapay-$walletBackupId-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.ibirapay';
}

/// Documents/IBIRAPAY: Android's shared Documents (Android 11+ lets an app create files there without a permission).
// ponytail: Android 10 and older would need WRITE_EXTERNAL_STORAGE; the write fails there and the backup is not made
Future<Directory> backupDir() async =>
    Directory('${await _channel.invokeMethod<String>('documentsDir')}/IBIRAPAY');

/// Encrypts [words], writes a new file in [dir] (never over an existing one), then reads it back and decrypts it: the
/// path comes back only when the file on disk restores the words. A file that does not is deleted.
Future<String> writeWalletBackup(
  List<String> words,
  String passphrase, {
  required Directory dir,
  DateTime? now,
  Argon2Params params = Argon2Params.standard,
  Future<void> Function(File, String)? write, // tests: a disk that stores something else
}) async {
  final blob = await encryptBackup(words, passphrase, shopId: walletBackupId, params: params);
  await dir.create(recursive: true);
  final f = File('${dir.path}/${backupFileName(now ?? DateTime.now())}');
  await f.create(exclusive: true);
  await (write ?? (f, s) => f.writeAsString(s, flush: true))(f, blob);
  try {
    final back = await decryptBackup(await f.readAsString(), passphrase, shopId: walletBackupId);
    if (back.join(' ') != words.join(' ')) throw BackupError('o arquivo gravado devolve outra seed');
  } catch (e) {
    await f.delete();
    throw BackupError('o arquivo gravado não devolve a seed ($e): use outra pasta ou tente de novo');
  }
  return f.path;
}

Future<List<String>> readWalletBackup(String json, String passphrase) =>
    decryptBackup(json, passphrase, shopId: walletBackupId);

/// The backups this install can list in [dir], newest first. After a reinstall Android hides them: use the picker.
Future<List<File>> listWalletBackups(Directory dir) async {
  try {
    final files = await dir.list().where((e) => e is File && e.path.endsWith('.ibirapay')).cast<File>().toList();
    return files..sort((a, b) => b.path.compareTo(a.path));
  } on FileSystemException {
    return [];
  }
}

/// Android's file picker: the bytes of the chosen file, or null when nothing was chosen.
Future<Uint8List?> pickBackupFile() => _channel.invokeMethod<Uint8List>('pick');

/// No screenshot, screen recording or recents thumbnail while the words are on screen.
Future<void> secureScreen(bool on) => _channel.invokeMethod<void>('secure', on);
