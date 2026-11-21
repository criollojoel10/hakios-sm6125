# Dual-boot test: Linux on b, HakiOS on a

Test procedure after the 2026-11-21 incident (GPT of the boot LUN left
inconsistent by the qbootctl switch; recovered with `gpt_both4.bin`).

**Rule: switch with the ABL (`fastboot set_active`), not with qbootctl, while
testing.** qbootctl only writes two of the three things ABL's `SetActiveSlot`
moves; a partial write can leave both slots unbootable.

## Inputs

- `SILICIUM_UEFI.fd` + `BootShim.bin` from the `uefi` workflow
  (`laurel-uefi` artifact; run 44920693365 produced 3 145 728 B / 112 B).
- `hakios-kernel` + `loader.efi` from `build-laurel`
  (`laurel-build` artifact; run 44919121380).
- `hakios-common` (`oosexgang/hakios-xnu-kernel`) for
  `xnuloader/mkpayload.py`.
- `prebuilt/device-tree-android.dtb`, `prebuilt/ramdisk`, `prebuilt/fd.conf`
  (in this repo).

## Build the boot image (on laurel, light step)

```sh
git clone https://github.com/criollojoel10/hakios-sm6125
git clone --depth 1 https://github.com/oosexgang/hakios-xnu-kernel hakios-common
# artifacts: gh run download ... -n laurel-uefi / laurel-build (or aria2c with
# the signed artifact URL)
cd hakios-sm6125
COMMON=../hakios-common tools/build-image.sh \
  -f ../uefi/SILICIUM_UEFI.fd -s ../uefi/BootShim.bin \
  -k ../build/hakios-kernel -l ../build/xnuloader/loader.efi \
  -o boot-laurel-xnu.img
```

Expected: header v0, page 4096, 7 245 824 B, sha256
`d4d7a4a714c31489be56e9c99b770365bc64f500cf3936190cbff8b742775a5c`
(2026-11-21 artifacts).

## Backup before writing anything

```sh
sudo tools/slot.sh backup          # boot_a/b, dtbo_a/b, vbmeta_a/b, misc,
                                   # devinfo, gpt.bin (LUN 4), SHA256SUMS
sudo cp -a /var/lib/hakios/backups/2026-* /home/user/  # copy to begonia
```

Also keep a copy of the stock `gpt_both4.bin` from the ROM (pmos-laurel-sprout
workflow `28-extract-stock-gpt`) on begonia, not only on the phone.

## Write slot a and switch

```sh
# on laurel, slot b is the working Linux
sudo tools/boot-slot-a.sh write boot-laurel-xnu.img   # dd + readback
sudo qbootctl -m b                                    # b is the fallback
```

Put laurel in fastboot (power off; Volume Down + Power) and, from begonia with
**fastboot 30.0.5**:

```sh
fastboot devices
fastboot set_active a
fastboot reboot
```

Watch the panel: `Silicium UEFI (Mu-Silicium) for Xiaomi Mi A3`, the DXE list,
then `== XNULOADER v3 ==`. If it stops or goes black, hold Power ~10 s and
choose slot b.

## Fallback / recovery

From a fastboot session on begonia:

```sh
fastboot set_active b
fastboot reboot
```

If the GPT itself is inconsistent (both slots fall to fastboot, retry counter
drops), restore only the boot LUN 4 from the stock ROM:

```sh
fastboot flash partition:4 gpt_both4.bin
for s in a b; do
  fastboot flash boot_$s boot.img        # Linux boot.img
  fastboot flash vbmeta_$s vbmeta.img
  fastboot erase dtbo_$s
done
fastboot set_active b
fastboot reboot
```

Never flash `gpt_both0.bin` (LUN 0 / userdata) for this.

## Host tools

- begonia: fastboot **30.0.5** (compiled from nmeum/android-tools) for the ABL.
- laurel: `android-tools` (latest) + `adb`, installed as host tooling; use
  aria2c as pacman `XferCommand`.
