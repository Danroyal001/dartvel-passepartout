// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
//
// Derives the launcher icon and the favicon from the logo (assets/icon.png):
//
//   dart run tool/icons.dart
//
// - assets/app_icon.png: 1024x1024, opaque (iOS refuses transparent icons),
//   the logo centred on a light background; Dartvel writes every launcher
//   (Android, iOS, macOS, Windows, Linux) and the PWA icons from it.
// - assets/favicon.png: the logo trimmed to its drawing, 64x64, transparent.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final logo = img.decodePng(File('assets/icon.png').readAsBytesSync())!;
  final drawing = img.trim(logo, mode: img.TrimMode.transparent);

  const size = 1024;
  final icon = img.Image(width: size, height: size, numChannels: 4);
  img.fill(icon, color: img.ColorRgba8(0xFF, 0xF8, 0xEE, 0xFF));
  // The drawing fills about two thirds of the height, inside every platform's
  // safe zone (Android's adaptive mask is the tightest).
  final height = (size * 0.62).round();
  final scaled = img.copyResize(drawing, height: height, interpolation: img.Interpolation.cubic);
  img.compositeImage(icon, scaled, dstX: (size - scaled.width) ~/ 2, dstY: (size - scaled.height) ~/ 2);
  File('assets/app_icon.png').writeAsBytesSync(img.encodePng(icon));

  final square = img.Image(width: drawing.height, height: drawing.height, numChannels: 4);
  img.compositeImage(square, drawing, dstX: (drawing.height - drawing.width) ~/ 2);
  final favicon = img.copyResize(square, width: 64, height: 64, interpolation: img.Interpolation.cubic);
  File('assets/favicon.png').writeAsBytesSync(img.encodePng(favicon));
  stdout.writeln('Wrote assets/app_icon.png and assets/favicon.png');
}
