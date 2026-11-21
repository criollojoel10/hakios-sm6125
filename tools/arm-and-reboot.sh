#!/bin/bash
# Arm slot a and restart into it, with the fallback checked first. Run ON laurel, as root, with the
# phone in hand: the result is only on the panel, and this Linux goes away until slot b starts again.
#
#   tools/arm-and-reboot.sh [IMAGE]   default: /var/lib/hakios/images/boot-laurel-noufs.img
set -euo pipefail
cd "$(dirname "$0")/.."
IMG=${1:-/var/lib/hakios/images/boot-laurel-noufs.img}
[ -f "$IMG" ] || { echo "arm-and-reboot: no image $IMG" >&2; exit 1; }
[ "$(id -u)" = 0 ] || exec sudo -n "$0" "$@"

tools/boot-slot-a.sh switch          # battery >= 60, backup verifies, writes nothing
tools/slot.sh to a                   # ABL will try _a; _b stays successful
echo
echo "Rebooting in 10 s. Watch the panel: UEFI banner -> DXE list -> == XNULOADER v3 =="
echo "To cancel: Ctrl-C now."
sleep 10
systemctl reboot
