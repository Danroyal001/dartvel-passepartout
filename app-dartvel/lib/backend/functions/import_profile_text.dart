// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// POST /api/import_profile_text: the browser has no engine, so the web target
// asks its own server (which links Partout) to read a configuration. Takes
// the configuration text and a name, returns the profile document, which the
// app reads with TunnelProfile.decode at the engine boundary.
import 'package:dartvel_core/dartvel.dart';

import '../../platform/vpn_service.dart';

@DVBackendFunction(middleware: [DVMiddlewares.bodyLimit, DVMiddlewares.rateLimit])
Future<String> _importProfileText({required String text, required String name}) async {
  if (text.length > 1024 * 1024) throw const FormatException('Configuration exceeds 1 MB');
  if (name.trim().isEmpty) throw const FormatException('Name is required');
  return (await VpnService.instance.importProfile(text, name.trim())).encode();
}
