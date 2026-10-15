# Tunnel integration

Linux is implemented through a separate Dart AOT helper, `partout-tunnel`.
The application starts `pkexec /usr/local/libexec/passepartout/partout-tunnel --stdin` and writes
the profile on its stdin (see Protocol).
`canConnect` requires Linux, an executable helper and pkexec in PATH. Authentication,
missing libraries and network privileges can still fail at runtime; availability is
not a promise of successful connection. `PARTOUT_TUNNEL_HELPER` overrides the app's
helper location for testing; a custom installed path also needs a matching policy.
Web, Android, Windows and Apple connection implementations remain pending.

## Build and install (owner only)

Build the engine first (docs/BUILD.md). From `app-dartvel`, resolve dependencies with
`flutter pub get`, then run:

```sh
dart run tool/tunnel_helper/build.dart            # output: build/tunnel-helper
```

Paths default to this checkout (`../partout`); override `PARTOUT_SOURCE`,
`PARTOUT_LIB_DIR` and `PARTOUT_OPENSSL_DIR` for another engine build, or pass an output
directory as the first argument.
The C bridge requires the matching upstream `partout.h`; it is not a Flutter native
folder or platform shell. The executable is compiled with `dart compile exe`.
The bridge loads **only** `libpartout.so` beside the helper. Its dependencies must
resolve from the trusted install directory or system library directories. Confirm
with `readelf -d` and `ldd`: no dependency/runpath may point to a user-writable path.
The current engine has `$ORIGIN` RUNPATH and needs libwg-go, OpenSSL and system libs.
Do not install symlinks to user-owned build files or grant privileges to a Dart VM.

Review the compiled files and XML first. The owner runs this single privileged
installation block (this worker has not run it):

```sh
sudo sh -eu <<'INSTALL'
install -d -o root -g root -m 0755 /usr/local/libexec/passepartout
install -o root -g root -m 0755 build/tunnel-helper/partout-tunnel /usr/local/libexec/passepartout/
install -o root -g root -m 0644 build/tunnel-helper/*.so* /usr/local/libexec/passepartout/
install -o root -g root -m 0644 tool/tunnel_helper/io.partout.tunnel.policy /usr/share/polkit-1/actions/
INSTALL
```

Install the distribution's polkit/pkexec package first if missing. A desktop polkit
agent must run for the authentication prompt. The helper runs as root and therefore
has CAP_NET_ADMIN; never use passwordless authorization or writable privileged code.
Restart/reinstall nothing automatically. Check routing and DNS restoration after a
real connection/disconnection before treating a release as validated.

**Setcap alternative:** after installing the same root-owned immutable files,
the owner can grant `cap_net_admin=ep` to the **compiled helper only** with
`sudo setcap cap_net_admin=ep /usr/local/libexec/passepartout/partout-tunnel`.
This grants networking privileges without a per-launch prompt. The current app
still uses pkexec intentionally; direct invocation is for manual testing or a future
explicit launcher mode. Do not setcap `dart`, `flutter` or a user-writable executable.
Capability execution uses the secure dynamic loader: verify every dependency resolves
and that the daemon's Linux route/DNS operations require no additional privileges.
Reinstallation removes file capabilities; never silently reapply them.

## Protocol and ownership

The helper runs as root and takes **no path argument**: it cannot be pointed at a file.
The app writes the profile (which holds the WireGuard private key) as the first stdin
line, at most 4 MiB (`kMaxHelperProfileBytes`); a longer line, a missing line or a line
that is not a JSON object is refused. The profile is never written to disk and never
appears in arguments, environment or logs. Failures report only a fixed code
(`profile_missing`, `profile_too_large`, `profile_invalid`, `profile_timeout`,
`network_setup`, `cleanup_failed` and `helper_failure` carry the exception *type* as
`detail`), never any exception text or part of the input. Later stdin lines are commands
(`stop`); when stdin closes the helper stops too, and it releases stdin so it exits.

`partout-tunnel --cleanup` removes routing rules, the nftables kill switch and DNS changes a
killed helper left behind, and answers `{"type":"network","state":"restored"}`. The helper
sends the same event after it undid its own changes on a normal stop or a failure. The app
runs `--cleanup` (through pkexec) only when a helper that had started (`ready`) ended
without that event, and when a stop cannot be confirmed: not after a refused pkexec prompt.
Without it the kill switch, which fails closed, would keep blocking traffic until the next
connect. Settings > Diagnostics also offers "Restore network" for the case where the app
itself was killed together with the helper.

