# Ginkgo / UniXNU as a reference for laurel (SM6125)

Sources studied on 2026-11-21:

| Repository | Revision | What it is |
|---|---|---|
| `redmagikarp13/UniXNU-ginkgo` | `664157ee` | Redmi Note 8 (`ginkgo`, SM6125, 4 GB/64 GB) board port |
| `redmagikarp13/UniXNU-sm6125-common` | `02c2de60` | SM6125 SoC layer: ArmCpu, eMMC, platform power, XNU patches |
| `redmagikarp13/Mu-Silicium-ginkgo`, branch `ginkgo-unixnu` | `96a967ed` | Mu-Silicium fork for the UniXNU boot path |
| `UniXNU/UniXNU`, `UniXNU/DarwinBoot`, `UniXNU/ShengUfs` | current | Upstream build system, UEFI XNU loader, native UFS |

`ginkgo` is the closest hardware to laurel that boots XNU today: same SM6125, same
Kryo 260 cores, same GIC/timer, 4 KiB pages, ARMv8.0-A. Its storage is eMMC; laurel
is UFS. That single difference separates most of what transfers from what does not.

## What UniXNU is

UniXNU is not a fork of HakiOS. It is a UEFI environment that boots an
Apple-sourced XNU (iPadOS/macOS profile) on non-Apple ARM64 hardware:

- `UniXNUPkg` — UEFI application/driver, the menu and the boot policy;
- `DarwinBoot` — a UEFI XNU loader (Mach-O, packed ramdisk, memory windows);
- `ArmCpu` — GICv3, generic timer, IPIs, idle;
- `ShengUfs` — native UFS transport for sheng (SM8550), not a generic SM6125 driver;
- per-device repositories provide `board.toml`, a DTS, a defconfig, patches and the
  UEFI firmware package.

Ginkgo's boot chain is:

```
ABL (boot v2 + separate DTB)
  -> BootShim + Mu-Silicium FD (uefi-ginkgo)
     -> UniXNU / DarwinBoot
        -> XNU, built from the UniXNU tree with the sm6125 patches
           -> iPadOS userland from the IPSW
```

The HakiOS chain on laurel is different but shares the first two stages:

```
ABL (v0, page 4096)
  -> BootShim + Mu-Silicium FD (laurel_sproutPkg)
     -> XNULOADER (payload at 0xF0000000, loader_return.c)
        -> XNU from oosexgang/hakios-xnu-kernel
```

So the reusable surface is the UEFI platform, the SM6125 facts, and the XNU
bring-up fixes — not DarwinBoot or the userland.

## SM6125 facts confirmed by ginkgo (and true for laurel)

From `UniXNU-sm6125-common/dts/sm6125.dtsi`:

| Fact | Value |
|---|---|
| CPUs | 4x Cortex-A53 `reg = 0x0..0x3` (small) + 4x Cortex-A73 `reg = 0x100..0x103` (big) |
| Timer | `clock-frequency = <19200000>` (19.2 MHz) |
| GIC | dist `0x0f200000`, redist `0x0f300000`, stride `0x20000` |
| PSCI | `method = "smc"` (not HVC) |
| GCC | `0x01400000`, size `0x1f0000` |
| eMMC (ginkgo) | `sdhci@4744000` (SDCC1), `qcom,sdhci-msm-v5` |
| ISA | ARMv8.0-A: **no PAN, no LSE, no PAC**, 4 KiB pages |

The laurel Android device tree has the same CPU/GIC/timer values. Its RAM layout
is different (`0x40000000..0x7dd00000`, `0x80000000..0xc0000000`,
`0xc0000000..0x140000000`), and its ABL accepts boot header v0/page 4096, so
ginkgo's `pack-boot-v2.py` and separate-DTB layout do not apply.

## What is worth adapting, in order

### 1. Turn PAN off for SM6125 (highest impact)

`hakios-xnu-kernel` builds the BCM2837 board configuration with:

```
MACHINE_FLAGS_ARM64_BCM2837 = -DARM64_BOARD_CONFIG_BCM2837 -Xclang -target-feature -Xclang +pan
#define __ARM_PAN_AVAILABLE__ 1
```

Those are correct for the ARMv8.2 cores of redwood (A55/A78), but **wrong for
SM6125**: Cortex-A53/A73 are ARMv8.0-A and have no `PSTATE.PAN`. Ginkgo disables
it explicitly:

```
# UniXNU-sm6125-common/configs/sm6125.config
CONFIG_XNU_NATIVE_PAN=n
```

The kernel reaches early boot on laurel with PAN compiled in because that path
does not execute a user-memory access yet. The first `copyin`/`copyout` or user
fault path would trap. This needs a per-SoC switch (a `CONFIG_PAN`/device
fragment that drops both `+pan` and `__ARM_PAN_AVAILABLE__`), or a small patch
applied to the common tree for `SOC=sm6125`.

### 2. Add a laurel platform to the loader

`xnuloader/loader.c` only knows `platform_qemu_virt` and `platform_redwood`.
On laurel it stays on QEMU:

- `psci_hvc = 1` (QEMU) while SM6125 uses **SMC**;
- `core_shift = 0` and no idea of the `0x0..0x3` / `0x100..0x103` split;
- QEMU GIC/UART addresses in the ADT it builds for XNU.

