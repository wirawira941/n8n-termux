#!/data/data/com.termux/files/usr/bin/bash
# install-n8n-termux.sh — n8n 2.44.4 on Termux (Android aarch64), using
# PREBUILT native modules (sqlite3 + isolated-vm) cross-compiled with the
# NDK in GitHub Actions. No on-device compilation.
#
# Why prebuilt: n8n's two native deps ship no Android binaries and would
# otherwise compile from source on the phone (isolated-vm is a large V8
# build). The CI-built .node files are aarch64/bionic and pass ELF checks.
# Both need libc++_shared.so (Termux `libc++` package).
#
# How it works:
#   1. Installs Termux packages: nodejs (Node 26; isolated-vm is
#      V8-ABI-bound to Node 26 — see termux/build-natives-android.sh,
#      which pins node-gyp's target to the device's Node), libc++, curl,
#      unzip.
#   2. npm install -g n8n@2.44.4 --ignore-scripts, so npm does NOT try to
#      build/download the natives itself.
#   3. Downloads the natives zip from this repo's GitHub Release and drops
#      the .node files at the exact paths the loaders search:
#        sqlite3:     <pkg>/build/Release/node_sqlite3.node
#                     <pkg>/lib/binding/napi-v6-android-arm64/node_sqlite3.node
#                     (loader is the `bindings` package)
#        isolated-vm: <pkg>/build/Release/isolated_vm.node
#                     (loader is node-gyp-build's build/Release fallback)
#      Every sqlite3 / isolated-vm directory found under the global n8n
#      tree gets a copy, so npm hoisting differences don't matter.
#   4. Load-tests both .node files with process.dlopen, then runs
#      `n8n --version` and a bounded editor smoke test on port 5678.
#
# Fallback: install-n8n-termux-ondevice-compile.sh compiles the natives
# on the phone instead (slow, needs the Termux toolchain).
#
# Usage:  bash install-n8n-termux.sh
#         SKIP_SMOKE=1 bash install-n8n-termux.sh   (skip the server test)

set -u
N8N_VER="2.44.4"
NATIVES_URL="https://github.com/wirawira941/n8n-termux/releases/download/v2.44.4-termux.2/n8n-android-natives.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== n8n $N8N_VER for Termux (prebuilt natives)"

if [ -z "${PREFIX:-}" ]; then
  echo "ERROR: \$PREFIX is not set — run this inside Termux." >&2
  exit 1
fi

echo "== Installing Termux packages: nodejs, libc++, curl, unzip"
pkg install -y nodejs libc++ curl unzip || {
  echo "ERROR: pkg install failed." >&2; exit 1; }

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$NODE_MAJOR" != "26" ]; then
  echo "ERROR: need Node 26, found Node $NODE_MAJOR ($(command -v node))." >&2
  echo "The isolated-vm binary is built for Node 26's V8 ABI (release" >&2
  echo "v2.44.4-termux.2). Termux's 'nodejs' package is currently Node 26;" >&2
  echo "if you have nodejs-lts installed instead, remove it and install" >&2
  echo "'nodejs'." >&2
  exit 1
fi
echo "== Node $(node --version) OK"

echo "== Installing n8n@$N8N_VER globally (install scripts disabled)"
npm install -g "n8n@$N8N_VER" --ignore-scripts --no-audit --no-fund || {
  echo "ERROR: npm install failed." >&2; exit 1; }

GROOT="$PREFIX/lib/node_modules/n8n"
[ -d "$GROOT" ] || { echo "ERROR: $GROOT not found after install." >&2; exit 1; }

echo "== Downloading prebuilt Android natives"
curl -fL -o "$WORK/natives.zip" "$NATIVES_URL" || {
  echo "ERROR: download failed: $NATIVES_URL" >&2; exit 1; }
unzip -o -q "$WORK/natives.zip" -d "$WORK/natives" || {
  echo "ERROR: could not unzip the natives package." >&2; exit 1; }

SQLITE_NODE="$(find "$WORK/natives" -name 'sqlite3.node' | head -1)"
IVM_NODE="$(find "$WORK/natives" -name 'isolated-vm.node' -o -name 'isolated_vm.node' | head -1)"
if [ -z "$SQLITE_NODE" ] || [ -z "$IVM_NODE" ]; then
  echo "ERROR: natives zip did not contain both .node files." >&2
  find "$WORK/natives" -type f >&2
  exit 1
fi

echo "== Placing native modules"
placed_s=0
while IFS= read -r d; do
  mkdir -p "$d/build/Release" "$d/lib/binding/napi-v6-android-arm64"
  cp "$SQLITE_NODE" "$d/build/Release/node_sqlite3.node"
  cp "$SQLITE_NODE" "$d/lib/binding/napi-v6-android-arm64/node_sqlite3.node"
  echo "   sqlite3     -> $d"
  placed_s=$((placed_s + 1))
done < <(find "$GROOT" -type d -name sqlite3 -path '*node_modules*')
placed_i=0
while IFS= read -r d; do
  mkdir -p "$d/build/Release"
  cp "$IVM_NODE" "$d/build/Release/isolated_vm.node"
  echo "   isolated-vm -> $d"
  placed_i=$((placed_i + 1))
done < <(find "$GROOT" -type d -name isolated-vm -path '*node_modules*')
if [ "$placed_s" = "0" ] || [ "$placed_i" = "0" ]; then
  echo "ERROR: placed sqlite3=$placed_s isolated-vm=$placed_i — a module dir is missing." >&2
  exit 1
fi

echo "== Load-testing the native modules"
fail=0
while IFS= read -r f; do
  if node -e 'const m={exports:{}};process.dlopen(m,process.argv[1])' "$f" 2>"$WORK/dlopen.err"; then
    echo "   OK   $f"
  else
    echo "   FAIL $f" >&2
    cat "$WORK/dlopen.err" >&2
    fail=1
  fi
done < <(find "$GROOT" \( -name node_sqlite3.node -o -name isolated_vm.node \) -path '*build/Release*')
[ "$fail" = "0" ] || { echo "ERROR: a native module failed to load (see above)." >&2; exit 1; }

echo "== n8n version"
n8n --version || { echo "ERROR: n8n --version failed." >&2; exit 1; }

if [ "${SKIP_SMOKE:-0}" != "1" ]; then
  echo "== Smoke test: starting n8n on http://127.0.0.1:5678 (max ~90 s)"
  LOG="$WORK/n8n-smoke.log"
  ( n8n start >"$LOG" 2>&1 & echo $! >"$WORK/n8n.pid" )
  ok=0
  for _ in $(seq 1 45); do
    sleep 2
    if curl -sf -o /dev/null "http://127.0.0.1:5678/"; then ok=1; break; fi
    kill -0 "$(cat "$WORK/n8n.pid")" 2>/dev/null || break
  done
  kill "$(cat "$WORK/n8n.pid" 2>/dev/null)" 2>/dev/null
  sleep 1
  kill -9 "$(cat "$WORK/n8n.pid" 2>/dev/null)" 2>/dev/null
  if [ "$ok" = "1" ]; then
    echo "   Smoke test PASSED — the editor answered on port 5678."
  else
    echo "   Smoke test FAILED — last log lines:" >&2
    tail -n 30 "$LOG" >&2
    exit 1
  fi
fi

echo ""
echo "Done. Run n8n with:  n8n start"
echo "Then open http://localhost:5678 in your browser (data lives in ~/.n8n)."
