#!/bin/bash
# Pull this phone's firmware off Android (needs `adb` and a rooted shell or `adb root`) into fw-*/ at the
# top of the repository. Nothing here is redistributable: the files are the vendor's and are gitignored.
#
# laurel_sprout (SM6125) pieces the port needs, and where they live on the phone:
#   fw-gpu/     a610_zap.mbn, a630_sqe.fw            /vendor/firmware, /firmware/image
#   fw-wifi/    WCN3990 board files (bdwlan*, wlanmdsp.mbn)   /vendor/firmware, /firmware/image
#   fw-modem/   modem.mbn / NON-HLOS image           /firmware/image (or dump the modem partition)
#   fw-adsp/    adsp.mbn (+ adsp split images)       /firmware/image
#   fw-audio/   ACDB/ADCM calibration (.acdb/.bin)   /vendor/etc, /persist
#   fw-touch/   FT3518 firmware, if the panel needs it  /vendor/firmware
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ADB:=adb}"
adbd=$($ADB shell id -u 2>/dev/null | tr -d '\r')
if [ "$adbd" != "0" ]; then
  echo "adb shell is not root (uid=$adbd): run 'adb root' (userdebug stock) or use a rooted shell" >&2
  exit 1
fi
pull() { # pull <remote> <local dir>
  mkdir -p "$2"
  $ADB pull "$1" "$2/" 2>&1 | tail -n 1
}
for src in /vendor/firmware /firmware/image; do
  pull "$src" "fw-$(basename "$src")"
done
pull /vendor/etc/acdbdata fw-audio
pull /persist fw-persist
echo "pulled. what is missing is named in the header of this script; record the counts in docs/PLAN.md"
