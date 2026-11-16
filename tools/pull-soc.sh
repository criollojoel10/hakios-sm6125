#!/bin/bash
# Pull the phone's own device tree and turn it into the soc_* values the kernel takes on the command
# line. Run with the phone on adb (Android booted). Writes soc.args and device-tree.dtb next to this repo.
#
# Needs the common repository's tools/soc-args.py: run this through `make` there, or point COMMON at a
# checkout. SM6125 note: soc_rsc (the RPMh controller) has no meaning on this SoC; its value is ignored.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${COMMON:=../..}"
if [ ! -f "$COMMON/tools/soc-args.py" ]; then
  echo "tools/soc-args.py not found in COMMON=$COMMON (clone oosexgang/hakios-xnu-kernel and sync)" >&2
  exit 1
fi
adb pull /sys/firmware/fdt device-tree.dtb
python3 "$COMMON/tools/soc-args.py" device-tree.dtb | tee soc.args
echo "review soc.args by hand: soc_smem, soc_cmd_db, soc_mpss_mem and soc_imem come from the reserved-memory nodes"
