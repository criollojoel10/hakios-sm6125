# Journal

Dated record of what was run, where, and what it proved. One entry per working session; a claim is
only here if a command produced the line next to it.

## 2026-11-21 — work moved onto the phone itself (laurel) and onto CI

**Where.** Arch Linux ARM (aarch64) running *on the phone*: `laurel` = Xiaomi Mi A3, `laurel_sprout`,
SM6125, kernel `7.2.6-sm61x5`, 8 cores, 3.4 GB RAM, no `/dev/kvm`. The phone is the host, so it cannot
`fastboot boot` itself; that needs a second machine on the cable.

**Toolchain installed on laurel** (pacman): `base-devel`, `clang` 23.1.5, `lld`, `llvm`, `cmake`,
`ninja`, `dtc`, `ccache`, `qemu-system-aarch64` 11.1.3, `python-yaml`, `flex`, `bison`, `m4`,
`autoconf`, `automake`, `libtool`, `rsync`. zram (2 GB, zstd) enabled as swap for the builds.

**Gates run here**

| Gate | Command | Result |
|---|---|---|
| Common tree | `tools/hakios-device.py sync` | redwood + hakios-uefi cloned; `devices/laurel_sprout` in place |
| Configuration | `make laurel_sprout_defconfig` | `.config made from defconfig, common_defconfig, sm6125.config, laurel_sprout.config, laurel_sprout_defconfig`; `106 characters of boot-arguments`; `kernel.ver=2.3.4-hakios-darwin22.5-sm6125-g63fc2b46` |
| Machine | `make doctor` | `qemu-system-aarch64: make qemu-open works`; **fails** on 7-Zip (only needed for an IPSW) and on no aarch64 UEFI firmware (Arch Linux ARM packages none) |

**What laurel cannot do, and where it goes instead**

| Work | Why not here | Where |
|---|---|---|
| XNU build | 3.4 GB RAM, phone also runs a desktop; a full build is the one thing that would OOM it | GitHub Actions `build-laurel.yml` (ccache, artifacts: kernel, loader, `.config`, logs) |
| Boot log of XNU | no KVM, and the phone cannot fastboot itself | GitHub Actions `qemu-open.yml`: `make qemu-open` on the runner, log as an artifact |
| UEFI (Mu-Silicium) | needs the vendor DXEs (`Binaries/laurel_sprout/`), which are not in git | extraction from the phone's own `xbl_a` (`/dev/sdb1`, readable here) with UEFIReader, then a local build |
| Real boot | `xl enter` needs a host on the USB cable | a second device (begonia, USB-C OTG) driving `fastboot` |

**Where the port stands (from `docs/BASELINE.md`, unchanged by this session).** UEFI executes and shows
its banner on the panel; DXE dispatches drivers and stops right after `UFSDxe.efi`. The next image
(`xnu-laurel-noufs.img`) removes the vendor UFS driver from `APRIORI.inc` / `DXE.inc`; it has not been
built or run yet, because the build needs the vendor DXEs.

### What the two workflows produced (same day)

| Job | Result |
|---|---|
| `qemu-open` | **XNU booted in QEMU**: `== XNULOADER v3 ==`, `hello hakios-kernel!`, `Darwin Kernel Version 22.5.0 ... runner:xnu-8796.121.2`, `hakios-kernel: 25 drivers built in (...)`, `hakios-kernel: version 2.3.4-hakios-darwin22.5-g63fc2b46`, `Hello from user space on Darwin!`, then the expected `panic: initproc failed to start` after `hello` exits. Log kept as artifact `qemu-open-logs` (32 KB). |
| `build-laurel` | kernel for laurel_sprout built and uploaded: `hakios-kernel` 15.7 MB, `loader.efi` 66 048 B; `logs/config.txt` shows `CONFIG_DEVICE="laurel_sprout"`, `CONFIG_SOC="sm6125"`, `CONFIG_CPUS=8`. `kernel.ver` was not written by this path yet. |
| `uefi` | failed: the common checkout has no `uefi/`, which comes from `hakios-uefi`; the workflow now clones it first. Not re-run yet. |

### Slot and backups (read-only so far)

- `qbootctl` reads what ABL reports: `_a` active 0 / successful 0 / bootable 1, `_b` active 1 /
  successful 1 / bootable 1; current `_b`.
