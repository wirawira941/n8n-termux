#!/data/data/com.termux/files/usr/bin/bash
# n8n 2.44.4 on Termux (Android aarch64) — installer.
#
# n8n ships a prebuilt dist and an official CLI, so there is nothing to
# build in CI. The work happens here: two native deps have NO Android
# prebuilds and compile on-device during npm install —
#   sqlite3      (small C compile, usually a few minutes)
#   isolated-vm  (large C++ compile against V8 headers; the long pole,
#                 can take a long while and most of the RAM)
# Keep the phone plugged in and be patient on the install step.
#
# Usage:  bash install-n8n-termux.sh
#         SKIP_SMOKE=1 bash install-n8n-termux.sh   (skip the smoke test)
set -u

N8N_VERSION="2.44.4"
PORT="${N8N_PORT:-5678}"

echo "== n8n $N8N_VERSION Termux installer =="

echo "-- Installing Termux packages (nodejs, python, clang, make)..."
pkg install -y nodejs python clang make || {
  echo "GAGAL memasang paket Termux. Coba 'pkg update' dulu, lalu jalankan ulang."
  exit 1
}

NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
echo "-- Node version: $(node -v 2>/dev/null)"
if [ "$NODE_MAJOR" -lt 24 ]; then
  echo "n8n $N8N_VERSION butuh Node >= 24, terpasang v$NODE_MAJOR."
  echo "Paket 'nodejs' Termux adalah yang benar (bukan 'nodejs-lts' yang masih 22)."
  echo "Jalankan: pkg install -y nodejs   lalu jalankan ulang installer ini."
  exit 1
fi

# Keep native builds from eating the phone: bound job parallelism.
export npm_config_jobs=2
export MAKEFLAGS="-j2"

echo "-- Installing n8n@$N8N_VERSION globally (native modules compile here;"
echo "   sqlite3 sebentar, isolated-vm lama — biarkan saja, jangan ditutup)..."
if ! npm install -g "n8n@$N8N_VERSION"; then
  echo ""
  echo "npm install GAGAL. Penyebab paling mungkin: compile sqlite3 atau"
  echo "isolated-vm. Tempelkan ~30 baris terakhir output di atas ke Muse"
  echo "supaya bisa didiagnosis (ada jalur cadangan untuk keduanya)."
  exit 1
fi

echo "-- Terpasang: $(n8n --version 2>/dev/null || echo '(n8n --version gagal)')"

if [ "${SKIP_SMOKE:-0}" = "1" ]; then
  echo "-- Smoke test dilewati (SKIP_SMOKE=1)."
else
  echo "-- Smoke test: menyalakan server di port $PORT (maks ~90 detik)..."
  LOG="$(mktemp)"
  N8N_PORT="$PORT" n8n start >"$LOG" 2>&1 &
  SRV=$!
  OK=0
  for i in $(seq 1 30); do
    sleep 3
    CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null || echo 000)"
    if [ "$CODE" = "200" ]; then OK=1; break; fi
    kill -0 "$SRV" 2>/dev/null || break
  done
  kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
  if [ "$OK" = "1" ]; then
    echo "   SMOKE TEST LULUS: editor n8n menjawab HTTP 200 di port $PORT."
  else
    echo "   SMOKE TEST GAGAL — 25 baris terakhir log server:"
    tail -n 25 "$LOG"
    echo "   (Tempelkan log ini ke Muse untuk diagnosis.)"
  fi
  rm -f "$LOG"
fi

echo ""
echo "Selesai. Menjalankan n8n:"
echo "  n8n            (atau: n8n start)"
echo "Lalu buka http://localhost:$PORT di browser HP dan buat akun owner."
echo "Data & workflow tersimpan di ~/.n8n (SQLite)."
echo "Kalau mau diakses dari laptop di hotspot yang sama, jalankan:"
echo "  N8N_HOST=0.0.0.0 n8n   — pastikan akun owner sudah dibuat dulu."
