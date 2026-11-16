# UEFI for the Xiaomi Mi A3 (laurel_sprout)

The loader chain is Project Silicium's **Mu-Silicium**, which already carries a platform for this phone:
`Platforms/Xiaomi/laurel_sproutPkg` (`.dsc`, `.fdf`, `DeviceBuild.py`, and a patched `ClockDxe`). On
Silicium's status page the port is listed **Inactive**: it builds, and it has not been kept up.

`apply.sh` here is the same two-line entry point the reference phone uses: it calls HakiOS's
`uefi/apply.sh <device>` in the common repository, which clones Mu-Silicium at `BASE`, applies
`hakios.patch` and this device's platform from `uefi/files/`.

## What has to be filled in

| What | Where it comes from | State |
|---|---|---|
| `uefi/files/` (this phone's platform) | Silicium's `Platforms/Xiaomi/laurel_sproutPkg` at `BASE` | to copy once, then carry differences as patches |
| `uefi/BASE` (the Silicium commit) | HakiOS's `uefi/BASE` | take the common one |
| `prebuilt/SILICIUM_UEFI.fd`, `BootShim.bin`, `device-tree.dtb`, `ramdisk` | `uefi/build.sh` + the phone's own boot image | not built yet |
| vendor DXEs (display, UFS, PMIC) | **never in this repository**: built from the phone's own firmware | not pulled yet |

## The known hazard

Silicium's laurel_sprout platform exists because SM6125 needs a **patched ClockDxe** (Silicium PR #71).
If the platform is taken from a newer commit than the patch, the phone hangs in UEFI with no console.
Pin `BASE` and keep the patch in `hakios.patch`; do not "update Silicium" without re-testing the phone.
