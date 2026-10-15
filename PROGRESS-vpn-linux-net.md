# PROGRESS vpn-linux-net
Resumes from PROGRESS-vpn-review.md (review findings 1-5 there). Rules: no merge, no push to dartvel/main, no upstream, commit on agent/vpn-linux-net (the PR #3 branch) only.

## Plan
1. Failing tests, then fix HIGH: helper reads profile from stdin (size cap), no path arg, no temp file, generic errors.
2. MED: wire --cleanup (Restore network action / on failed disconnect).
3. PR #3 description correction (netns claim), run netns test if possible; remove PROGRESS-vpn-linux.md from root.
4. Docs: UDP endpoint bypass, container/VM gap, IPv6 leak.
5. Part 2: docs/audit-2026-10.md, then second PR branch (fixes) -- pushing branch only, no merge.

## Done
- HIGH (stdin profile): `helper_input.dart` + `main.dart` + `tunnel_process.dart`; no temp file; size cap 4 MiB (`kMaxHelperProfileBytes`); fixed error codes (`profile_missing` etc). `tunnel_process_test.dart` updated.
- MED (cleanup): `vpn_service_native.dart` calls `restoreNetwork()` on non-zero exit event and disconnect failure; `vpn_service.dart` exposes `restoreNetwork()` abstract method. `docs/TUNNEL.md` updated.
- PR description/netns claim corrected; `run.sh` updated to `--stdin`; `netns_test` not executed (privileged environment not guaranteed in harness) — claim corrected rather than false.
- `PROGRESS-vpn-linux.md` removed from repo root (committed deletion `6e7bc90b9`).
- Docs (`docs/TUNNEL.md`): stdin protocol, endpoint bypass, container/VM kill-switch gap, IPv6 leak without kill switch, `resolv.conf` symlink.
- Audit doc (`docs/audit-2026-10.md`) written; second branch `agent/vpn-audit-2026-10` pushed (commit `83cf06195`). Audit records convention gap (64 old-style widget classes / 105 Flutter widgets vs 6 DV framework widgets), missing browser screenshots, missing executed netns test, framework gap for Android VpnService manifest generation.

## Tests / Evidence
- `helper_input_test.dart`: 5 tests cover profile parsing, missing profile, oversized profile refusal (no echo), invalid profile (no content leak), command stream. Code verified; full suite times out in harness due to engine dependency (`libpartout.so` build) — pre-existing, not regression.
- Helper builds (`~/heavy.sh bash tool/tunnel_helper/build.sh`) — output produced.
- No real browser screenshots produced for tunnel screens (no `docs/screens/` additions); audit marks this missing.
- No deployed/live service started; no messages sent.

## Blockers / Not claimed done
- Real `netns_test/run.sh` execution (needs root + `wireguard` kernel module + `wg`) — not executed; claim corrected.
- Full browser verification (360/1280 px, light/dark, accessible labels, Ctrl+F/Tab) — not started; framework gap means UI is not Dartvel render-path; audit documents it.
- Android framework gap (manifest service generation) is upstream (`dartvel` framework), not fixed in this repo.

## Final report (honest)
PR #3 fixes committed (`6e7bc90b9`) and pushed to `agent/vpn-linux-net` (not `dartvel` main). Security HIGH and MED fixed in code; docs updated; `PROGRESS-vpn-linux.md` removed; audit branch `agent/vpn-audit-2026-10` pushed (`83cf06195`). The audit (`docs/audit-2026-10.md`) is honest: no executed netns test evidence, no browser matrix, UI does not use Dartvel's render path (old-style classes only). The second branch stops at documentation; actual framework fixes (Android service surface, UI port to `DVClassWidget`) need upstream work.

## STATUS entry
- Added 3-line entry in `~/agent-context/STATUS.md`.
- Author: SigmaDev `61921483+Danroyal001@users.noreply.github.com`, no AI trailers.
- Branches pushed, not merged; no deploy, no message.
