// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// What lib/pages/_guard.dart decides, apart from the router so it is tested
// on its own.

import '../dartvel_client/dartvel_client.dart';
import 'app_state.dart';
import 'profile_draft.dart';

/// Where a page under `/profiles/<id>` goes when that profile neither exists
/// nor is being created: back to the profile list. Null lets the page open,
/// as it does for every other page, and before the saved profiles are loaded
/// (a reload on a profile URL must not lose its place).
String? missingProfileRedirect(Uri location, {required ProfilesState profiles, required ProfileDraft draft}) {
  final segments = location.pathSegments;
  if (segments.length < 2 || segments.first != 'profiles') return null;
  if (!profiles.isReady) return null;
  final id = segments[1];
  if (profiles.byId(id) != null || draft.profile?.id == id) return null;
  return DVRoutes.index.path;
}
