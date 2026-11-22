# XNU on laurel_sprout: state of the port

Last updated: 2026-11-21 (snapshot; see section 9 for later commits). This file is the handoff record: what was built, what was
proven on the phone, what failed, and the next steps. `docs/PLAN.md` holds the older
plan and research notes; where the two disagree, this file is newer.

Evidence labels used below:

- **proven** — seen on the phone or in a command's output that is recorded here.
- **built** — an artifact exists and was checked locally, never booted to completion.
- **unproven** — claimed or expected, with no evidence.

## 1. Where the pieces live

| Piece | Location |
|---|---|
| This device/SoC repository | `hakios-sm6125` (public) |
| Common tree (fork of `hakios-xnu-kernel`) | `~/Projects/hakios-common` |
| UEFI (fork of `hakios-uefi` on Mu-Silicium) | `~/Projects/hakios-common/uefi`, clones Mu-Silicium into `uefi/BASE` |
| XNU source and toolchain | `~/theos` (Theos + LLVM aarch64 + iPhoneOS16.5.sdk) |
| XNU payload images | `~/Projects/hakios-common/out/laurel-diagnostics/` |

`uefi/apply.sh laurel_sprout` clones Mu-Silicium, applies `hakios.patch`, and copies
`devices/laurel_sprout/uefi/files/Platforms/Xiaomi/laurel_sproutPkg` (72 KiB) into the tree.
`mkxnuimg.py -d laurel_sprout` packs shim + FD + payload into an Android boot image v1
(page 2048).

## 2. What is proven on the phone

- **UEFI runs.** A DEBUG build flashed to `boot_a` shows the UEFI console on the panel:
  drivers load (`DxeCore.efi`, `MemoryManagerDxe.efi`, and the rest), then the boot manager
  appears. Photos of this exist; they are not committed.
- **One crash has a cause.** An earlier build died with
  `Synchronous Exception / Data abort: Translation fault, third level` while loading
  `DxeCore.efi` at `0x5D5E7000`, an address inside the gap between the "Display Reserved"
  and "FV Region" entries of the platform memory map. That map came from the QRD stub DTB,
  not from laurel. `MemoryMapLib.c` was rewritten from the phone's own device tree; later
  builds reached the boot manager instead of that abort.
- **The XNU loader parses the payload.** With the loader installed, the console shows the
  payload being accepted and a jump. There is **no evidence the XNU kernel executed** after
  that jump, and none that any userspace ran.

## 3. What is built but unproven

- XNU `xnu-8796.121.2` with `xnu/apply.sh` applied (82 changed + 72 new files + 49 drivers).
  `make kernel` produced `mach.development.bcm2837`.
- `make loader-open` produced a placeholder-identity `xnuloader/loader.efi` (66 048 bytes).
  A real Darwin boot needs a signed identity from a device IPSW.
- Mu-Silicium for `laurel_sprout`, `FD_BASE=0x5FC00000`, `FD_SIZE=0x300000`; DEBUG and
  RELEASE `SILICIUM_UEFI.fd` are 3 145 728 bytes each.
- Payload images: `hello-xnu.bin` (16 MiB, sha256 `13cdbcc27c8c058a…`) and
  `usb-resident.bin` (65 KiB, sha256 `5b4af6a08fec310b…`). Both were checked structurally,
  never run to a known state.
- Boot images in this repository: `boot-laurel.img` (sha256 `8db50e185667e6f6…`),
  `boot-laurel-v0.img` (`f2d12742253e1fe2…`), `vbmeta-laurel.img` (`8b282508cd8bb372…`).

## 4. Defects found, and their state

**Payload base mismatch.** The upstream loader has
`#define PAYLOAD_BASE 0xF0000000ULL`; the HakiOS BootShim and `XnuLoader.h` copy the
`XNUP` container to `0x70000000`. An image built from the mismatched pair jumps to memory
the shim never filled. Fixed in an isolated diagnostic copy of the loader; the upstream
tree still carries `0xF0000000`.

**The upstream shim drops the payload.** Mu-Silicium's `BootShim.S` (112 bytes) copies only
the UEFI FD. HakiOS's shim (176 bytes) also copies the `XNUP` container — `objdump` shows
`mov w3,#0x4e58; movk w3,#0x5055` ("XNUP"). Any image built with the upstream shim cannot
boot XNU whatever the loader does. `uefi/apply.sh` must keep using the HakiOS shim.

**No storage from the loader.** With `UFSDxe` disabled (needed to get past the dispatch
hang), `BlockIO` reports `EFI_NOT_FOUND` and zero handles, so nothing the loader writes to
a log partition lands anywhere. `UFSDxe` is commented out in `APRIORI.inc` and `DXE.inc`;
that change let the boot manager and the loader run, but it has not been shown to be what
fixed the earlier reset.

**No usable log of a failed boot.** On the Android side pstore/ramoops is enabled
(`ramoops` at `0x61600000`, 1 MiB, console 0x40000, record 0x80000, ECC 4). A control boot
produced `console-ramoops-0` with 1971 corrected bytes and 1001 unrecoverable blocks, and a
marker written to `/dev/kmsg` before rebooting was absent. The raw `logdump` partition is
64 MiB of zeros. Neither channel has produced a trustworthy log of a HakiOS boot. Do not
write to `logdump` until a read-back proves the write lands.

