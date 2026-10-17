// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// GET /api/health: "ok" while the server answers.
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
String _health() => 'ok';
