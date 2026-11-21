#!/bin/bash
# Build the laurel_sprout boot image for slot a from three pieces:
#
#   SILICIUM_UEFI.fd   the UEFI firmware (artifact "laurel-uefi" of the uefi workflow)
#   BootShim.bin       the stub that installs the FD and copies the payload (same artifact, or built here)
#   payload.bin        kernel + loader + boot arguments, an XNUP container (common/xnuloader/mkpayload.py)
#
# The result is the layout this phone's ABL accepts for `boot_a` (header v0, page 4096, DTB appended to
# the gzipped kernel), the one the Kupfer image on slot b uses. Nothing is flashed: say where the image
# goes and check it first.
#
#   tools/build-image.sh -f path/SILICIUM_UEFI.fd -s path/BootShim.bin -k kernel -l loader.efi \
#                        [--cmdline "-v"] [-o boot-laurel.img]
#
# Env: COMMON (default ../../common), FD_BASE/FD_SIZE from prebuilt/fd.conf.
set -euo pipefail
cd "$(dirname "$0")/.."
COMMON=${COMMON:-../../common}
OUT=boot-laurel.img
FD="" SHIM="" KERNEL="" LOADER="" CMDLINE="-v"
while [ $# -gt 0 ]; do
	case "$1" in
		-f) FD=$2; shift 2 ;;
		-s) SHIM=$2; shift 2 ;;
		-k) KERNEL=$2; shift 2 ;;
		-l) LOADER=$2; shift 2 ;;
		--cmdline) CMDLINE=$2; shift 2 ;;
		-o) OUT=$2; shift 2 ;;
		*) echo "build-image: unknown $1" >&2; exit 2 ;;
	esac
done

die() { echo "build-image: $*" >&2; exit 1; }
[ -f "$FD" ] || die "no FD (-f); it comes from the uefi workflow's artifact"
[ -f "$SHIM" ] || die "no BootShim.bin (-s)"
[ -f "$KERNEL" ] || die "no kernel (-k)"
[ -f "$LOADER" ] || die "no loader (-l)"
[ -f "$COMMON/xnuloader/mkpayload.py" ] || die "no $COMMON/xnuloader/mkpayload.py (set COMMON=)"
BASE=$(sed -n 's/^base=//p' prebuilt/fd.conf)
SIZE=$(sed -n 's/^size=//p' prebuilt/fd.conf)
[ -n "$BASE" ] && [ -n "$SIZE" ] || die "prebuilt/fd.conf has no base/size"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# 1. the XNUP payload the loader finds at 0xF0000000
python3 "$COMMON/xnuloader/mkpayload.py" -o "$tmp/payload.bin" \
	kernel="$KERNEL" ramdisk="$LOADER" --cmdline "$CMDLINE" >/dev/null
python3 - "$tmp/payload.bin" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
assert d[:4]==b'XNUP', 'payload is not an XNUP container'
print(f'payload: {len(d)} bytes')
PY

# 2. kernel = gzip(BootShim + FD + payload) + DTB, as mkxnuimg.py does for redwood
DTB=prebuilt/device-tree.dtb
[ -f "$DTB" ] || DTB=prebuilt/device-tree-android.dtb
[ -f "$DTB" ] || die "no device tree (prebuilt/device-tree*.dtb)"
python3 - "$SHIM" "$FD" "$SIZE" "$tmp/payload.bin" "$DTB" "$tmp/kernel.gz" <<'PY'
import gzip, sys
shim_p, fd_p, size, pay_p, dtb_p, out = sys.argv[1:7]
shim=open(shim_p,'rb').read(); fd=open(fd_p,'rb').read(); pay=open(pay_p,'rb').read()
assert len(fd)==int(size,16), f'FD is {len(fd)} bytes, fd.conf says {size}'
blob=(shim+fd+pay); blob+=b'\0'*(-len(blob)%16)
open(out,'wb').write(gzip.compress(blob,6)+open(dtb_p,'rb').read())
print(f'kernel: shim {len(shim)} + fd {len(fd)} + payload {len(pay)} = {len(blob)} gzipped, + dtb')
PY

# 3. header v0, page 4096, the addresses the Kupfer image on slot b uses
python3 prebuilt/mkbootimg.py --kernel "$tmp/kernel.gz" --ramdisk prebuilt/ramdisk \
	--base 0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 --tags_offset 0x100 \
	--pagesize 4096 --header_version 0 -o "$OUT"

python3 - "$OUT" <<'PY'
import struct, sys
raw=open(sys.argv[1],'rb').read(4096)
ver=struct.unpack('<I',raw[40:44])[0]
ksize=struct.unpack('<I',raw[8:12])[0]
page=struct.unpack('<I',raw[36:40])[0]
print(f'{sys.argv[1]}: header v{ver}, kernel {ksize} B, page {page}, total {__import__("os").path.getsize(sys.argv[1])} B')
assert ver==0 and page==4096, 'unexpected header; ABL wants v0/page 4096 on this phone'
PY