## 5. Memory map (laurel_sproutPkg)

From the phone's device tree; the header is at `0x5FC00000` (3 MiB). Entries include
Kernel `0x40000000+0x05700000`, Boot Info `0x45CF0000`, AOP CMD DB `0x45F20000`,
SMEM `0x46000000`, PIL Reserved `0x4AB00000+0x0D200000`, DBI Dump `0x5B100000`,
Sched Heap `0x5BC00000`, Display Reserved `0x5C000000+0x01000000`, Gap RAM
`0x5D000000+0x01400000`, FV Region `0x5F800000`, ABOOT FV `0x5FA00000`,
UEFI FD `0x5FC00000+0x00300000`, SEC Heap `0x5FF00000`, MMU PageTables `0x5FF8D000`,
UEFI Stack `0x5FF90000`, Log Buffer `0x5FFF7000`, Info Blk `0x5FFFF000`,
WtShareMem `0x62000000`, DXE Heap `0x62100000+0x01BC0000`, High Bank A
`0x80000000+0x40000000`, High Bank B `0xC0000000+0x80000000`.

The two overlaps the map reported (25 entries) were fixed; a later map has 37 entries and
0 overlaps.

An EFI reserved range `0x70000000+0x04000000` was added so the payload base is not reused
by the firmware. Confirm it appears in the map dump before trusting it.

## 6. Build commands

```
# UEFI (from the common tree)
cd uefi && ./apply.sh laurel_sprout
cd BASE && python3 build_uefi.py -d laurel_sprout -r DEBUG

# XNU kernel and loader
cd xnu-deps && THEOS=~/theos ./setup.sh          # stages 1 + 2
cd xnu && ./apply.sh && make kernel && make loader-open

# Boot image: shim + FD + optional XNUP payload
./mkxnuimg.py -d laurel_sprout --mode DEBUG -p out/laurel-diagnostics/hello-xnu.bin \
    -o out/xnu-laurel.img
```

`mkxnuimg.py` reads `devices/laurel_sprout/prebuilt/fd.conf` (`base=0x5FC00000`,
`size=0x300000`), rebuilds `BootShim` with `FD_BASE/FD_SIZE/PAYLOAD_BASE`, and packs
`--header_version 1`, page 2048.

## 7. Next steps, in order

1. Dump the UEFI memory map from the running build and confirm the `0x70000000+0x04000000`
   reservation is present.
2. Make one image where shim, `XnuLoader.h` and the loader all use the same payload base,
   and keep it at `0x70000000`.
3. Get a log channel before touching XNU again: either make `UFSDxe` work with `BlockIO`, or
   drive the driver's own USB (UEFI `UsbfnDwc3Dxe`/`UsbDeviceDxe` are present in the tree)
   so the loader can report over the cable instead of the panel.
4. Only then retry the minimal XNU payload, with a kernel command line and interrupts
   defined, and treat "kernel printed one line" as the next gate — not "Darwin booted".
5. `fastboot boot` is refused on this phone ("unknown command"); every test writes the slot.
   `slot-unbootable:a` only clears after `set_active a` followed by `reboot-bootloader`.
   Keep a known-good `boot_a` image on the host for every experiment.

## 8. Not in this repository

Firmware, `diagnostics/`, photos, serial numbers and any capture that identifies the phone
stay out of git. `diagnostics/` holds the Android-side captures used for the ramoops
analysis (`dmesg.txt`, `logcat.txt`, `pstore-status.txt`, `console-ramoops-control.txt`,
`logdump.bin`); it is ignored by git.


## 9. Newer than this file

`docs/JOURNAL.md` and `docs/DUAL-BOOT-TEST.md` carry work that landed after this
snapshot; read them first. In short:

- `loader: add platform_laurel (GIC/timer/SMC) and watchdog fallback` (`51b938f`) adds
  `patches/loader-laurel-fallback.patch`: `platform_laurel`, selected by MIDR, arms the
  Qualcomm virtual watchdog on reboot and exception.
- `58f964c` records the result: a no-kernel test and `boot-laurel-xnu-fallback.img`
  (cmdline `-v hv_wdt_pet=1 loader_return_after=60`) both returned to Linux by
  themselves, which is the automatic fallback this port needed. The kernel log is still
  panel-only; `logdump` stays untouched until UFS BlockIO works.
- The higha memory map (High Bank A as SYS_MEM, XNUP window at `0x70000000`) is now part
  of the platform, which supersedes the "reserve it" step in section 7.
- `ca2d623` builds laurel without PAN: SM6125 is ARMv8.0-A.
- `docs/DUAL-BOOT-TEST.md` states the rule that came out of the 2026-11-21 incident:
  switch slots with the ABL (`fastboot set_active`), never with `qbootctl`, because a
  partial qbootctl write can leave both slots unbootable.

So the current gate is no longer "does the payload base match" but "does the XNU kernel
produce a line of output that survives the fallback".
