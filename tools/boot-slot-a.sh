#!/bin/bash
# Put a built image in slot a (the inactive one) and, only if asked, ask ABL to start it next.
# Slot b (Linux) is never written. Run on laurel as root.
#
#   tools/boot-slot-a.sh write boot-laurel.img   image -> boot_a, read back and compared
#   tools/boot-slot-a.sh switch                  qbootctl -s a; takes effect at the next start
#   tools/boot-slot-a.sh preflight               battery, backups, slots, image
set -euo pipefail
cd "$(dirname "$0")/.."
BK=${HAKIOS_BACKUP:-/var/lib/hakios/backups/2026-11-21}
BOOT_A=/dev/disk/by-partlabel/boot_a
die() { echo "boot-slot-a: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || exec sudo -n "$0" "$@"; }

preflight() {
	local cap
	cap=$(cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1)
	[ -n "$cap" ] || die "no battery capacity (do not run this unattended without one)"
	# a write is a few megabytes and can be done at a moderate charge; a start cannot (the UEFI/loader
	# session does not charge, and a flat battery in the loader is how a phone goes quiet).
	[ "$cap" -ge "${MIN_BATTERY:-60}" ] || die "battery at ${cap}%, needs >= ${MIN_BATTERY:-60}% (the UEFI session does not charge)"
	echo "battery: ${cap}%"
	[ -f "$BK/SHA256SUMS" ] || die "no backup in $BK"
	( cd "$BK" && sha256sum -c --quiet SHA256SUMS ) || die "backup does not verify"
	echo "backup: ok in $BK"
	qbootctl
	qbootctl -c | grep -q '_b' || die "slot b is not current; this script only writes the inactive slot"
	echo "slot: current _b, safe to write _a"
}

case "${1:-preflight}" in
preflight) need_root "$@"; preflight ;;
write)
	need_root "$@"
	MIN_BATTERY=20 preflight
	img=${2:-}; [ -f "$img" ] || die "usage: $0 write IMAGE"
	size=$(stat -c %s "$img")
	part=$(blockdev --getsize64 "$BOOT_A")
	[ "$size" -le "$part" ] || die "image $size > boot_a $part"
	python3 - "$img" <<'PY'
import struct, sys
raw=open(sys.argv[1],'rb').read(4096)
ver=struct.unpack('<I',raw[40:44])[0]; page=struct.unpack('<I',raw[36:40])[0]
assert raw[:8]==b'ANDROID!' and ver==0 and page==4096, 'not an ANDROID! v0/page4096 image'
print(f'image: ANDROID! v0 page {page}')
PY
	dd if="$img" of="$BOOT_A" bs=1M conv=fsync status=none
	# read back what was written, not what the cache says
	# count_bytes: no `head` closing the pipe under dd (that was a SIGPIPE, not a write error)
	got=$(dd if="$BOOT_A" bs=1M iflag=count_bytes count="$size" status=none | sha256sum | cut -d' ' -f1)
	want=$(sha256sum "$img" | cut -d' ' -f1)
	[ "$got" = "$want" ] || die "read-back mismatch ($got != $want)"
	echo "boot_a: written $size bytes, read back identical"
	echo "next: $0 switch, then reboot and watch the screen"
	;;
switch)
	need_root "$@"
	MIN_BATTERY=60 preflight
	qbootctl -s a
	sync
	echo "slot: ABL will try _a at the next start; _b stays successful, so a failed start falls back"
	;;
*) die "usage: $0 {preflight|write IMAGE|switch}" ;;
esac
