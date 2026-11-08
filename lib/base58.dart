import 'dart:typed_data';

const _alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

String base58Encode(List<int> bytes) {
  var n = BigInt.zero;
  for (final b in bytes) {
    n = (n << 8) | BigInt.from(b);
  }
  final out = StringBuffer();
  final b58 = BigInt.from(58);
  while (n > BigInt.zero) {
    out.write(_alphabet[(n % b58).toInt()]);
    n = n ~/ b58;
  }
  final zeros = bytes.takeWhile((b) => b == 0).length;
  return '1' * zeros + out.toString().split('').reversed.join();
}

/// Inverse of [base58Encode]; leading '1's are leading zero bytes. Throws [FormatException] on a character outside the alphabet.
Uint8List base58Decode(String s) {
  var n = BigInt.zero;
  final b58 = BigInt.from(58);
  for (final c in s.codeUnits) {
    final i = _alphabet.indexOf(String.fromCharCode(c));
    if (i < 0) throw const FormatException('base58: caractere inválido');
    n = n * b58 + BigInt.from(i);
  }
  var h = n == BigInt.zero ? '' : n.toRadixString(16);
  if (h.length.isOdd) h = '0$h';
  final zeros = s.codeUnits.takeWhile((c) => c == 0x31).length;
  return Uint8List.fromList([...List.filled(zeros, 0), for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
}
