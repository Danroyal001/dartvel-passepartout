// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:passepartout/domain/qr_import.dart';
import 'package:zxing2/qrcode.dart';

/// A PNG of [text] as a QR code: 4 px modules, 4-module quiet zone.
List<int> _qrPng(String text, {bool dark = false, int scale = 4}) {
  final matrix = Encoder.encode(text, ErrorCorrectionLevel.l).matrix!;
  const quiet = 4;
  final size = (matrix.width + quiet * 2) * scale;
  final image = img.Image(width: size, height: size);
  final light = dark ? img.ColorRgb8(20, 20, 20) : img.ColorRgb8(255, 255, 255);
  final ink = dark ? img.ColorRgb8(235, 235, 235) : img.ColorRgb8(0, 0, 0);
  img.fill(image, color: light);
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) == 1) {
        img.fillRect(image,
            x1: (x + quiet) * scale, y1: (y + quiet) * scale, x2: (x + quiet + 1) * scale - 1, y2: (y + quiet + 1) * scale - 1, color: ink);
      }
    }
  }
  return img.encodePng(image);
}

void main() {
  final config = io.File('test/fixtures/sample.conf').readAsStringSync();

  test('reads a wg-quick configuration from a QR code image', () {
    expect(decodeQrImage(_qrPng(config)), config);
  });

  test('reads a light-on-dark QR code (a dark-mode screenshot)', () {
    expect(decodeQrImage(_qrPng(config, dark: true)), config);
  });

  test('reads a JPEG photo-sized image', () {
    final png = img.decodePng(Uint8List.fromList(_qrPng(config, scale: 12)))!;
    expect(decodeQrImage(img.encodeJpg(png, quality: 90)), config);
  });

  test('refuses what is not an image or has no code', () {
    expect(() => decodeQrImage(<int>[1, 2, 3]), throwsFormatException);
    final blank = img.Image(width: 200, height: 200)..clear(img.ColorRgb8(255, 255, 255));
    expect(() => decodeQrImage(img.encodePng(blank)), throwsFormatException);
  });

  test('only tunnel configurations are imported', () {
    expect(looksLikeTunnelConfig(config), isTrue);
    expect(looksLikeTunnelConfig('client\ndev tun\nremote vpn.example.com 1194\n'), isTrue);
    expect(looksLikeTunnelConfig('https://example.com/promo'), isFalse);
  });
}
