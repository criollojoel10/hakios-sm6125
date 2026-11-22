#!/bin/sh
# Put laurel in ABL fastboot from Linux.
#
# `reboot bootloader` reaches the qcom-pon reboot-mode driver, whose modes are
# "bootloader recovery"; ABL honours the reason and starts fastboot. This is the
# route that works on this phone. The Android BCB (`bootonce-bootloader` in the
# LUN 0 `misc`) is ignored by this ABL, and `fastboot boot` answers "unknown
# command": flash the image to boot_a instead.
set -eu
[ "$(id -u)" -eq 0 ] || exec sudo -n "$0" "$@"
echo "rebooting to fastboot (reboot bootloader)"
exec reboot bootloader
