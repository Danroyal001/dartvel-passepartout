# Progress: VPN production audit (branch agent/vpn-audit-2026-10, PR into dartvel)

State on 2026-10-15. The findings are in app-dartvel/docs/audit-2026-10.md and the framework
gaps in app-dartvel/docs/DARTVEL-GAPS.md.

## Done
- PR #3 (agent/vpn-linux-net) merged into this branch and completed: it compiles now;
  the profile is passed on stdin with a size cap; no profile or key file is written; errors
  never echo input; the app runs --cleanup only when a started helper did not restore; there
  is a "Restore network" action. The helper now holds "connected" until routes are in place
  and exits after stop.
- The real netns test was run in Dart: 25/25 checks (docs/evidence/netns-2026-10-15.txt).
- The UI was ported to Dartvel conventions: functional widgets, DVBox/DVText, signals,
  DVIconButton, tooltips. main.dart is DV.run with a TODO; pages/_guard.dart added; backend
  functions are typed with middleware; the app uses the published Dartvel 0.12.2; tooling is
  Dart-only; the app has an icon and favicon. test/conventions_test.dart checks all of this.
- Tests: 236 pass with the engine. The web build was checked in Chromium (docs/screens/2026-10).

## Not done / next
- Push and PR: this session could not push (the git proxy has no credential for the fork,
  and the gh token is invalid). The branch exists only locally.
- Persistence through Dartvel models needs a device-only model (gap), because profiles hold
  private keys.
- Android, Apple and Windows tunnels are blocked by framework gaps.
- Not tested on a desktop: the polkit prompt and systemd-resolved DNS.
- `dartvel build web` semantics capture failed in this sandbox (CDN unreachable from headless
  Chromium).
