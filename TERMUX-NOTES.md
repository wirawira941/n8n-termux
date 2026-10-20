# n8n Termux port — dissection notes (2026-10-20)

Package dissected: `n8n` **2.44.4** (npm tarball 5.5 MB, extracted at
~/workspace/n8n-termux/pkg/package/). Started in parallel with the LobeChat
v1 CI build at the user's request.

## Shape — the easy kind
- Official CLI package with `bin: n8n -> ./bin/n8n`, and it ships a **prebuilt
  dist/** (compiled JS + the prebuilt editor UI via n8n-editor-ui) — no build
  step of ours, no CI needed. Profile is closest to 9Router: install, then run.
- engines: **Node >= 24** (Termux's nodejs package line satisfies this; verify
  on-device).
- No postinstall script in the main package. 161 dependencies.
- Runtime: editor/API server on port **5678**, data dir `~/.n8n`, default DB
  is SQLite.

## Native dependencies — both lack Android prebuilds
- `sqlite3` 5.1.7 (hard dep): prebuilds are fetched from TryGhost/node-sqlite3
  GitHub releases (napi v3/v6). URL template verified sane (linux-x64 = 200)
  and **android-arm64 = 404 for both napi versions** → no Android prebuild.
  On Termux it falls back to a node-pre-gyp source build (needs python3,
  clang, make — all in Termux). The C compile is modest and commonly done.
  Alternative bypass: n8n officially supports Postgres (`DB_TYPE=postgresdb`)
  with the Termux postgresql package — skips sqlite3 entirely.
- `isolated-vm` ^7.0.1 (hard dep): ships prebuilds INSIDE its tarball for
  linux-arm64/x64 (glibc+musl), darwin-arm64, win32-x64 at Node ABI 137/147 —
  **none for Android/bionic**, and the glibc .node cannot load under bionic.
  Its install script auto-falls back to `node-gyp rebuild`, so npm will TRY
  to compile it on-device: this is the port's main risk. isolated-vm is a
  large C++ build against V8 headers — slow and RAM-hungry on a phone;
  bound parallelism (-j2) if attempted. It is used by @n8n/task-runner
  (Code-node JS sandbox) and referenced by the main process's agents runtime
  (agent-isolate-pool). Open question for the install phase: how gracefully
  n8n degrades if isolated-vm cannot be built (N8N_RUNNERS_ENABLED and
  runner modes exist as env knobs).
- Everything else of note is pure JS (bcryptjs, @grpc/grpc-js).

## Verdict
Feasible, installer-style (no CI build): Termux toolchain (python3, clang,
make) + `npm i -g n8n@2.44.4` with install scripts ON so sqlite3 (and
isolated-vm, if it cooperates) compile on-device; smoke test `n8n --version`
then a bounded server start on :5678. Fallbacks if isolated-vm defeats the
phone: --ignore-scripts install + selective rebuilds, runners disabled, or
accept Code-node/agents degradation. Postgres bypass available for sqlite3.
