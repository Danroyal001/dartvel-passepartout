// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Upstream builds every module on "Save" and shows the first
// `PartoutError.invalidField` it throws. Edits here write JSON at once, so the
// raw text that would fail lives in the editors' builders; this asks them.

import '../../../domain/profile.dart';
import '../dns_view.dart';
import '../http_proxy_view.dart';
import '../wireguard/wireguard_issues.dart';

/// The localised save-time error of [module], or null when it would build.
/// IP and on-demand modules never fail to build upstream. WireGuard reports
/// the first field its editor flags (keys, addresses, endpoints...), the
/// check the WireGuard apps make before saving a tunnel.
String? moduleValidationError(TaggedModule module) => switch (module.type) {
      ModuleType.dns => dnsValidationError(module),
      ModuleType.httpProxy => httpProxyValidationError(module),
      ModuleType.wireGuard => _wireGuardError(module),
      _ => null,
    };

String? _wireGuardError(TaggedModule module) {
  final configuration = module.value['configuration'];
  if (configuration is! Map) return null;
  final issues = WireGuardValidation.configuration(Map<String, dynamic>.from(configuration));
  return issues.isEmpty ? null : wireGuardIssueText(issues.values.first);
}
