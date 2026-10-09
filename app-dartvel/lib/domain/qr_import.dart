// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Reads a tunnel configuration from a QR code image, as the official WireGuard
// mobile apps do when they scan a wg-quick config. Works from any image (a
// photo the camera takes or a screenshot file), so every target can use it.
// Decoding uses the `image` and `zxing2` packages; no WireGuard code is copied.

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// The largest image accepted, in bytes and in pixels along a side.
const int maxQrImageBytes = 20 * 1024 * 1024;
const int _maxQrSide = 2000;

/// The text encoded in the QR code in [imageBytes] (PNG, JPEG, GIF, BMP,
/// WebP...). Throws [FormatException] when there is no readable QR code.
String decodeQrImage(List<int> imageBytes) {
  if (imageBytes.length > maxQrImageBytes) throw const FormatException('The image is too large');
  img.Image? image;
  try {
    image = img.decodeImage(imageBytes is Uint8List ? imageBytes : Uint8List.fromList(imageBytes));
  } on Object {
    image = null; // The decoders throw on truncated or foreign data.
  }
  if (image == null) throw const FormatException('Not an image');
  if (image.width > _maxQrSide || image.height > _maxQrSide) {
    image = image.width >= image.height ? img.copyResize(image, width: _maxQrSide) : img.copyResize(image, height: _maxQrSide);
  }
  final pixels = Int32List(image.width * image.height);
  var index = 0;
  for (final pixel in image) {
    final alpha = pixel.a.toInt();
    // Transparent pixels read as white, as a QR code shown on a light page.
    int channel(num value) => alpha == 255 ? value.toInt() : (value * alpha / 255 + 255 - alpha).round().clamp(0, 255);
    pixels[index++] = 0xff000000 | (channel(pixel.r) << 16) | (channel(pixel.g) << 8) | channel(pixel.b);
  }
  final source = RGBLuminanceSource(image.width, image.height, pixels);
  for (final binarizer in <Binarizer Function(LuminanceSource)>[HybridBinarizer.new, GlobalHistogramBinarizer.new]) {
    try {
      return QRCodeReader().decode(BinaryBitmap(binarizer(source)), hints: DecodeHints()..put(DecodeHintType.tryHarder)).text;
    } on Object {
      continue;
    }
  }
  // A dark-mode screenshot shows light modules on a dark background.
  try {
    return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source.invert()))).text;
  } on Object {
    throw const FormatException('No QR code found in this image');
  }
}

/// Whether [text] looks like a configuration Partout can import, so a QR code
/// that holds a web address is refused with a plain message.
bool looksLikeTunnelConfig(String text) {
  final trimmed = text.trimLeft();
  return trimmed.startsWith('[Interface]') ||
      RegExp(r'^\s*(client|remote|dev|proto)\b', multiLine: true).hasMatch(trimmed) ||
      trimmed.startsWith('{');
}
