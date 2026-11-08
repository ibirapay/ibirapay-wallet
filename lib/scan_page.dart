// QR scanner: CameraX (the Flutter `camera` plugin, androidx) for frames and zxing_lib (pure Dart, Apache-2.0) to read them.
// No Google ML Kit and no Play Services: that is what lets the app into the official F-Droid.
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/zxing.dart';

import 'theme.dart';

/// Reads a QR code from the luminance (Y) plane of a camera frame: `bytesPerRow` is the row stride, which can be wider
/// than `width`. Returns the text, or null when the frame has no readable QR code (including a code the library
/// itself cannot parse, and one piece of a multi-part code, which would otherwise decode as a truncated payload).
/// Pure function, safe for an isolate.
String? decodeQr(Uint8List luma, int bytesPerRow, int width, int height) {
  try {
    final source = PlanarYUVLuminanceSource(luma, bytesPerRow, height, width: width, height: height);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    // QRCodeReader alone ignores alsoInverted (only MultiFormatReader honors it): without it a QR shown light-on-dark,
    // like a dark-theme wallet or POS, never scans.
    final result = MultiFormatReader().decode(
      bitmap,
      const DecodeHint(tryHarder: true, alsoInverted: true, possibleFormats: [BarcodeFormat.qrCode]),
    );
    if (result.resultMetadata?.containsKey(ResultMetadataType.structuredAppendSequence) ?? false) {
      return null; // one piece of a split code: on its own it is a truncated, still well-formed payload
    }
    return result.text;
  } on ReaderException {
    return null; // NotFound, Checksum and Format errors all mean "not in this frame"
  } on ArgumentError {
    return null;
  } on TypeError {
    return null; // a code the library cannot interpret (an unusual mode or character set)
  } on FormatException {
    return null; // text decoding failed
  }
}

// What the page needs from the camera, so a test can drive it without hardware.
typedef FrameStream = Future<void> Function(void Function(Uint8List luma, int bytesPerRow, int width, int height) onFrame);

/// One frame in, the decoded text (or null) out. Test hook: a fake can skip the real isolate round trip entirely.
typedef FrameDecoder = Future<String?> Function(Uint8List luma, int bytesPerRow, int width, int height);

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.openCamera, this.decode = _defaultDecode});

  /// Test hook: replaces the real camera. Starts delivering frames; completes once started. Throws to simulate a refusal.
  final FrameStream? openCamera;

  /// Test hook: replaces decodeQr's compute() isolate round trip.
  final FrameDecoder decode;

  static Future<String?> _defaultDecode(Uint8List luma, int bytesPerRow, int width, int height) =>
      compute(_decodeArgs, (luma, bytesPerRow, width, height));

  @override
  State<ScanPage> createState() => ScanPageState();
}

class ScanPageState extends State<ScanPage> {
  CameraController? _camera;
  String? _problem;
  bool _done = false;
  bool _busy = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      if (widget.openCamera != null) {
        await widget.openCamera!(_onFrame);
      } else {
        final cams = await availableCameras();
        final back = cams.where((c) => c.lensDirection == CameraLensDirection.back);
        if (cams.isEmpty) throw StateError('sem câmera');
        final c = CameraController(back.isNotEmpty ? back.first : cams.first, ResolutionPreset.high,
            enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
        try {
          await c.initialize();
        } catch (e) {
          // initialize() subscribes to orientation events before permission is granted: a denied or busy
          // camera must still be disposed, or that subscription (and a cameraInUse failure's native camera) leaks.
          // A dispose() failure here must not replace the real error (e.g. CameraAccessDenied) the user needs to see.
          await c.dispose().catchError((_) {});
          rethrow;
        }
        if (!mounted) {
          await c.dispose();
          return;
        }
        _camera = c;
        await c.startImageStream((img) => _onFrame(img.planes[0].bytes, img.planes[0].bytesPerRow, img.width, img.height));
      }
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      _fail(e.code.startsWith('CameraAccess') ? 'Sem permissão para usar a câmera. Libere nas configurações do aparelho ou cole o código.' : 'Não consegui abrir a câmera (${e.code}).');
    } catch (e) {
      _fail('Não consegui abrir a câmera.');
    }
  }

  void _fail(String m) {
    if (mounted) setState(() => _problem = m);
  }

  // ponytail: ~4 frames per second, one decode at a time. Raise the rate if scanning feels slow on cheap phones.
  void _onFrame(Uint8List luma, int bytesPerRow, int width, int height) {
    if (_done || _busy || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < 250) return;
    _last = now;
    _busy = true;
    final copy = Uint8List.fromList(luma); // the camera reuses its buffer: copy before leaving this callback
    widget.decode(copy, bytesPerRow, width, height).then((v) {
      _busy = false;
      if (v == null || _done || !mounted) return;
      // Back may have been pressed: the page stays mounted through the ~300 ms exit animation. Popping now would
      // pop whatever is now on top instead of this screen.
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _done = true;
      Navigator.pop(context, v);
    }, onError: (Object _) {
      _busy = false;
    });
  }

  @override
  void dispose() {
    _done = true;
    final c = _camera;
    _camera = null;
    if (c != null) {
      // stop the stream before disposing, ignore errors on the way out
      unawaited((c.value.isStreamingImages ? c.stopImageStream() : Future<void>.value()).catchError((_) {}).whenComplete(c.dispose));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR'), backgroundColor: C.surface),
      body: _problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_problem!, key: const Key('scan-problem'), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
                ]),
              ),
            )
          : cam != null && cam.value.isInitialized
              ? CameraPreview(cam)
              : const Center(child: CircularProgressIndicator()),
    );
  }
}

String? _decodeArgs((Uint8List, int, int, int) a) => decodeQr(a.$1, a.$2, a.$3, a.$4);
