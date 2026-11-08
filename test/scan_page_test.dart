import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/scan_page.dart';
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/qrcode.dart';
import 'package:zxing_lib/zxing.dart';

/// A camera-like luminance frame of a QR code: `scale` pixels per module, a quiet zone, rows padded to `stride`.
({Uint8List luma, int stride, int width, int height}) frameOf(String text, {int scale = 4, int pad = 0, bool invert = false}) {
  final m = QRCodeWriter().encode(text, BarcodeFormat.qrCode, 0, 0, EncodeHint(margin: 4));
  final w = m.width * scale, h = m.height * scale, stride = w + pad;
  final luma = Uint8List(stride * h)..fillRange(0, stride * h, 7); // padding bytes are junk, not white
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dark = m.get(x ~/ scale, y ~/ scale);
      luma[y * stride + x] = (dark != invert) ? 0 : 255;
    }
  }
  return (luma: luma, stride: stride, width: w, height: h);
}

String? read(({Uint8List luma, int stride, int width, int height}) f) => decodeQr(f.luma, f.stride, f.width, f.height);

/// Renders a [QRCode] built from raw bits (same wire format as [frameOf]): shared by the hand-built frames below,
/// all of which construct bit streams zxing_lib's own writer cannot produce (no structured-append, no malformed
/// content), the way a corrupt or multi-part real-world code would carry them.
({Uint8List luma, int stride, int width, int height}) _rasterOf(BitArray bits, Version version, ErrorCorrectionLevel ecLevel, {int scale = 4}) {
  final ecBlocks = version.getECBlocksForLevel(ecLevel);
  final numDataBytes = version.totalCodewords - ecBlocks.totalECCodewords;
  Encoder.terminateBits(numDataBytes, bits);
  final finalBits = Encoder.interleaveWithECBytes(bits, version.totalCodewords, numDataBytes, ecBlocks.numBlocks);

  final dimension = version.dimensionForVersion;
  final matrix = ByteMatrix(dimension, dimension);
  const maskPattern = 0; // any valid mask (0-7) decodes correctly; only affects how camera-friendly a real code looks
  MatrixUtil.buildMatrix(finalBits, ecLevel, version, maskPattern, matrix);
  final code = QRCode(mode: Mode.byte, ecLevel: ecLevel, version: version, maskPattern: maskPattern, matrix: matrix);

  final m = QRCodeWriter.renderResult(code, 0, 0, 4);
  final w = m.width * scale, h = m.height * scale;
  final luma = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      luma[y * w + x] = m.get(x ~/ scale, y ~/ scale) ? 0 : 255;
    }
  }
  return (luma: luma, stride: w, width: w, height: h);
}

final _smallVersion = Version.getVersionForNumber(5); // small, fixed: plenty of room for every frame below
const _ecLevel = ErrorCorrectionLevel.L;

/// A well-formed, single-segment byte-mode frame built through the same hand-rolled `_rasterOf` path as the
/// malformed frames below (no structured-append, no invalid mode/charset). Decoding this one to its own text is
/// the positive control: it proves the raster pipeline itself can succeed, so a null result from a sibling frame
/// below is actually caused by that frame's malformed content, not by `_rasterOf` producing an undecodable image.
({Uint8List luma, int stride, int width, int height}) plainByteFrameOf(String text, {int scale = 4}) {
  final bits = BitArray();
  final dataBits = BitArray();
  Encoder.appendBytes(text, Mode.byte, dataBits, utf8);
  Encoder.appendModeInfo(Mode.byte, bits);
  Encoder.appendLengthInfo(dataBits.sizeInBytes, _smallVersion, Mode.byte, bits);
  bits.appendBitArray(dataBits);
  return _rasterOf(bits, _smallVersion, _ecLevel, scale: scale);
}

/// A frame holding only ONE piece of a multi-part QR code: a STRUCTURED_APPEND mode segment ahead of the payload,
/// the way a real split code would carry it.
({Uint8List luma, int stride, int width, int height}) structuredAppendFrameOf(String text, {int scale = 4}) {
  final bits = BitArray();
  Encoder.appendModeInfo(Mode.structuredAppend, bits);
  bits.appendBits(0x12, 8); // symbol sequence (position/count): any value, just needs to be present
  bits.appendBits(0x56, 8); // parity: any value, same reason

  final dataBits = BitArray();
  Encoder.appendBytes(text, Mode.byte, dataBits, utf8);
  Encoder.appendModeInfo(Mode.byte, bits);
  Encoder.appendLengthInfo(dataBits.sizeInBytes, _smallVersion, Mode.byte, bits);
  bits.appendBitArray(dataBits);
  return _rasterOf(bits, _smallVersion, _ecLevel, scale: scale);
}

/// A frame whose mode header is a value the QR spec reserves (6): zxing_lib's `Mode.values[6]` is `null`, and the
/// decoder's `Mode.values[bits.readBits(4)]!` throws a TypeError on it. Models "an unusual mode value" from a
/// corrupt or non-conformant code.
({Uint8List luma, int stride, int width, int height}) invalidModeFrameOf({int scale = 4}) {
  final bits = BitArray()..appendBits(6, 4);
  return _rasterOf(bits, _smallVersion, _ecLevel, scale: scale);
}

/// A byte-mode frame whose payload is not valid UTF-8 (a lone continuation byte, 0x80, with no lead byte): an ECI
/// segment pins the charset to UTF-8 first (without it, the library GUESSES a charset from the bytes and a single
/// stray byte decodes cleanly as Latin-1), so the decoder's `encoding.decode(readBytes)` is a real `utf8.decode`,
/// which throws FormatException on this input. Models "text decoding failed".
({Uint8List luma, int stride, int width, int height}) invalidUtf8FrameOf({int scale = 4}) {
  final bits = BitArray()
    ..appendBits(Mode.eci.bits, 4)
    ..appendBits(26, 8); // ECI 26 = UTF-8 (CharacterSetECI.UTF8.value)
  Encoder.appendModeInfo(Mode.byte, bits);
  Encoder.appendLengthInfo(1, _smallVersion, Mode.byte, bits);
  bits.appendBits(0x80, 8);
  return _rasterOf(bits, _smallVersion, _ecLevel, scale: scale);
}

