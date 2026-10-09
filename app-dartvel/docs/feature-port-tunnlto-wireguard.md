<!-- SPDX-License-Identifier: GPL-3.0; Copyright 2026 SigmaDev -->
# Features taken from TunnlTo and the WireGuard apps

The owner asked for Dartvel VPN to take what it can from TunnlTo
(github.com/TunnlTo/desktop-app) and from the official WireGuard apps.

## Licensing

- **TunnlTo.** The repository now holds only a README. The old source was "free for personal use,
  not licensed for business or commercial use" and was built on the closed Wiresock driver.
  **No TunnlTo code or assets are used.** Only feature ideas are reimplemented, in our own code.
- **WireGuard apps.** Licenses checked with `gh api repos/WireGuard/<repo>/license` on 2026-10-09:
  wireguard-apple MIT, wireguard-android Apache-2.0, wireguard-windows MIT. We copied **no
  WireGuard source code**. The features below are our own implementations of the same behaviour.
  The idea credit is in `assets/credits/credits.json` (notices "WireGuard apps" and "TunnlTo"),
  which is shown under Settings > About > Credits.
- **New dependencies** (all GPL-3.0 compatible, listed under Credits > Licenses): `archive` (MIT)
  for zip files, `image` (MIT) for decoding pictures, and `zxing2` (BSD-3-Clause, a Dart port of
  ZXing) for reading QR codes.

## What Dartvel VPN had before this work (WireGuard)

| Area | State before |
|---|---|
| Import | `.conf`/`.ovpn` files (several at once) and pasted text, parsed by Partout |
| Editor | Full WireGuard editor: interface, DNS, peers, key generation, public key shown; each long field on its own URL |
| On-demand | OnDemand module editor (policy any/including/excluding, SSIDs, mobile, Ethernet), stored for the engine. Only Apple evaluates it (NEOnDemandRule); nothing evaluated it in the Dartvel app |
| Routing | IP module (included/excluded routes per family); "Enforce tunnel" (`includesAllNetworks`, Apple) |
| Stats | Transfer totals (↓/↑) in the status line |
| Logs | Diagnostics > tunnel logs viewer |
| Desktop | Tray / menu bar app, launch at login |
| UI | Light/dark/system appearance; profile search by name |
| Export | None in the Dartvel app (Apple upstream can export profiles) |

## Feature table

Platforms: L = Linux desktop, W = Windows, M = macOS, A = Android, I = iOS, Web = browser build.
"Done" means implemented and tested on Linux in this change. Apple, Windows and Android builds
were not run here (no Xcode/Windows host; Android connecting is not built yet).

