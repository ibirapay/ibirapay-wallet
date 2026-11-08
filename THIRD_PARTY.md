# Third-party notices

## Glow (design reference)
The layout and visual language of the screens (dark void background, centered balance, gradient Enviar/Receber bar,
payment rows, bottom sheets) follow Breez's Glow wallet, https://github.com/breez/glow-web, MIT License,
Copyright (c) 2026 Breez. No Glow source code or brand assets are included; colors use IBIRAPAY teal.

## QR scanning: camera + zxing_lib
QR codes are read with the Flutter `camera` plugin (BSD-3-Clause, AOSP CameraX under the hood) and `zxing_lib`
(Apache-2.0, a Dart port of ZXing). No Google ML Kit and no Play Services: this is what keeps the app free of
non-free dependencies for inclusion in the official F-Droid.
