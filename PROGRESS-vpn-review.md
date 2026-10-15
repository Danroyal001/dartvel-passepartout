# vpn-review: progress (paused 2026-10-14, queued by lead: 5-agent cap)

Task: (1) review + fix + merge fork PR #3 (agent/vpn-linux-net -> dartvel, merge commit by
SigmaDev <61921483+Danroyal001@users.noreply.github.com>, no AI trailers); (2) write
app-dartvel/docs/audit-2026-10.md, fix top issues on a new branch (tests first), PR into
`dartvel` with screenshots from my own puppeteer-core Chrome (never :9333).
Fork only: Danroyal001/dartvel-passepartout (gh default already set). Never upstream.

## Done
- Read the full PR diff: linux_network_plan.dart, linux_network.dart, tunnel_helper/main.dart,
  bridge.c, ip_ranges.dart, make_profile.dart; plus vpn_service_native.dart, tunnel_process.dart,
  the polkit policy and tool/netns_test/run.sh.
- Ran the whole suite on the PR branch (`~/heavy.sh flutter test` in app-dartvel, flutter at
  ~/snap/flutter/common/flutter/bin): 155 pass, 5 skipped, 7 fail. The failing files
  (engine_test, module_subpages_test setUpAll, openvpn_engine_test, openvpn_widget_test, +3)
  all need libpartout.so at ../partout/bin/linux-x86_64/partout/lib (engine not built in this
  worktree). Next: check whether they fail the same way on origin/dartvel (likely pre-existing).
- No code changed yet. Nothing pushed, nothing merged.

## Review findings (PR #3 is NOT ready to merge yet)
1. HIGH: the helper runs as root (pkexec) and reads any path given as argv[1]. A bad JSON
   file makes jsonDecode throw a FormatException whose text (an excerpt of the file) goes to
   stdout as `helper_failure`, so root-only files leak to the caller. The profile, which holds the
   WireGuard private key, also sits in a temp file. Planned fix: the helper takes `--stdin` and reads
   the profile as the first stdin line (size cap of about 4 MiB), and the path argument is removed.
   TunnelProcess writes the profile and then "\n" to stdin, so no temp file is needed. Update
   run.sh so it pipes the profile and then keeps stdin open. Add tests for the protocol, and for
   the cap and generic error messages.
2. MEDIUM: `--cleanup` is never called by the app. After a crash, the kill switch nft table stays
   (it fails closed), and the user has no internet until the next connect. Wire a "Restore network"
   action, or run cleanup on a failed disconnect.
3. PR description overclaims: it says the netns test checks ping, excluded routes, the kill switch and
   that the host is unchanged. run.sh is NOT changed in this PR, and PROGRESS-vpn-linux.md says
   it was never run. Correct the description, and extend run.sh (it needs sudo; the owner has
   NOPASSWD sudo per STATUS, but the handbook says to test only in a netns, never on host interfaces).
4. PROGRESS-vpn-linux.md is committed at the repo root. Remove it before the merge.
5. Lower risk, document in the audit: the endpoint bypass rule lets any local process send UDP to
   endpoint:port outside the tunnel. The kill switch hooks only output, not forward
   (containers/VMs). A v4-only profile without the kill switch leaks IPv6. resolv.conf fallback
   writes through a symlink.
- Checked OK: every ip/nft/resolvectl call uses argument lists and absolute tool paths (no shell, no
  PATH). The nft script interpolates only canonical IPs, int ports and regex-checked interface
  names. Search domains are regex-checked. The state dir is under /run (root only). The library
  loads only from beside the executable. The policy is auth_admin with a fixed exec path.

## Next (to resume)
1. `cd ~/wt/vpn-linux-net` (branch agent/vpn-linux-net). Write failing tests for finding 1,
   then implement, run the full suite, and build the helper with `~/heavy.sh bash tool/tunnel_helper/build.sh`.
2. Fix 2-4, push to the PR branch, then merge with `git merge --no-ff` as SigmaDev, no trailers.
3. Part 2 (audit + fixes branch + screenshots) has not started.
4. Clean up the build output (/tmp/pp-tunnel-build, app-dartvel/build) and add a STATUS.md entry.
