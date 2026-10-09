// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
// Turns a wg-quick file into the Partout profile the tunnel helper reads,
// through the real engine, optionally with rule groups applied the way
// TunnelStore.connect applies them.
//
// dart run tool/netns_test/make_profile.dart IN.conf OUT.json [EXCLUDED_CIDR...]

import 'dart:io';

import 'package:passepartout/domain/rule_groups.dart';
import 'package:passepartout/platform/vpn_service_native.dart';

Future<void> main(List<String> args) async {
  final engine = PartoutVpnService();
  var profile = await engine.importProfile(File(args[0]).readAsStringSync(), 'netns');
  final excluded = args.skip(2).toList();
  if (excluded.isNotEmpty) {
    final group = RuleGroup.create('netns').copyWith(excluded: excluded);
    final routes = await ruleRoutes(<RuleGroup>[group], resolve: (_) async => <String>[]);
    profile = applyRuleRoutes(profile, routes);
  }
  File(args[1]).writeAsStringSync(profile.encode());
}
