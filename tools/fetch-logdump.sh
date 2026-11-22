#!/bin/sh
# Copy the loader/kernel log out of the physical logdump partition.
#
# The loader writes its staged log (loader log + "== KERNEL LOG ==" + kernel log)
# at offset 0 of /dev/disk/by-partlabel/logdump. The partition is 64 MiB; the
# staged buffer is at most 2 MiB, so read the first 2 MiB and keep both the raw
# bytes and a text extraction for analysis.
#
#   tools/fetch-logdump.sh [OUT.bin]      (default: /var/lib/hakios/logdump-<time>.bin)
set -eu
[ "$(id -u)" -eq 0 ] || exec sudo -n "$0" "$@"
OUT=${1:-/var/lib/hakios/logdump-$(date +%Y%m%d-%H%M%S).bin}
PART=/dev/disk/by-partlabel/logdump
[ -b "$PART" ] || { echo "fetch-logdump: no $PART" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
dd if="$PART" of="$OUT" bs=1M count=2 status=none
sync
strings -n 4 "$OUT" > "$OUT.txt"
echo "raw:  $OUT ($(stat -c %s "$OUT") bytes)"
echo "text: $OUT.txt ($(wc -l < "$OUT.txt") lines)"
