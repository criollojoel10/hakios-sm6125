# Dual boot on laurel: Linux on b, HakiOS on a

Two systems on the Mi A3, with the bootloader as the referee, and no step that can leave the phone with
nothing to start.

| | slot b (active today) | slot a |
|---|---|---|
| holds | Kupfer Linux (Arch Linux ARM) — the root on `sda15` | HakiOS's U-Boot, the loader and the payload |
| written by | the Kupfer install | `tools/slot.sh`/`fastboot flash boot_a` |
| fallback | it is the fallback | ABL retries it, then goes back to b |

## What has been checked on this phone

- bootloader unlocked, `current-slot: _b`, slot b `successful:yes`, slot a `successful:no`,
  `unbootable:yes`, both `boot_*` 64 MiB, `misc` 1 MiB, no `init_boot`.
- `qbootctl` (installed) reads the same state the bootloader reports:
  `SLOT _a: Active 0, Successful 0, Bootable 1` / `SLOT _b: Active 1, Successful 1, Bootable 1`.
- `misc`'s AOSP BCB carries a leftover `bootonce-bootloader` command; the slot state qbootctl reads
  comes from the boot LUN (`/dev/sde`)'s partition attributes, which is where ABL keeps it.
- A full backup exists at `/var/lib/hakios/backups/2026-11-21/` (boot_a, boot_b, dtbo_a/b,
  vbmeta_a/b, misc, devinfo, the LUN 4 GPT, and SHA256SUMS that `tools/slot.sh to` verifies first).

## The rule that makes it safe

**Only ABL changes the active slot.** On these phones `SetActiveSlot()` moves three things together (the
`_a`/`_b` bits, the type GUIDs of every pair, the boot LUN); `ValidateSlotGuids()` refuses a slot whose
GUIDs disagree, and then *no* image starts — Android's included. HakiOS learned that the hard way
(`docs/u-boot.md`: "Which slot is active is never U-Boot's to change"). So here the slot is changed with
`qbootctl` (the same request `fastboot set_active` makes) and never by editing bits by hand.

## Order of work

1. **Backup** — done. `tools/slot.sh backup` repeats it.
2. **Build the payload** (CI, heavy): `uefi.yml` for `SILICIUM_UEFI.fd` and the loader; the kernel and
   the loader come from `build-laurel.yml`. Nothing is written to the phone.
3. **Put U-Boot + loader + kernel in a boot image** for slot a (`tools/mkubootimg.py --install` in the
   common tree) and write it to `boot_a` *from Linux*, with `dd`/`fastboot`'s equivalent, only after the
   image boots in QEMU (`qemu-u-boot`) and the backup verifies.
4. **Switch once**: `tools/slot.sh to a`, reboot. U-Boot's menu chooses HakiOS or Linux.
5. **If it does not come back**: power off, power on. ABL's retries fall back to slot b because b is
   marked successful. If even that fails, begonia drives fastboot over USB and issues
   `fastboot set_active b` (then `fastboot reboot`).

## Why slot b survives

- `boot_b`, `dtbo_b` and `vbmeta_b` are never written; the backup has them anyway.
- Slot b is `successful:1`, so it is always a bootable candidate for ABL.
- `boot_a` is the only boot partition this work writes, and the backup can put it back with
  `dd if=boot_a.img of=/dev/disk/by-partlabel/boot_a`.

## Recovery from begonia (only if laurel does not come back)

Begonia is a phone, not a PC: it needs a USB-C OTG adapter and a USB-A to USB-C cable to act as host.

```sh
sudo pacman -S --needed android-tools
fastboot devices                 # laurel must answer
fastboot set_active b            # ABL's own command: the one that always works
fastboot reboot
```

`fastboot getvar current-slot` tells which one ABL thinks is active.
