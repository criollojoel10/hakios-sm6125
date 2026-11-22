#!/bin/sh
# Copy the XNU loader's pstore/ramoops records to /var/lib/hakios and clear
# them, so each test leaves a timestamped text file. Run as root (or through
# hakios-pstore-collect.service at boot).
set -eu
dst=${1:-/var/lib/hakios}
mkdir -p "$dst"
set -- /sys/fs/pstore/dmesg-ramoops-* /sys/fs/pstore/console-ramoops-*
[ -e "$1" ] || exit 0
stamp=$(date -u +%Y%m%dT%H%M%SZ)
out="$dst/xnu-log-$stamp.txt"
: > "$out"
for f in "$@"; do
	[ -f "$f" ] || continue
	printf '===== %s =====\n' "$(basename "$f")" >> "$out"
	cat "$f" >> "$out"
	printf '\n' >> "$out"
	: > "$f"          # pstore erase
done
ln -sfn "$out" "$dst/xnu-log-latest.txt"
printf '%s %s\n' "$(date -Is)" "$out" >> "$dst/pstore-collect.log"
echo "$out"
