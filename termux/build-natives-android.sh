#!/usr/bin/env bash
# Cross-compile n8n 2.44.4's two native deps for Android aarch64 (bionic)
# with the NDK, in GitHub Actions — an EXPERIMENT (user-approved 2026-10-20):
#
#   sqlite3 5.1.7    N-API module (ABI-independent once built) — expected OK.
#   isolated-vm 7.0.1 raw V8 addon, tied to Node ABI 137 (Node 24) — the
#                    hard one; no official Android support.
#
# Both are attempted even if one fails; results land in BUILD-RESULTS.txt
# and every produced .node is ELF-checked (must be ARM aarch64 and link
# bionic libc.so, NOT glibc libc.so.6). Output: n8n-android-natives.zip
# in the repo root. Expects env NDK_ROOT pointing at an extracted r28c.
set -uo pipefail

SQLITE_VER="5.1.7"
IVM_VER="7.0.1"
API_LEVEL="24"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"
OUT="$ROOT/out"
RESULTS="$OUT/BUILD-RESULTS.txt"

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

NDK_BIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CC="$NDK_BIN/aarch64-linux-android${API_LEVEL}-clang"
export CXX="$NDK_BIN/aarch64-linux-android${API_LEVEL}-clang++"
export AR="$NDK_BIN/llvm-ar"
export RANLIB="$NDK_BIN/llvm-ranlib"
export STRIP="$NDK_BIN/llvm-strip"

NODE_TARGET="$(node -v | sed 's/^v//')"
echo "Host node: $(node -v) | gyp target: $NODE_TARGET | CC: $CC"
{
  echo "n8n Android natives cross-compile — $(date -u +%FT%TZ)"
  echo "node-gyp target: $NODE_TARGET (Node ABI follows the major)"
  echo "NDK clang: $CC"
} > "$RESULTS"

check_node_file() {
  # $1 = path to a .node file; verifies arch + bionic linkage
  local f="$1"
  file "$f" | grep -q "ARM aarch64" || { echo "  !! not an aarch64 ELF"; return 1; }
  if "$NDK_BIN/llvm-readelf" -d "$f" 2>/dev/null | grep -q "libc\.so\.6"; then
    echo "  !! links glibc (libc.so.6) — would NOT load on Android"; return 1
  fi
  echo "  ok: aarch64 ELF, no glibc linkage"
  return 0
}

attempt() {
  # $1 = label, $2 = npm package spec, $3 = build command (run in src dir)
  local label="$1" spec="$2" buildcmd="$3"
  echo ""
  echo "================ $label ($spec) ================"
  echo "" >> "$RESULTS"
  echo "## $label ($spec)" >> "$RESULTS"
  local dir="$WORK/$label"
  mkdir -p "$dir" && cd "$dir"
  npm pack "$spec" >/dev/null 2>&1
  tar xzf ./*.tgz
  cd package
  if eval "$buildcmd" > "$dir/build.log" 2>&1; then
    echo "build command: OK" >> "$RESULTS"
  else
    echo "build command: FAILED (see build.log in the artifact)" >> "$RESULTS"
    tail -n 15 "$dir/build.log" >> "$RESULTS" 2>/dev/null
  fi
  local found=0
  while IFS= read -r f; do
    found=1
    echo "produced: $f ($(stat -c%s "$f") bytes)" >> "$RESULTS"
    cp "$f" "$OUT/$label.node"
    cp "$dir/build.log" "$OUT/$label-build.log"
    if check_node_file "$f" >> "$RESULTS" 2>&1; then
      echo "verdict: PASS" >> "$RESULTS"
    else
      echo "verdict: FAIL (bad ELF)" >> "$RESULTS"
      rm -f "$OUT/$label.node"
    fi
  done < <(find . -name "*.node" -path "*Release*" 2>/dev/null | head -3)
  [ "$found" = "0" ] && echo "produced: (no .node found)" >> "$RESULTS"
  cd "$ROOT"
}

GYP_FLAGS="--target=$NODE_TARGET --arch=arm64 --dist-url=https://nodejs.org/dist"

# sqlite3: node-pre-gyp drives its binding.gyp (sets module_name/path).
attempt "sqlite3" "sqlite3@$SQLITE_VER" \
  "npx --yes @mapbox/node-pre-gyp rebuild $GYP_FLAGS"

# isolated-vm: plain node-gyp.
attempt "isolated-vm" "isolated-vm@$IVM_VER" \
  "npx --yes node-gyp rebuild $GYP_FLAGS"

echo ""
cat "$RESULTS"
cd "$OUT"
zip -q "$ROOT/n8n-android-natives.zip" ./* 2>/dev/null || \
  zip -q "$ROOT/n8n-android-natives.zip" BUILD-RESULTS.txt
ls -lh "$ROOT/n8n-android-natives.zip"
