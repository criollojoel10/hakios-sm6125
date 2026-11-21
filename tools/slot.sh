#!/bin/bash
# laurel_sprout: which slot starts, and the way back. Run ON the phone (laurel), as root.
#
#   tools/slot.sh status            where the bootloader says we are (qbootctl)
#   tools/slot.sh backup            copy the boot-related partitions and the LUN 4 GPT to /var/lib/hakios/backups
#   tools/slot.sh to a|b            ask ABL for the other slot (what `fastboot set_active` does)
#   tools/slot.sh rollback          back to Linux: slot b, marked successful
#
# The slot is ABL's, not ours: `to` only writes the metadata ABL reads, and ABL itself does the rest at
# the next start (the _a/_b type GUIDs and the boot LUN). Nothing here trusts that: `rollback` is a
# one-line command, and docs/DUAL-BOOT.md has the recovery from another machine on the cable.
set -euo pipefail
BK=${HAKIOS_BACKUP:-/var/lib/hakios/backups/2026-11-21}
PARTS="boot_a boot_b dtbo_a dtbo_b vbmeta_a vbmeta_b misc devinfo"
LUN=${HAKIOS_LUN:-/dev/sde}

die() { echo "slot: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || exec sudo -n "$0" "$@"; }

case "${1:-status}" in
status)
	need_root "$@"
	qbootctl
	echo "current: $(qbootctl -c)"
	;;
backup)
	need_root "$@"
	mkdir -p "$BK"
	for p in $PARTS; do
		[ -e "/dev/disk/by-partlabel/$p" ] || die "no partition $p"
		dd if="/dev/disk/by-partlabel/$p" of="$BK/$p.img" bs=1M status=none
	done
	sgdisk --backup="$BK/gpt.bin" "$LUN" >/dev/null 2>&1 || true   # ABL's table may differ from its backup header
	( cd "$BK" && sha256sum *.img gpt.bin > SHA256SUMS
	  { echo "date: $(date -Is)"; echo "slot: $(qbootctl -c)"; } > MANIFEST )
	echo "slot: backup in $BK ($(du -sh "$BK" | cut -f1))"
	;;
to)
	need_root "$@"
	slot=${2:-}
	case "$slot" in a|b) ;; *) die "usage: slot.sh to a|b" ;; esac
	[ -f "$BK/SHA256SUMS" ] || die "no backup in $BK; run: tools/slot.sh backup"
	( cd "$BK" && sha256sum -c --quiet SHA256SUMS ) || die "backup does not verify; refusing to switch"
	qbootctl -s "$slot"
	# asking for a slot clears its "successful" flag (it is a new attempt); the *other* one must keep it,
	# because it is the fallback
	if [ "$slot" = a ]; then qbootctl -m b; else qbootctl -m b; fi
	sync
	echo "slot: asked ABL for _$slot; $(qbootctl -c) now, it takes effect at the next start"
	;;
rollback)
	need_root "$@"
	qbootctl -s b
	qbootctl -m b
	sync
	echo "slot: Linux (b) is the active slot and is marked successful"
	qbootctl
	;;
*)
	die "usage: slot.sh {status|backup|to a|b|rollback}"
	;;
esac