Stdout contains JSON lines with `type`: `ready`, `status` (disconnected/connecting/
connected/disconnecting), `data` (received/sent byte totals), `error` (code, detail),
`log` (level/message), `exit` (native completion code) and `network` (restored). Stderr is
captured separately. `lib/platform/tunnel/tunnel_protocol.dart` is the only code that reads
or writes these lines; the app sees the sealed `HelperEvent` types. Ready means profile
consumed and helper started. **Connected** is the engine's status, held back by the helper
(`HelperStatusGate`) until the tun device has its addresses, routes and DNS: before that
nothing goes through the tunnel, so the app must not say it is connected.

Partout blocks in daemon mode on a pthread. Bindings have a NULL controller,
selecting Linux's default tun implementation as the upstream CLI does. Event-only
bindings are required for status reporting. A C bridge duplicates borrowed status,
error and logger strings *before* returning to Partout, whose strings are immediately
freed. All four event kinds arrive through `NativeCallable.listener`; Dart frees
copies only after delivery. Logging sets `logs_private_data=false`. No Dart
synchronous callbacks run on native threads. Completion follows native shutdown.

Disconnect writes `stop` on stdin; the helper calls `partout_daemon_stop`.
SIGTERM and SIGINT do the same. The app waits for pipe draining and process exit,
then attempts SIGTERM by the spawned PID if needed. Linux prevents an unprivileged
app from signalling a root helper, so stdin is the reliable control path across
pkexec. Failure to stop is surfaced rather than claimed as disconnected; an owner
may need to terminate a stuck privileged PID. Closing stdin also stops the daemon.
No global process-name kills are used.

Logs are written by the *app user* to `$XDG_CACHE_HOME/passepartout/tunnel` (fallback
`$HOME/.cache/passepartout/tunnel`), directory 0700/files 0600. They also feed AppLog.
Diagnostics can import `lib/platform/tunnel/tunnel_logs.dart` for
`tunnelLogFiles()` and `readTunnelLog(path)`. Paths are limited to discovered regular
log files; symlinks are not listed. Logs may contain profile names/IDs even with
private protocol data redacted. Rotation/deletion UX is a follow-up.

## Verification

`flutter test test/tunnel_process_test.dart test/helper_input_test.dart
test/linux_network_plan_test.dart` covers the typed event protocol, the connected gate,
cleanup decisions, stdin profile delivery and size cap, no temp file, fixed error codes,
duplicate start, early exit, startup timeout and graceful stop (the fake helpers are Dart
scripts). C is compiled with warnings as errors.

`dart run tool/netns_test/run.dart` (root or sudo; iproute2, nftables, wireguard-tools,
iputils-ping; kernel WireGuard or `wireguard-go` for the server end) runs the **real helper
and engine** against a WireGuard server in network namespaces, with the profile piped on
stdin and no key file written. It checks: handshake and `connected`; the tun device
addressed by the helper; ping through the tunnel and encrypted bytes counted on the server;
data events; stop restores (no rules, no tun device); an excluded route leaves outside the
tunnel; the kill switch drops outside traffic, still drops it after the helper is killed
with SIGKILL, and `--cleanup` lets it through again; the host's rules, routes and nftables
tables are unchanged. The run of 2026-10-15 passed all 25 checks
(docs/evidence/netns-2026-10-15.txt; server end wireguard-go, as that kernel had no
WireGuard module). Not covered there: pkexec/polkit prompts, systemd-resolved DNS, IPv6.

`dart run tool/tunnel_helper/probe.dart` runs the helper unprivileged against a dead
endpoint for three seconds: a connection *attempt*, not a VPN handshake.

## Android implementation plan and framework gap

Use upstream `app-android/.../PassepartoutVpnService.kt`, `vpn/VpnServiceStore.kt`,
`VpnServiceNotificationController.kt`, and `partout/cross/android`'s
`PartoutVpnServiceRuntime`. Generate JNI bindings with jnigen: call
`VpnService.prepare`, launch the system consent intent, then start the foreground
service with the lossless profile JSON. The service owns `VpnService.Builder`, tun
fd, `protect(socket)`, DNS/routes, lifecycle and foreground notification. Bridge
`set_connection_status`, `set_data_count`, `set_last_error_code` to Dart events;
stop through runtime stop/onRevoke and close the tun fd. No MethodChannel.

