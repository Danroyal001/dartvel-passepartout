// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
import 'package:flutter/material.dart';
import '../../../dartvel_client/dartvel_client.dart';
import '../../../ui/settings/rule_groups_screen.dart';
@DVPage(title: 'Rule group', showAppBar: false)
Widget _ruleGroupPage(BuildContext context) => RuleGroupEditorScreen(groupId: context.dvParams['id']!);
