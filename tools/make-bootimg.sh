#!/bin/bash
# Build the laurel_sprout boot image in the format this bootloader accepts.
#
# Evidence (docs/PLAN.md, docs/BASELINE.md): the working Kupfer image on this phone is header v0 with the
# DTB appended and page size 4096, kernel at 0x10008000; the v1/2048 image built by the common tree's
# mkxnuimg.py did not bring the phone up (and `fastboot boot` is refused outright).
#
#   kernel  = gzip(BootShim + SILICIUM_UEFI.fd + XNUP payload)     (mkxnuimg builds this part)
#   dtb     = prebuilt/device-tree.dtb
#
# usage: tools/make-bootimg.sh [-p payload.bin] [-o boot-laurel.img]
set -euo pipefail
cd "$(dirname "$0")/.."
COMMON=${COMMON:-../hakios-common}
PRE=prebuilt
PAYLOAD=${1:-}
OUT=boot-laurel.img
while [ $# -gt 0 ]; do
  case "$1" in
    -p) PAYLOAD=$2; shift 2 ;;
    -o) OUT=$2; shift 2 ;;
    *) shift ;;
  esac
done
[ -f "$PRE/SILICIUM_UEFI.fd" ] || { echo "missing $PRE/SILICIUM_UEFI.fd (see prebuilt/README.md)" >&2; exit 1; }
base=0 kern=0x00008000 ram=0x01000000 tags=0x00000100
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. the Android "kernel" this bootloader jumps into: the shim that installs the FD and the payload
if [ -n "$PAYLOAD" ]; then
  "$COMMON/mkxnuimg.py" -d laurel_sprout -p "$PAYLOAD" -o "$tmp/stage.img" >/dev/null
else
  "$COMMON/mkxnuimg.py" -d laurel_sprout -o "$tmp/stage.img" >/dev/null
fi
# mkxnuimg already produced a boot image; take its kernel bytes back out (they are gzip)
python3 - "$tmp/stage.img" "$tmp/kernel.gz" <<'PY'
import struct, sys
raw = open(sys.argv[1], 'rb').read()
ksize = struct.unpack('<I', raw[8:12])[0]
page = struct.unpack('<I', raw[36:40])[0]
open(sys.argv[2], 'wb').write(raw[page:page + ksize])
PY

# 2. repack exactly like the Kupfer image that boots on this phone: header v0, page 4096, addresses
#    base 0 / kernel 0x8000 / ramdisk 0x1000000 / tags 0x100, and the DTB appended to the kernel (dt_size 0).
cat "$tmp/kernel.gz" "$PRE/device-tree.dtb" > "$tmp/kernel+dtb"
python3 "$PRE/mkbootimg.py" \
  --kernel "$tmp/kernel+dtb" --ramdisk "$PRE/ramdisk" \
  --base $base --kernel_offset $kern --ramdisk_offset $ram --tags_offset $tags \
  --pagesize 4096 --header_version 0 -o "$OUT"

python3 - "$OUT" <<'PY'
import struct, sys
raw = open(sys.argv[1], 'rb').read(4096)
ksize = struct.unpack('<I', raw[8:12])[0]
page, dtsize = struct.unpack('<I', raw[36:40])[0], struct.unpack('<I', raw[40:44])[0]
print(f'{sys.argv[1]}: kernel {ksize} B, page {page}, dt_size {dtsize} (0 or 1 means the DTB was not recorded)')
PY
