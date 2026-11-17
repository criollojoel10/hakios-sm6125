#!/bin/bash
# Flash a boot image to the inactive slot on laurel_sprout and watch whether the phone comes back on USB.
# Nothing else is written: no vbmeta beyond the one-time command below, no userdata, no partition table.
#
#   tools/flash-and-test.sh [IMAGE] [--recover]
#
#   IMAGE      default: ../hakios-common/xnu-laurel_sprout.img
#   --recover  only set the active slot back to b (the working Android/Kupfer slot) and exit
#
# The bootloader refuses `fastboot boot` on this phone, so a slot write is the only way to try an image.
set -euo pipefail
cd "$(dirname "$0")/.."
FB=./tools/platform-tools-30.0.5/platform-tools/fastboot
IMG=${1:-../hakios-common/xnu-laurel_sprout.img}
[ "${1:-}" = "--recover" ] && IMG=""
export PATH=$PWD/tools/platform-tools-30.0.5/platform-tools:$PATH

$FB devices | grep -q . || { echo "no phone in fastboot (Power 10 s, then Power+VolDown)" >&2; exit 1; }

if [ "$IMG" = "" ]; then
  $FB set_active b
  $FB reboot-bootloader >/dev/null 2>&1 || true
  echo "active slot: $($FB getvar current-slot 2>&1 | awk -F': ' '/current-slot/{print $2}')"
  exit 0
fi
[ -f "$IMG" ] || { echo "missing image: $IMG" >&2; exit 1; }

echo "== image header"
python3 - "$IMG" <<'PY'
import struct, sys
raw = open(sys.argv[1], 'rb').read(4096)
ver = struct.unpack('<I', raw[40:44])[0]
ksize, kaddr = struct.unpack('<I', raw[8:12])[0], struct.unpack('<I', raw[12:16])[0]
page = struct.unpack('<I', raw[40:44])[0] if ver == 0 else struct.unpack('<I', raw[36:40])[0]
print(f"header_version={ver} kernel={ksize} kernel_addr={kaddr:#x} page={page}")
PY

echo "== slot before: $($FB getvar current-slot 2>&1 | awk -F': ' '/current-slot/{print $2}')"
$FB flash boot_a "$IMG"
$FB set_active a
$FB reboot-bootloader >/dev/null 2>&1 || true   # this is what clears slot-unbootable:a on this bootloader
$FB set_active a >/dev/null
echo "== slot after:  $($FB getvar current-slot 2>&1 | awk -F': ' '/current-slot/{print $2}'), unbootable a: $($FB getvar slot-unbootable:a 2>&1 | awk -F': ' '/slot-unbootable/{print $2}')"
$FB reboot >/dev/null
for i in $(seq 1 18); do
  sleep 5
  if $FB devices | grep -q .; then echo "USB: fastboot after $((i*5))s"; exit 0; fi
  if adb devices | grep -qw device; then echo "USB: adb after $((i*5))s"; exit 0; fi
done
echo "no USB device after 90 s: look at the screen (HakiOS banner / vendor splash / black) and run"
echo "  tools/flash-and-test.sh --recover    # back to slot b"
exit 2
