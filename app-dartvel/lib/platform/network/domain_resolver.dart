// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Resolves a rule group's domain names at connect time.

import '../../domain/rule_groups.dart';
import 'domain_resolver_stub.dart' if (dart.library.io) 'domain_resolver_io.dart' as implementation;

abstract final class DomainResolution {
  /// The resolver connect uses. Tests replace it.
  static DomainResolver resolve = implementation.resolveDomain;
}
