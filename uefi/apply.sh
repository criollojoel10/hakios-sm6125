#!/bin/bash
# The laurel_sprout platform on HakiOS's UEFI: uefi/apply.sh (Mu-Silicium with HakiOS's changes and
# banner), with this phone's platform from files/ here -- which is Project Silicium's own
# Platforms/Xiaomi/laurel_sproutPkg, at the commit uefi/BASE names, plus whatever the revive needs.
set -euo pipefail
exec "$(dirname "$(readlink -f "$0")")/../../../uefi/apply.sh" laurel_sprout
