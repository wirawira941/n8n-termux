# n8n-termux

Run **n8n** (npm package `n8n` v2.44.4) natively on Android via Termux.

n8n ships a prebuilt dist and an official CLI, so there is no app build —
the port is about its two native dependencies, neither of which publishes
an Android build:

- `sqlite3` (default database) — N-API module, no android-arm64 prebuild.
- `isolated-vm` (Code-node sandbox / agents runtime) — ships prebuilds for
  Linux glibc/musl, macOS and Windows only; the glibc binaries cannot load
  under Android's bionic libc.

## Install (prebuilt natives — recommended)

Both native modules were cross-compiled for Android with the NDK in
GitHub Actions and **passed** the ELF checks (aarch64, bionic linkage,
no `libc.so.6`); see `BUILD-RESULTS.txt` in the release asset. They are
published in the
[v2.44.4-termux.2 release](https://github.com/wirawira941/n8n-termux/releases/tag/v2.44.4-termux.2),
so the phone never has to compile anything:

1. Download `install-n8n-termux.sh` and run it in Termux.
2. It installs `nodejs` (Node 26; `isolated-vm` is V8-ABI-bound to it) + `libc++` (both `.node` files need
   `libc++_shared.so`), installs `n8n@2.44.4` globally with
   `--ignore-scripts`, downloads the natives zip from the release, and
   places the binaries at the exact paths their loaders search.
3. It load-tests both `.node` files, runs `n8n --version`, and finishes
   with a bounded smoke test on port 5678.

## Fallback (compile on the phone)

`install-n8n-termux-ondevice-compile.sh` is the original installer: it
installs the Termux toolchain and lets both native modules compile
on-device during `npm install`. Kept in case the prebuilt path ever
misbehaves on a specific device.

## How the natives are built

The **Cross-compile n8n natives for Android (NDK)** workflow
(`termux/build-natives-android.sh`) cross-compiles both modules with
NDK r28c targeting `aarch64-linux-android` (sqlite3 via a direct
node-gyp build with deps installed first; isolated-vm via plain
node-gyp), ELF-checks every result, and packages `out/` as
`n8n-android-natives.zip`. Dispatch it with a `release_tag` input to
publish a Release.

## Notes

- Editor/API: http://localhost:5678, data in `~/.n8n`.
- If sqlite3 ever becomes the blocker, n8n officially supports Postgres
  (`DB_TYPE=postgresdb`) and Termux ships a postgresql package.
- Full dissection and reasoning: [TERMUX-NOTES.md](TERMUX-NOTES.md).
