// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Runs before every page: a profile URL whose profile is gone (deleted, or a
// stale link) returns to the profile list instead of an empty editor.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state.dart';
import '../state/profile_draft.dart';
import '../state/route_guard.dart';

FutureOr<String?> guard(BuildContext context, GoRouterState state) =>
    missingProfileRedirect(state.uri, profiles: ProfileStore.state, draft: DraftStore.state);