void main() {
  const payloads = {
    'address': 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
    'bip21': 'bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.00007&label=IBIRAPAY',
    'bolt11': 'lnbc20u1pnx3k9qpp5qyr7q8hjkc9fw2zvx6f8l0m5n3tq4u5v6w7e8r9t0y1u2i3o4p5sdqqcqzzsxqyz5vqsp5x9z8y7w6v5u4t3s2r1q0p9o8n7m6l5k4j3h2g1f0e9d8c7b6a5q9qxpqysgqx7w6v5u4t3s2r1q0p9o8n7m6l5k4j3h2g1f0e9d8c7b6a5z4y3x2w1v0u9t8s7r6q5p4o3n2m1l0k9j8h7g6f5e4d3c2b1a',
    'lnurl': 'LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEFCV5MKVV34X5EKZD3EV56NYD3HXQURZEPEXEJXXEPNXSCRVWFNV9NXZCN9XQ6XVNZZRZ2D',
    'long lnurl on a 1080p-ish frame': 'LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEFCV5MKVV34X5EKZD3EV56NYD3HXQURZEPEXEJXXEPNXSCRVWFNV9NXZCN9XQ6XVNZZRZ2D0000',
  };

  group('decodeQr', () {
    for (final e in payloads.entries) {
      test('reads ${e.key}', () => expect(read(frameOf(e.value)), e.value));
    }
    test('rows wider than the image (the camera stride) are handled', () {
      const t = 'lightning:LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEFCV5MKVV34X5EKZD3EV56NYD3HXQURZEPEXEJXXEPNXSCRVWFNV9NXZCN9XQ6XVNZZRZ2D';
      expect(read(frameOf(t, scale: 3, pad: 37)), t);
    });
    test('a frame with no QR code is null, never an exception', () {
      expect(decodeQr(Uint8List(640 * 480)..fillRange(0, 640 * 480, 255), 640, 640, 480), isNull);
      final noise = Uint8List(640 * 480);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = (i * 2654435761 >> 7) & 255;
      }
      expect(decodeQr(noise, 640, 640, 480), isNull);
    });
    test('a lying frame size is null, never an exception', () {
      expect(decodeQr(Uint8List(10), 640, 640, 480), isNull);
    });
    test('MED1: a QR shown light-on-dark (inverted), like a dark-theme wallet or POS, still reads', () {
      expect(read(frameOf('lightning:lnbc1...inverted', invert: true)), 'lightning:lnbc1...inverted');
    });
    test('MED2: the hand-built _rasterOf path itself can decode (positive control for the three tests below)', () {
      expect(read(plainByteFrameOf('control')), 'control');
    });
    test('LOW4: one piece of a multi-part code is null, not a truncated, still "valid" payload', () {
      expect(read(structuredAppendFrameOf('bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=1')), isNull);
    });
    test('LOW4: a mode value the library cannot interpret is null, not an uncaught TypeError', () {
      expect(read(invalidModeFrameOf()), isNull);
    });
    test('LOW4: a byte-mode payload that is not valid UTF-8 is null, not an uncaught FormatException', () {
      expect(read(invalidUtf8FrameOf()), isNull);
    });
  });

  group('ScanPage', () {
    Future<String?> run(WidgetTester t, FrameStream open, {bool settle = true}) async {
      String? result;
      var popped = false;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              result = await Navigator.of(ctx).push<String>(MaterialPageRoute(builder: (_) => ScanPage(openCamera: open)));
              popped = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pump();
      for (var i = 0; i < 20 && !popped; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump(const Duration(milliseconds: 300));
      }
      return result;
    }

    testWidgets('permission denied shows a plain message and a way back, no crash', (t) async {
      await t.pumpWidget(MaterialApp(home: ScanPage(openCamera: (_) async => throw CameraException('CameraAccessDenied', 'x'))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('scan-problem')), findsOneWidget);
      expect(find.textContaining('permissão'), findsOneWidget);
      expect(find.text('Voltar'), findsOneWidget);
    });

    testWidgets('any other camera failure says so, with the code', (t) async {
      await t.pumpWidget(MaterialApp(home: ScanPage(openCamera: (_) async => throw CameraException('CameraAccessRestricted2', 'x'))));
      await t.pumpAndSettle();
      expect(find.textContaining('permissão'), findsOneWidget); // restricted is a permission class too
      await t.pumpWidget(MaterialApp(home: ScanPage(key: UniqueKey(), openCamera: (_) async => throw CameraException('cameraInUse', 'x'))));
      await t.pumpAndSettle();
      expect(find.textContaining('cameraInUse'), findsOneWidget);
      await t.pumpWidget(MaterialApp(home: ScanPage(key: UniqueKey(), openCamera: (_) async => throw StateError('boom'))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('scan-problem')), findsOneWidget);
    });

    testWidgets('a frame with a QR code closes the page with its text, once', (t) async {
      const text = 'bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.00007';
      final f = frameOf(text);
      final got = await run(t, (onFrame) async {
        onFrame(Uint8List(100), 10, 10, 10); // junk first: skipped, not fatal
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          onFrame(f.luma, f.stride, f.width, f.height);
          onFrame(f.luma, f.stride, f.width, f.height); // a second one in flight is ignored
        });
      });
      expect(got, text);
    });
  });
}

