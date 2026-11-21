#!/bin/bash
# Runs at every Linux start (systemd, root). Two jobs:
#   1. mark this slot successful, so ABL always has a fallback even after a trial boot of slot a;
#   2. leave evidence for the next session: where the slot metadata is, and what the loader wrote to
#      logdump during a HakiOS attempt.
set -u
OUT=/var/lib/hakios/last-boot.txt
mkdir -p /var/lib/hakios
{
	echo "== $(date -Is) =="
	echo "cmdline: $(cat /proc/cmdline)"
	echo "bootreason: $(tr ' ' '\n' </proc/cmdline | sed -n 's/^androidboot.bootreason=//p')"
	echo
	echo "-- qbootctl before --"
	qbootctl 2>&1
} > "$OUT"

# current slot, as the kernel was told
slot=$(tr ' ' '\n' </proc/cmdline | sed -n 's/^androidboot.slot_suffix=//p')
[ -n "$slot" ] && qbootctl -m "${slot#_}" >> "$OUT" 2>&1

{
	echo
	echo "-- qbootctl after --"
	qbootctl 2>&1
	echo
	echo "-- logdump (loader's own log, if any) --"
	if [ -b /dev/disk/by-partlabel/logdump ]; then
		strings -n 6 /dev/disk/by-partlabel/logdump | tail -200
	else
		echo "no logdump partition"
	fi
} >> "$OUT" 2>&1
exit 0
