<!-- SPDX-License-Identifier: GPL-3.0; Copyright 2026 SigmaDev -->
# Build and development

## Toolchain

- Flutter 3.47 stable (Dart 3.13) or newer, and the published Dartvel packages
  (`dartvel_core`, `dartvel_flutter`, `dartvel_shelf`, `dartvel_cli`, all `^0.12.2` in
  pubspec.yaml). The `dartvel` command: `dart pub global activate dartvel_cli 0.12.2`.
- For the Partout engine: Zig 0.16.0, Go 1.24 or newer, CMake and Ninja. Install the
  official Zig release (ziglang.org, check its SHA256 against `index.json`). The Zig
  project also publishes the same binaries on PyPI as the `ziglang` package
  (`pip download ziglang==0.16.0`, then use the `zig` inside the wheel), which is what the
  2026-10-15 audit build used because ziglang.org was not reachable from that machine.
- OpenSSL development headers. Without them, add `-prebuilts 0.8.2` to the engine build
  below to use Partout's prebuilt OpenSSL.

No root is needed to build. Install toolchains wherever you keep them and put them on
`PATH`.

## Engine

The engine is the Partout submodule, pinned at ae65d63961652fe8fb3823e536a6fc80ce5f9c8a.
From the repository root:

```sh
git submodule update --init --recursive
bash partout/scripts/build.sh -gen -config Release -crypto openssl -wireguard
```

That is Partout's own build script. It writes `libpartout.so` and `libwg-go.so` to
`partout/bin/linux-x86_64/partout/lib` (and the OpenSSL libraries to
`partout/bin/linux-x86_64/openssl/lib` with `-prebuilts`). Build outputs are ignored by
the submodule and are never committed.

## App

```sh
cd app-dartvel
flutter pub get
dartvel routes                       # generates lib/dartvel_client (dartvel dev/build do it too)
dart run ffigen --config ffigen.yaml # only after changing the engine's C header
export PARTOUT_LIBRARY="$PWD/../partout/bin/linux-x86_64/partout/lib/libpartout.so"
flutter test
```

Without `PARTOUT_LIBRARY`, the tests that need the native engine are skipped and say so;
the default library path (`../partout/bin/linux-x86_64/partout/lib/libpartout.so`,
relative to `app-dartvel`) is used by the rest. `test/conventions_test.dart` checks the
Dartvel conventions on the source.

The Linux ABI returns malloc-owned strings; the wrapper frees every returned string and
UTF-8 input. Default initialization does not log private data.

The root `scripts/openapi.yaml` defines the app configuration. Engine profile and module
schemas live in `partout/scripts/openapi.yaml`; `domain/profile.dart` follows that
schema's field and discriminator names. Unedited OpenVPN/WireGuard/IP/on-demand payloads
stay lossless; typed DNS/proxy values use the same wire representation.

## Linux tunnel helper

Connecting on Linux goes through a separate privileged helper; see docs/TUNNEL.md for the
build (`dart run tool/tunnel_helper/build.dart`), the install, the stdin protocol and the
network-namespace test (`dart run tool/netns_test/run.dart`). Do not run the UI or the
server as root.