A `platform_laurel` entry should carry at least:

```
.name = "laurel", .io_base = 0x00400000, .io_size = 0x3fc00000,
.gic_dist = 0x0f200000, .gic_redist = 0x0f300000, .uart = 0,
.psci_hvc = 0, .log_other_cpu = 1,
.cores = 8, .core_shift = 8, .small_cores = 0x0f
```

The core numbering is the part to test: `bootcpu=N` currently becomes
`N << core_shift`, which cannot express both `0x0..0x3` and `0x100..0x103`
from one 0-7 index. Either the loader gets a small MPIDR table for SM6125, or
laurel boots with one core (`cpus=1`, no `bootcpu=`) until that is fixed.
Without this entry, SMP, the live-log watcher and the USB command channel do
not have the right firmware description.

### 3. UFSDxe for the physical log

The loader writes its log to the `logdump` GPT partition through UEFI `BlockIo`
(`find_log_partition()` in `loader.c`). `logdump` is on UFS LUN 4, so this needs
the vendor `UFSDxe`. The first slot-a boot removed it to get past DXE dispatch;
that is why `logdump` was empty. Ginkgo keeps `UFSDxe` in `APRIORI.inc`/`DXE.inc`
even though its own storage is eMMC, which says the driver is expected to
dispatch on SM6125. Re-enable it, boot with `loader_return_after=60`, and read
`logdump` from Linux (`tools/fetch-logdump.sh`).

### 4. Kernel config and boot arguments

Ginkgo's board config is a useful checklist:

```
CONFIG_XNU_NATIVE_PAN=n
CONFIG_XNU_DT_PANIC_REGION=y   # no BCM2837 0x3c0fc000 in a Qualcomm phone
CONFIG_XNU_SHENG_PMGR=y        # only for the UniXNU AMFI bridge
```

The HakiOS common patch already removes the fixed `PLATFORM_PANIC_LOG_PADDR`
and takes the panic region from `/pram` and `/chosen`, so the second item is
already the HakiOS behaviour. The first is not. The third belongs to UniXNU's
prelinked AMFI and is not needed for a HakiOS boot.

Boot arguments worth copying for a diagnostic run: `-v debug=0x14e` (more XNU
output). `serial=3` and `pmgr=2` are ginkgo-specific and should not be copied
blindly.

### 5. Small XNU fixes that may apply

- `iokit-fdt-phandle-alias.patch`: accepts `phandle`/`linux,phandle` as
  `IODeviceTree`'s `AAPL,phandle`. Useful if a driver does not match because
  the ADT uses the FDT spelling.
- `sm6125-modload-lock-order.patch`: takes the kext lock around
  `OSKext::load`; relevant once kexts are loaded, not for the first boot.
- `platform-sleep-hook.patch`: a weak `arm64_platform_sleep_hook` for Xcode 27's
  ld-prime. A build-time stub, not a feature.
- `native-smp-secondary.patch`: `MAX_CPUS=8` and an Affinity1 mask of `0xffff`.
  The HakiOS common patch already has `MAX_CPUS=8` and the same mask, so this
  one is already covered.

### 6. Storage: eMMC is not UFS

Ginkgo's `Sm6125EmmcCore`/`Sm6125EmmcBlock` initialize GCC + SDHCI-MSM v5 and
present `IOBlockStorageDevice` over eMMC. Laurel has no SDHCI card: it is UFS
2.1 behind the Qualcomm UFS host controller. That driver does not transfer.
For laurel storage the candidates are the existing `drivers/storage/hakios.ufs.c`
in the HakiOS tree, or a port of `UniXNU/ShengUfs` (written for SM8550, a much
larger job). Neither is needed for the first XNU log.

### 7. Platform power

`Sm6125PlatformPower.cpp` is a bridge that loads `com.apple.driver.ApplePMGR`
and implements `ApplePMGRNub` so UniXNU's prelinked AMFI can run on SM6125. It
is tied to UniXNU's XNU/AMFI layout and its `pmgr=2` boot argument. It is not a
generic SM6125 power driver and should not be copied into HakiOS unless the
AMFI path is being ported too.

## What does not transfer

- `pack-boot-v2.py`, the separate DTB and the 3 GiB `0x80000000` memory window:
  laurel's ABL takes v0/page 4096 and its RAM layout is different.
- `fastboot boot`: this ABL answers `unknown command`; tests write `boot_a` and
  switch slots. `reboot bootloader` is the way into fastboot from Linux.
- DarwinBoot, `UniXNURamDiskDxe`, the UniXNU menu and the iPadOS userland: a
  different boot architecture from XNULOADER.
- The eMMC probe and its `bsd_init` hook: laurel is UFS.
- The `VerifiedRoot`/`SHNGROOT`/`SHNGDATA` storage layout: UniXNU-specific.

## Concrete next steps

1. Finish the UFSDxe + `loader_return_after=60` run and read `logdump`; that
   log decides what to fix next.
2. Add `platform_laurel` to the loader (GIC/timer/SMC; decide the MPIDR table),
   then rebuild the loader in CI.
3. Make PAN a per-SoC choice and turn it off for SM6125; rebuild the kernel.
4. Only then try `cpus=8`/`bootcpu=` and compare the SMP bring-up against
   ginkgo's `native-smp-secondary` expectations.
