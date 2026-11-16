# Baseline: the phone as it is, 2026-11-16

Read with **fastboot 30.0.5** (`tools/platform-tools-30.0.5`, gitignored). fastboot 37 (android-tools
37.0.0p1, the distro package) hangs on `getvar all` against this bootloader; the r30 build answers in
milliseconds. That is a tooling constraint of this port, not a preference.

Raw dump: `docs/fastboot-all.txt` (211 lines).

| Fact | Value |
|---|---|
| product | `laurel_sprout` |
| unlocked | `yes`, `anti:0` |
| storage | `SM_ UFS` |
| slots | 2, **current: b** |
| slot b | `successful:yes`, `unbootable:no`, retry 6 → Kupfer/Arch is on b |
| slot a | `successful:no`, `unbootable:yes` → stock/LineageOS slot is marked failed by the bootloader |
| `boot_a`, `boot_b` | 64 MiB (`0x4000000`) |
| `dtbo_b` | 24 MiB, `vbmeta_b` 64 KiB |
| `modem_a` | 180 MiB (`0xB400000`), A/B |
| `userdata` | 0x1AFA5F3000 ≈ 108 GiB |
| `init_boot` | **does not exist** (no `has-slot:init_boot`) |

## What this changes for the port

1. **No `init_boot`.** HakiOS's install screen lives in `init_boot.img`; the Mi A3 (Android 9 → 11, A/B
   but pre-`init_boot`) has no such partition. The loader/installer has to live in the `boot` image
   ramdisk, next to the kernel — the arrangement the project already uses for U-Boot-in-`boot_a`.
2. **Slot a is not a fallback right now.** The bootloader marks it unbootable; the rollback path is
   `fastboot --set-active=a` plus a working image there, not a passive "the other slot still has Android".
   Reflash stock to a before relying on it.
3. **The phone runs from b.** HakiOS writing the *inactive* slot means writing `boot_a`, which today
   boots nothing: no conflict with Kupfer, but also no dual-boot safety net until a is restored.
4. **`userdata` is Kupfer's rootfs** (ext4 on `sda15` per the Kupfer manifests), not Android's data.
   Carving `darwin` out of the end of `userdata` (HakiOS's install step) would cut into that filesystem:
   shrink it first, or use a dedicated free region.
