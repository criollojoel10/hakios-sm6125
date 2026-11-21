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