Dartvel must generate the service class/build dependency and this manifest entry
inside application, plus INTERNET and foreground-service permissions appropriate
to the target SDK (including system-exempted VPN foreground type where required):

```xml
<service android:name="com.algoritmico.passepartout.PassepartoutVpnService"
    android:permission="android.permission.BIND_VPN_SERVICE"
    android:exported="true">
  <intent-filter><action android:name="android.net.VpnService" /></intent-filter>
</service>
```

Current Dartvel config/build sources contain permission/capture manifest generation,
but no app-declared Android service input. Repro: a generated app with all platforms
cannot express this `<service>` from pubspec; JNI binding alone cannot make Android
instantiate a VpnService. Lead must add a declarative service/native-source dependency
surface and test generated release manifests (permission, intent-filter, exported,
foreground type), including consent/revoke and process restart on an Android device.
Record this under the tunnel workstream in DARTVEL-GAPS.md; that shared file is outside
this worker's assigned files.

## Windows implementation plan

Reuse `partout/cross/windows/{runtime,tun,tun_ctrl_windows,socket}`. Package the matching
signed Wintun DLL for each architecture beside a trusted elevated helper. Helper owns
adapter creation/session, routes and DNS and restores them on stop/failure. Elevate via
UAC (ShellExecuteEx runas through FFI); exchange events/control over a named pipe with
a DACL restricted to the interactive user's SID and SYSTEM/admin, validate peer identity,
and pass a private profile file/pipe. Track the actual elevated process handle; close
sessions and wait on exit rather than terminating unrelated helpers. Test cancel-UAC,
existing adapter, IPv4/IPv6, crash recovery and DNS/route restoration on Windows.
Dartvel needs helper/DLL packaging and signed distribution support; no app native folders.

## Apple implementation plan

Reuse upstream app-apple NetworkExtension packet-tunnel target and Partout's Apple
bindings. The containing app controls NETunnelProviderManager via generated native
FFI/JNI-equivalent Objective-C bindings, loads/saves provider configuration and starts/
stops NETunnelProviderSession. The extension owns NEPacketTunnelProvider, packet flow,
routes and DNS and forwards status/traffic/error messages using provider messages and
shared app-group storage. Keep keys in Keychain with the appropriate access group.

Dartvel must generate an additional signed app-extension target with its own bundle ID,
Info.plist `NSExtension` packet-tunnel declaration, NetworkExtension entitlements, matching
app-group/keychain groups, embedded extension dependency and provisioning for both app
and extension. Current single-app packaging cannot declare this target. Repro: a pubspec
with ios/macos enabled cannot describe a packet-tunnel extension or its entitlements.
Lead should record/test this gap, implement target generation rather than editing native
folders, then verify on signed Apple devices (simulator/server builds cannot establish
this parity). Test consent, on-demand, reconnect, app termination and extension stop.

The recorded `tool/tunnel_helper/probe-stop.jsonl` and `probe-sigterm.jsonl` are older
unprivileged probe runs (tun creation denied, clean exit). The privileged end-to-end run is
the netns test above.

## Known limits of the Linux network plan

- **Endpoint bypass:** a routing rule sends traffic to the endpoint's UDP port outside the
  tunnel (encrypted packets must not loop into it). Any local process can therefore send UDP
  to `endpoint:port` without the tunnel, even with the kill switch on.
- **Containers and VMs:** the kill switch hooks the nftables `output` chain only. Traffic
  forwarded for containers, VMs or network namespaces is not covered and can leave through
  the physical interface while the tunnel is down.
- **IPv6:** a profile with only IPv4 addresses routes no IPv6 through the tunnel. Without
  the kill switch, IPv6 traffic goes out the physical interface (a leak). Turn the kill
  switch on ("Enforce tunnel") to block it.
- **resolv.conf:** without systemd-resolved the helper rewrites `/etc/resolv.conf` (backup
  restored on stop); if that path is a symlink, the target is written through the link.