- `misc` holds a leftover AOSP BCB `bootonce-bootloader`; the slot state qbootctl reads lives in the boot
  LUN's (`/dev/sde`) partition attributes.
- Backup at `/var/lib/hakios/backups/2026-11-21/`: boot_a, boot_b, dtbo_a/b, vbmeta_a/b, misc, devinfo,
  `gpt.bin` and a verified SHA256SUMS (178 MB). `sgdisk` warns the LUN 4 backup header disagrees with the
  main table — recorded, not repaired (ABL keeps its own layout).
- `tools/slot.sh`: `status`, `backup`, `to a|b`, `rollback`; `to` refuses unless the backup verifies.
  **Nothing has been written to a boot partition or to the slot metadata.**

### Hardware side: the image is in boot_a and the slot switch works

- **UEFI built on CI twice, byte-identical**: `SILICIUM_UEFI.fd` 3 145 728 B,
  `sha256 315e263f…f6f748` in runs 44920607280 and 44920693365; `UFSDxe` appears 0 times in the build
  log (the driver is out of `APRIORI.inc`/`DXE.inc`), `BootShim.bin` 112 B with `FD_BASE=0x5FC00000`,
  `FD_SIZE=0x300000` in its header.
- **Boot image built here** from that FD, the shim and the CI kernel+loader:
  `boot-laurel-noufs.img`, 7 245 824 B, `ANDROID!` v0 / page 4096, gzip member 19 003 408 B
  decompressing, the 468 601 B device tree appended (`d00dfeed`), `XNUP` at offset 3 145 840.
- **Written to `boot_a`** and read back identical:
  `sha256 414120aa…76991`; slot b untouched.
- **Slot switch verified** with a patched `qbootctl` (see DUAL-BOOT.md): `_a` went Active 1 with `_b`
  kept Successful 1, then back to `_b` Active 1 Successful 1. `qbootctl -s` clears the target's
  successful bit, so the fallback is re-marked each time.
- **Not done**: the reboot into slot a. It needs a person watching the panel (there is no console to
  fetch) and a battery over 60 % (55 % at the time of writing).

## 2026-11-21 (later) — boot image rebuilt from CI, test blocked by the phone

The CI artifacts were enough to rebuild the boot image without the vendor tree:

- `laurel-uefi` (run 44920693365): `SILICIUM_UEFI.fd` 3 145 728 B,
  `BootShim.bin` 112 B.
- `laurel-build` (run 44919121380): `hakios-kernel` 15 791 328 B,
  `loader.efi` 66 048 B.
- `tools/build-image.sh` (UEFI FD + shim + `mkpayload.py` + kernel + loader +
  `prebuilt/device-tree-android.dtb`) produced `boot-laurel-xnu.img`,
  **7 245 824 B**, header v0/page 4096, sha256
  `d4d7a4a714c31489be56e9c99b770365bc64f500cf3936190cbff8b742775a5c`.
  Same size as the image from the previous session.

The phone went offline (no RNDIS, Tailscale `offline, last seen 3m`) before
installing `android-tools` and before any write to `boot_a`; no slot was
modified in this session. The dual-boot test recipe and the GPT recovery are in
`docs/DUAL-BOOT-TEST.md`. The next session must switch with the **ABL**
(`fastboot set_active a`) rather than `qbootctl`, and keep the stock
`gpt_both4.bin` on the host.

## 2026-11-21 (night) — first real slot-a boot: Android logo, empty logdump

The phone booted slot a with the CI image and stopped at the **Android logo**: no
Silicium banner, no `XNULOADER`, and `/dev/disk/by-partlabel/logdump` was empty
because UEFI never reached its log writer.

Two independent causes, both on the build side:

1. **The CI platform compiled the QRD memory map.** `prebuilt/laurel-MemoryMapLib.c`
   (the DT-derived table used by `xnu-laurel-gap3.img`, the build that showed the
   banner) was never copied into
   `uefi/files/Platforms/Xiaomi/laurel_sproutPkg/Library/MemoryMapLib/`. The UEFI
   workflow copies `uefi/files/`, so CI shipped the stock table: DxeCore decompresses
   into the `0x5D000000` hole, faults before the framebuffer console, and the panel
   stays on the bootloader splash. Fixed in `ef0e5f2`.

