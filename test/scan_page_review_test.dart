// L1 and L2 live in their own file (not scan_page_test.dart): a real compute() call there (the only one in the
// suite that goes through a decode isolate) and these two tests do not share a VM/process reliably when run
// together. Separate files get separate flutter test processes, which sidesteps that without chasing it further.

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/scan_page.dart';

void main() {
  group('ScanPage review fixes', () {
    testWidgets('L2: a denied permission disposes the camera controller (no leaked orientation subscription)', (t) async {
      final platform = _FakeCameraPlatform();
      final prior = CameraPlatform.instance;
      CameraPlatform.instance = platform;
      addTearDown(() => CameraPlatform.instance = prior);

      await t.pumpWidget(const MaterialApp(home: ScanPage()));
      await t.pumpAndSettle();

      expect(find.textContaining('permissão'), findsOneWidget);
      expect(platform.orientationStreamRequested, isTrue);
      expect(platform.disposeCalls, 1, reason: 'initialize() subscribed before the permission check failed; dispose must still run');
    });

    testWidgets('L1: pressing Back while a decode is in flight does not pop a second time underneath', (t) async {
      const text = 'deveria-ser-ignorado-apos-voltar';
      String? scannerResult;
      var scannerDone = false;
      late void Function(Uint8List luma, int bytesPerRow, int width, int height) deliverFrame;
      // A send-sheet-like layer below ScanPage, typed <bool> (a confirmation), exactly what a stray pop with a
      // String would hit once Back has already popped ScanPage's own route: this is what a TypeError on that stray
      // pop would come from, the real failure mode the review describes.
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              await Navigator.of(ctx).push<bool>(MaterialPageRoute(
                builder: (ctx2) => TextButton(
                  onPressed: () async {
                    scannerResult = await Navigator.of(ctx2).push<String>(MaterialPageRoute(
                      // A fake decoder (no compute(), no real isolate): only the ModalRoute guard is under test
                      // here, the real decoder has its own coverage (scan_page_test.dart, 'a frame with a QR code
                      // closes the page...').
                      builder: (_) => ScanPage(
                        openCamera: (onFrame) async => deliverFrame = onFrame,
                        decode: (luma, bytesPerRow, width, height) async => text,
                      ),
                    ));
                    scannerDone = true;
                  },
                  child: const Text('abrir scanner'),
                ),
              ));
            },
            child: const Text('abrir'),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('abrir scanner'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300)); // let the push transition finish building the page

      // Back (the AppBar's own button): this starts the pop and its exit animation, the route is no longer current
      // from this point even though ScanPage stays mounted for the transition.
      await t.pageBack();
      await t.pump();

      // A frame "decodes" successfully (the fake resolves at once) while that transition is still running.
      deliverFrame(Uint8List(0), 0, 0, 0);
      await t.pump();

      // Let the pop transition itself finish and the page dispose cleanly.
      await t.pumpAndSettle();

      expect(scannerDone, isTrue);
      expect(scannerResult, isNull, reason: 'Back must win: a late decode must not override it with a scanned value');
      expect(t.takeException(), isNull, reason: 'a late decode landing after Back must not throw or assert');
    });
  });
}

/// Enough of [CameraPlatform] to exercise ScanPage's real camera branch: [availableCameras] returns one camera,
/// [onDeviceOrientationChanged] gives initialize() a stream to subscribe to (as it does before any permission
/// check), and [createCameraWithSettings] refuses like Android does when CAMERA permission was denied. Records
/// whether [dispose] runs, to prove a failed initialize() does not leak that subscription.
class _FakeCameraPlatform extends CameraPlatform {
  bool orientationStreamRequested = false;
  int disposeCalls = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async =>
      [const CameraDescription(name: 'fake0', lensDirection: CameraLensDirection.back, sensorOrientation: 0)];

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() {
    orientationStreamRequested = true;
    return const Stream.empty();
  }

  @override
  Future<int> createCameraWithSettings(CameraDescription description, MediaSettings? settings) async {
    throw PlatformException(code: 'CameraAccessDenied', message: 'recusado pelo usuário');
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposeCalls++;
  }
}
