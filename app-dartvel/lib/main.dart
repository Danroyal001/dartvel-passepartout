// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'app.dart';
import 'dartvel_client/dartvel_client.dart';

Future<void> main(List<String> arguments) async {
  // TODO(dartvel): main should be `DV.run()` alone. Dartvel 0.12.2's DV.run
  // only wraps runApp(widget): it takes neither the launch arguments nor the
  // app's startup work, so both are spelled out here (docs/DARTVEL-GAPS.md).
  await prepareDartvelVpn(arguments);
  DV.run(createDartvelApp(arguments: arguments));
  await loadDartvelVpn();
}