2. **`hakios-uefi` was rewritten upstream the same afternoon.** `c5ff339d`
   (2026-11-21 17:35) replaced Mu-Silicium with a profile-based U-Boot flow and
   removed `apply.sh`/`BASE`; the workflow failed at `cat common/uefi/BASE` before
   compiling. laurel is still a Mu-Silicium port, so the workflow now pins
   **`65621b691b25b94497b0abb5c7e8084ca4976e61`** (the last Mu-Silicium commit,
   BASE `e51cd877e31c8fbb322032dc4cb6715e83d25ad3`). Migrating laurel to the new
   U-Boot profiles is separate work.

The next build is **DEBUG** on purpose: RELEASE compiles out the `Loading driver…`
lines (`MDEPKG_NDEBUG`), and the panel is the only console this phone has.

Hardware note: after the Huasheng hub stopped enumerating (ganged power, killed by
`uhubctl`), rebinding the host controller brought the whole tree back without
touching the phone:

```sh
echo 11200000.usb | sudo tee /sys/bus/platform/drivers/xhci-mtk/unbind
echo 11200000.usb | sudo tee /sys/bus/platform/drivers/xhci-mtk/bind
```

`fastboot` stays at **30.0.5** (`/usr/local/bin/fastboot`); `set_active` and
`reboot` both answered in milliseconds.

### Software route to fastboot (confirmed on laurel)

`sudo reboot bootloader` from Linux **does** enter ABL fastboot. The mainline kernel
exposes `/sys/class/reboot-mode/qcom-pon` with `reboot_modes: bootloader recovery`,
and the PON driver maps the restart string; the BCB helper (writing
`bootonce-bootloader` to the LUN 0 `misc`) was ignored by this ABL. Use
`reboot bootloader`; keep Volume Down + Power as the hardware fallback.

### Reading XNU's log without UFSDxe

`logdump` stays empty because the loader writes it through UEFI's `BlockIo` for the
`logdump` GPT partition, and that needs `UFSDxe` (removed for the first boot). The
loader also has a USB fastboot channel, which needs no storage:

- payload built with the `usb` entry (`tools/build-image.sh --usb`);
- kernel boot-arg `loader_return_after=N` (the kernel hands control back after N
  seconds even if it is only waiting);
- host: `fastboot oem run`, then `fastboot getvar result` and
  `fastboot get_staged log.txt` for the combined loader+kernel log;
- `fastboot oem screenshot` stages the raw framebuffer (`getvar screen` gives the
  geometry).

## 2026-11-22 — automatic fallback: loader platform + watchdog

The local Nov 17 session on cachyos had already found that the loader's
`PAYLOAD_BASE`/UEFI differed and that UFSDxe hangs; its latest payloads
`hello-xnu.bin` (XNUP: loader 66 048, kernel 15 760 208, hello ramdisk 16 528)
and `usb-resident.bin` (custom loader 66 144) were never tested, and USB did
not enumerate. The real advance in that tree was the **higha memory map**
(High Bank A `0x80000000–0xc0000000` as SYS_MEM, XNUP window at
`0x70000000`), which is now in the platform.

The loader patch `patches/loader-laurel-fallback.patch` adds
`platform_laurel`, selects it by MIDR, and arms the Qualcomm virtual watchdog
on reboot/exception. CI `build-laurel` applies it (artifact loader
`cc6db985…`). A no-kernel test and the XNU image
`boot-laurel-xnu-fallback.img` (`9df5f6d5…`, cmdline
`-v hv_wdt_pet=1 loader_return_after=60`) both returned to Linux by
themselves; `qbootctl` left slot a **Bootable 0** and slot b active/successful.
That is the automatic fallback the port needed. `logdump` remains zero until
UFS BlockIo works; the kernel log is only on the panel for now.

## 2026-11-22 (later) — no PAN, kernel timer, fallback repeated

The kernel was built without `+pan` (`ca2d623`; 0 occurrences in the build log)
and the image `boot-laurel-xnu-nopan.img` (kernel `77874598…`, loader
`a3ab487c…`, `-v hv_wdt_pet=1 loader_return_after=20`) returned to Linux after
244 s on its own. Seven ABL retries of UEFI plus 20 s: the kernel's
`loader_return_after` thread call fired, so XNU started; the kernel log is on
the panel, `logdump` still zero. `qbootctl`: a Bootable 0, b active/successful.
The cachy handoff `docs/XNU.md` was pulled from origin (commits `445145d`,
`12dfdd4`) and extended with section 10.
