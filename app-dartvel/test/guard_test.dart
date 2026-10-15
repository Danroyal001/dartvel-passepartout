// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// The pages guard (lib/pages/_guard.dart): a profile URL for a profile that
// does not exist goes back to the profile list.

import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/domain/profile.dart';
import 'package:passepartout/state/app_state.dart';
import 'package:passepartout/state/profile_draft.dart';
import 'package:passepartout/state/route_guard.dart';

void main() {
  final saved = TunnelProfile.empty('Saved');
  final fresh = TunnelProfile.empty('New');
  final loaded = ProfilesState(profiles: <TunnelProfile>[saved], isReady: true);

  test('pages outside a profile are never redirected', () {
    for (final path in <String>['/', '/settings', '/settings/diagnostics/log', '/import-text']) {
      expect(missingProfileRedirect(Uri.parse(path), profiles: loaded, draft: const ProfileDraft()), isNull, reason: path);
    }
  });

  test('a saved profile and its sub-pages open', () {
    for (final path in <String>['/profiles/${saved.id}', '/profiles/${saved.id}/modules/m1', '/profiles/${saved.id}/modules/m1/ca']) {
      expect(missingProfileRedirect(Uri.parse(path), profiles: loaded, draft: const ProfileDraft()), isNull, reason: path);
    }
  });

  test('a new profile being edited opens before it is saved', () {
    final draft = ProfileDraft(profile: fresh, isNew: true, isDirty: true);
    expect(missingProfileRedirect(Uri.parse('/profiles/${fresh.id}'), profiles: loaded, draft: draft), isNull);
  });

  test('an unknown profile goes to the profile list once profiles are loaded', () {
    expect(missingProfileRedirect(Uri.parse('/profiles/nope'), profiles: loaded, draft: const ProfileDraft()), '/');
    expect(missingProfileRedirect(Uri.parse('/profiles/nope/modules/x'), profiles: loaded, draft: const ProfileDraft()), '/');
  });

  test('nothing is decided before profiles are loaded (a reload deep link)', () {
    const loading = ProfilesState();
    expect(missingProfileRedirect(Uri.parse('/profiles/${saved.id}'), profiles: loading, draft: const ProfileDraft()), isNull);
  });
}