| Feature | Source (license) | Before | Platforms | Plan / status |
|---|---|---|---|---|
| On-demand rules on Wi-Fi SSID / cellular / Ethernet | WireGuard apple (MIT) idea; Partout's `OnDemandModule+NE.swift` rule order (GPL) | Editor only | Rules: all. Evaluation: L (NetworkManager). Apple: system | **Done.** `domain/on_demand_rules.dart` evaluates the module in Partout's order; `state/on_demand_store.dart` watches the network every 10 s on Linux and connects or disconnects the armed profile only when the network changes. Connecting a profile with an active on-demand module by hand arms it; turning it off by hand disarms it. The editor gains "Add current Wi-Fi" and a line saying what the rules do on the current network. Windows/Android/macOS-non-Apple-path: needs a network probe per platform (Dartvel has no network-kind/SSID API; listed in DARTVEL-GAPS) |
| Import from `.conf` | WireGuard apps (MIT/Apache) | Yes | All | Already present |
| Import zip of configs | WireGuard apps | No | All with a file picker (L, W, M, A, Web) | **Done.** Picking a `.zip` imports every `.conf`/`.ovpn` inside; one bad file does not stop the rest; limits on entry count and size |
| Import from QR code | WireGuard android/apple | No | Image file: all. Camera photo: A, I where the Dartvel camera binding exists | **Done.** "Import QR..." in the add menu; decodes any image (photo, screenshot, light-on-dark) with zxing2. Live camera scanning is not done (needs a Dartvel camera preview API) |
| Export tunnels to zip | WireGuard apps | No | L, W, M (system save dialog) | **Done.** "Export all to zip..." writes one `.conf`/`.ovpn` per profile (Partout's own exporter), owner-only file mode. Phones/web: needs a Dartvel "save/share file" API |
| Export one profile | WireGuard apps / Passepartout | No | L, W, M; phones fall back to the share sheet with the text | **Done.** "Export configuration..." in each profile's menu |
| Exclude private IPs | WireGuard android (Apache-2.0) idea | No | All (it edits AllowedIPs) | **Done.** Toggle per peer when AllowedIPs has 0.0.0.0/0. The public ranges are computed by our own CIDR subtraction (`domain/ip_ranges.dart`); private IPv4 DNS servers stay in the tunnel as /32 |
| Inline config validation | WireGuard apps (messages already in upstream's strings) | No | All | **Done.** Keys, addresses, DNS, MTU, endpoint, AllowedIPs, keep-alive and duplicate peer keys are flagged next to the row and on the field's own page; save is refused with the first problem, as the WireGuard apps do |
| Rule groups decoupled from profiles | TunnlTo idea | No | Stored: all. Applied: wherever Partout applies IP module routes | **Done.** Settings > Rule groups (`/settings/rule-groups`, `/settings/rule-group/<id>`): named lists of IPs, subnets and domains, "through the tunnel" or "outside the tunnel". A profile switches groups on in its editor (ids kept in `userInfo.dartvel.ruleGroupIds`, allowed by openapi.yaml). On connect the groups become routes in an IP module of the copy handed to the engine; domains are resolved once at connect time. The saved profile never changes |
| Per-app split tunnel (include/exclude apps) | TunnlTo idea; Android `VpnService.Builder.addAllowedApplication` | No | A (VpnService), M (NE app rules, MDM only), L (cgroup + policy routing, root helper) | **Not done.** Android connecting is not built in the Dartvel app yet; Linux needs helper work (cgroup v2 + nftables mark + `ip rule`) that cannot be tested safely on this hosting box. Plan: add `apps` lists to rule groups once a platform can apply them, never before (no UI that does nothing) |
| Searchable profile picker for many tunnels | TunnlTo idea | Name-only search | All | **Done.** Search matches name, module types and server addresses, every word must match; Ctrl+K / Cmd+K focuses it and Enter connects the first match |
| Handshake / transfer stats | WireGuard apps | Transfer only | All with a tunnel | **Partly.** Status now shows how long the tunnel has been up next to ↓/↑. Latest handshake is **not available**: Partout's daemon events carry status, data counts and errors only. Plan: Partout API for wg-go's `last_handshake_time_sec` (UAPI), then show it |
| Kill switch / block untunneled traffic | WireGuard windows/apple | Apple only (`includesAllNetworks`) | M, I (system); W/L need firewall rules in the helper | **Not done** for Linux/Windows: needs nftables (Linux) or WFP (Windows) rules in the privileged helper, with tests in a network namespace or VM, not on this server |
| Per-tunnel log viewer | WireGuard apps | Yes (Diagnostics) | L | Already present |
| Config editor with syntax validation | WireGuard apps | Field editor | All | Field checks done (above). A raw wg-quick text editor is not added: the module editor is the one editing path |
| Apple Shortcuts / intents | WireGuard apple | Upstream Apple app has an Intents extension | I, M | Already in the upstream Apple app; the Dartvel app has no intents API |
| Quick settings tile / tray toggle | WireGuard android | Desktop tray: yes | Tray: L, W, M. Tile: A | Tray already present. Android tile waits for Android connecting |
| Light / dark UI | TunnlTo | Yes | All | Already present |
| Import provider configs | TunnlTo | Yes (any .conf/.ovpn) | All | Already present |

## Verification

Linux (this server): `flutter test` with the Partout engine
(`PARTOUT_LIBRARY`, `LD_LIBRARY_PATH` as in BUILD.md). New tests:
`ip_ranges_test`, `wireguard_validation_test`, `on_demand_test`, `rule_groups_test`,
`tunnel_archive_test`, `qr_import_test`, `profile_search_test`, `profile_transfer_test`
(engine), `feature_port_widgets_test`.

Real tunnel in network namespaces (`tool/netns_test/run.sh`, run 2026-10-09 on this server): two
namespaces joined by a veth pair, a kernel WireGuard peer in one, the compiled `partout-tunnel` helper
in the other. Host routes, links and DNS were compared before and after: unchanged.
- The helper reaches `connected`, the WireGuard handshake completes (engine log and the peer's
  `latest-handshakes`), and the helper reports transfer counts.
- **Partout's default Linux tun controller creates `tun0` but applies no address, route or link-up**
  (`ctrl_set_tunnel((nil))`). With the address and route added by hand inside the namespace,
  ping through the tunnel works (3/3) and the counts rise. So on Linux the data path works, but
  **nothing configures the interface yet**: profile addresses, AllowedIPs routes and IP-module routes
  (therefore rule groups) are not applied. That needs a tun controller in the helper (netlink:
  address, MTU, routes, DNS, and restore on stop), next step for the Linux port.
- Stopping the helper (SIGTERM) exits 0 and removes `tun0`.
- The rule-group case checks the engine input: the excluded route is in the IP module handed to the
  engine.

Not verified here:
- On-demand auto-connect was tested against a fake engine, not a live tunnel.
- NetworkManager probing was tested on recorded `nmcli` output; this server has no Wi-Fi.
- Save dialogs, camera capture and share sheets need a desktop session or a phone.
- macOS/iOS/Windows/Android builds need their hosts (Xcode etc.); nothing in this change touches
  `app-apple`, `app-android` or `app-cross`.
