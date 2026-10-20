# n8n-termux

Run **n8n** (npm package `n8n` v2.44.4) natively on Android via Termux.

n8n ships a prebuilt dist and an official CLI, so there is no app build —
the port is about its two native dependencies, neither of which publishes
an Android build:

- `sqlite3` (default database) — N-API module, no android-arm64 prebuild.
- `isolated-vm` (Code-node sandbox / agents runtime) — ships prebuilds for
  Linux glibc/musl, macOS and Windows only; the glibc binaries cannot load
  under Android's bionic libc.

## Two install paths

**Path 1 — compile on the phone (the installer).** Download
`install-n8n-termux.sh` and run it in Termux. It installs the Termux
toolchain (nodejs ≥ 24, python, clang, make), installs `n8n@2.44.4`
globally with build parallelism bounded to `-j2`, letting both native
modules compile on-device, and finishes with a bounded smoke test on
port 5678.

**Path 2 — NDK cross-compile in CI (experimental).** The
**Cross-compile n8n natives for Android (NDK)** workflow cross-compiles
both modules with NDK r28c targeting `aarch64-linux-android`, ELF-checks
the results (aarch64, bionic linkage, no `libc.so.6`), and packages them
as an artifact. sqlite3 is expected to pass; isolated-vm is a genuine
experiment (raw V8 addon, Node-ABI-bound). See `out/BUILD-RESULTS.txt`
in the artifact for the verdicts. Modules that pass can be dropped into
an `--ignore-scripts` install on the phone, sparing it the compile.

## Notes

- Editor/API: http://localhost:5678, data in `~/.n8n`.
- If sqlite3 ever becomes the blocker, n8n officially supports Postgres
  (`DB_TYPE=postgresdb`) and Termux ships a postgresql package.
- Full dissection and reasoning: [TERMUX-NOTES.md](TERMUX-NOTES.md).
