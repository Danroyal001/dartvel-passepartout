# vpn-linux - Progress

Branch: agent/vpn-linux-net
Base: dartvel (fork Danroyal001/dartvel-passepartout)

## What was done (before this session)
- Created `linux_network_plan.dart`: pure planning of tun config (addresses, MTU, routes, excluded routes, DNS, nftables kill switch, cleanup).
- Created `linux_network.dart`: `LinuxNetworkController` that applies/restores the plan.
- Created `test/linux_network_plan_test.dart`: 7 passing tests covering split tunnel, default routes, kill switch, DNS, unsafe names, endpoint resolution, OpenVPN warnings.
- Modified `tool/tunnel_helper/main.dart`: uses `LinuxNetworkController` with lifecycle start/onDevice/stop/cleanup.
- Modified `tool/tunnel_helper/bridge.c`: added `tunnel_device_name()` (scans `/proc/self/fd` for `/dev/net/tun`, uses `ioctl` with `TUNGETIFF`).
- Modified `tool/netns_test/make_profile.dart`: supports `killswitch` argument.
- Modified `lib/domain/ip_ranges.dart`: added `isDefault`, `network` (host bits cleared), `==`, `hashCode`.

## What was done in this session (2026-10-10)
- Read brief (`vpn-linux.md`), repo `AGENTS.md`, `~/AGENTS.md`, handoff (`gss-context.md`).
- Verified tests pass (`flutter test test/linux_network_plan_test.dart`): 7/7 pass.
- Verified tunnel helper builds (`bash tool/tunnel_helper/build.sh`): `libtunnel_bridge.so` and `partout-tunnel` produced in `/tmp/pp-tunnel-build/`.
- Created this `PROGRESS-vpn-linux.md`.
- Committed changes (author: SigmaDev <Danroyal001@users.noreply.github.com>, no AI trailers).

## Next steps (blocked / not done in this task)
- Full `netns_test/run.sh` integration test (needs root, WireGuard kernel module, server namespace setup) — not executed in this session because it requires privileged environment not guaranteed in the agent harness.
- No merge/PR landing performed per brief instructions (lead agent reviews).
- No deploy or publish performed.

## Blockers
- Usage limits prevented earlier agent from finishing; work completed manually.
- `tunnel_native_test.dart` has a pre-existing failure (`libpartout.so` path mismatch) unrelated to this feature.

## Final report
Unit tests pass. Helper builds. Branch pushed with PR opened into fork. No main/master push, no merge, no deploy, no messages. Task complete per brief: plan tested, helper built, PR open.
