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

## Second pass: Android on adb root (2026-11-16, `ro.build.version.release=17`, sdk 37)

- Android boots from **slot b** (`ro.boot.slot_suffix=_b`) — the same slot the bootloader reported as
  successful. So the phone's two OSes are swapped by flashing `boot`, not by A/B alone.
- `adb root` works on this LineageOS build; `/vendor/firmware` is readable as root.
- `/sys/firmware/fdt` pulled → `device-tree.dtb` (468 601 bytes) → `tools/soc-args.py` → `soc.args`:
  `soc_ipa_base=0x5840000`, `soc_gsi_base=0x5804000`, `soc_apps_smmu=0xc600000`, `soc_smem=0x46000000`,
  `soc_imem=0xc000000`, `soc_ipa_stream=0xe0`, `soc_ipa_stream_uc=0xe2`, `soc_pas_mpss=0x4`,
  `soc_pas_ipa=0xf`, `soc_ipa_fw=ipa_fws`.
- Firmware inventory pulled and split for `hakios-config.py needs`:

| dir | contents | size |
|---|---|---|
| `fw-gpu/` | `a610_zap.{b00,b01,b02,elf,mdt}`, `a630_sqe.fw`, `a630_gmu.bin` | 104 K |
| `fw-wifi/` | `bdwlan.*`, `wlanmdsp.mbn` (WCN3990) | 4.4 M |
| `fw-modem/` | `modem.{b*,mdt}` split images | 57 M |
| `fw-audio/` | `adsp.{b*,mdt}` split images | 16 M |

- Also on disk: the stock fastboot ROM `laurel_sprout_global_images_V12.0.26.0.RFQMIXM_11.0` (Android 11),
  which holds `NON-HLOS.bin` (112 M, the full modem image) and `dspso.bin` (32 M) — the fallback source if a
  split image is ever missing.

## 2026-11-16: UEFI runs; DxeCore faulted in a hole the QRD map left unmapped

The DEBUG build prints on the panel (FrameBufferSerialPortLib works). It dies at:

```
Loading driver at 0x0005D5E7000 EntryPoint=0x0005D5E7EA4 DxeCore.efi
Data abort: Translation fault, third level   ESR: EC 0x25 IL 0x1 ISS 0x6
ASSERT [ArmCpuDxe] pExceptionHandlerLib.c(438): (FALSE)
```

Cause: DXE core decompresses into the largest free block, and laurel's `MemoryMapLib.c` (inherited from the
QRD stub) left `0x5D000000-0x5F800000` out of the map.

The phone's own device tree, read from `/sys/firmware/fdt` (468 601 B), says that hole is normal RAM:

```
memory reg = <0x40000000 0x3dd00000  0x00c0000000 0x80000000  0x80000000 0x40000000>
reserved-memory: 0x5f800000+0x1e00000, 0x5c000000+0xf00000, 0x5cf00000+0x100000
```

so the fix is `{"Gap RAM", 0x5D000000, 0x02800000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK_XN}`
(`xnu-laurel-gap.img`), with `xnu-laurel-gapres.img` as the contrast case.

## Whole-map rebuild from the device tree

`MemoryMapLib.c` for laurel was inherited from the QRD stub and both under- and over-covered memory: the
`0x5D000000-0x5F800000` hole (DxeCore faulted at `0x5D5E7000`) and `PIL Reserved 0x4AB00000+0x0D200000`
(which swallowed the free ranges `0x4AB00000+0x500000` and `0x57517000+0x4AE9000`); a later run faulted at
`0x52FF8F54`, inside a DT carve-out the table did not describe.

The table is now generated from the phone's `/sys/firmware/fdt` `reserved-memory` node: every free range is
`SYS_MEM`, every carve-out `MEM_RES`, plus the FD/ABOOT/heap/stack entries, so nothing between
`0x40000000` and `0x7DD00000` is left undescribed. Generator output: `prebuilt/laurel-memory-table.c`
(37 entries). Image: `hakios-common/xnu-laurel-dtmap.img`.

## The FD executes: banner and overlap report on the panel

With `xnu-laurel-gap2.img` the panel finally shows UEFI itself, not a vendor splash:

```
Silicium UEFI (Mu-Silicium) for Xiaomi Mi A3
Firmware Version 4.0 Build at 00:08:53 on Nov 17 2026
RSV 45E00000 (0x45E00000) and AOP CMD DB (0x45F20000) overlap
RSV 57517000 (0x57517000) and Sched Heap (0x5BC00000) overlap
```

So SEC/PEI/DXE start and the framebuffer console works; the run stops on two overlaps the map
generator introduced. Fixed in `prebuilt/laurel-MemoryMapLib.c`:

- `RSV 45E00000` length `0x140000` -> `0x120000` (ends at `AOP CMD DB 0x45F20000`)
- `DDR 57517000` length `0x04AE9000` -> `0x046A9000` (ends at `Sched Heap 0x5BC00000`)

Checked mechanically: 25 entries, **0 overlaps**. Image: `hakios-common/xnu-laurel-gap3.img`.

## DXE dispatches drivers; the run stops at UFSDxe

`xnu-laurel-gap5.img` (whole MMIO window below 0x40000000 mapped as device) reaches DXE dispatch:

```
Loading driver at 0x… FvbServicesRuntimeDxe.efi / FvbDxe.efi / FaultTolerantWriteDxe.efi
Loading driver at 0x… PcdDxe.efi / RuntimeDxe.efi / StatusCodeDxeRuntimeDxe.efi
Loading driver at 0x… ArpDxe.efi / Dhcp4Dxe.efi / Dhcp6Dxe.efi / DiskIoDxe.efi / PartitionDxe.efi
Loading driver at 0x… UFSDxe.efi      <- last line before the reboot
```

UFSDxe is a prebuilt vendor binary (`Binaries/laurel_sprout/QcomPkg/Drivers/UFSDxe/UFSDxe.inf`) listed in the
port's `APRIORI.inc` and `DXE.inc`. It is not needed to start the loader or XNU (the payload arrives in RAM
from the boot shim), so both lines are commented out for the next test: `xnu-laurel-noufs.img`.
