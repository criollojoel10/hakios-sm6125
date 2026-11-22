# hakios-sm6125: the Xiaomi Mi A3 (laurel_sprout) and its Snapdragon 665 (SM6125)

One HakiOS **device repository**: the phone (`device.conf`, `configs/`, its UEFI platform, the firmware
script) and its SoC family's layer (`soc/`, the SM6125). The common tree's
`tools/hakios-device.py sync` clones it into `devices/laurel_sprout/`.

This port starts from a phone that already runs mainline Linux well: Kupfer/Arch on `boot_b` with the
mainline fork `sm61x5` (kernel 7.2.3) boots, the DSI panel and FT3518 touch work, WiFi WCN3990 works
through the `rmtfs`/`pd-mapper` chain, and the Adreno 610 initialises (`renderD128`) once the
`a610_zap.mbn` / `a630_sqe.fw` pair is in place. None of that is HakiOS yet: it is the firmware map and
the boot layout this port reuses.

## Status

`docs/XNU.md` is the current handoff record for the XNU side: what was built, what was
proven on the phone, the payload-base and shim defects, and the next steps. Read it before
touching the boot chain.


`device.conf` is the single source of truth (docs are generated from it). Today: **nothing tested on the
phone**. The pieces that exist outside this repository are named in `docs/PLAN.md`.

| Gate | State |
|---|---|
| UEFI platform (Silicium `laurel_sproutPkg`) | exists upstream, listed **Inactive** (patched ClockDxe) |
| SoC layer `sm6125` in HakiOS | **missing**: must be written (this repo's `soc/`) |
| Kernel `laurel_sprout_defconfig` | skeleton; first gate is `make laurel_sprout_defconfig` |
| GPU (Adreno 610) | blocked: no `gpu` node in mainline `sm6125.dtsi` (gpucc-sm6125 is upstream) |
| Boot image / prebuilt | not built |

## Building

CI (`.github/workflows/ci.yml`) checks structure and scripts on every push, and builds the kernel and
loader with **ccache** on `workflow_dispatch` (a cached rebuild is the only affordable way to iterate on
XNU).

Locally, from the common repository:

```sh
git clone https://github.com/oosexgang/hakios-xnu-kernel.git
cd hakios-xnu-kernel
git clone https://github.com/criollojoel10/hakios-sm6125.git devices/laurel_sprout
make laurel_sprout_defconfig
make kernel loader
make phone SECS=600        # phone on fastboot, nothing written to it
```

## Firmware

`tools/pull-firmware.sh` pulls the phone's own firmware (GPU, WiFi, modem, ADSP, audio calibration) into
`fw-*/`; it is the vendor's and stays out of git. `tools/pull-soc.sh` turns the phone's device tree into
the `soc_*` boot arguments.

## What this repository does not contain

Nothing of Apple's, no vendor firmware, no Darwin user space. The user space is laid out by whoever runs
it, from an IPSW they obtained themselves. Apple's services (activation, Apple ID, App Store) are not
supported and not a goal. HakiOS is not affiliated with Apple.

## Licence

MIT for everything written here (`LICENSE`); the Silicium platform under `uefi/files/` keeps Project
Silicium's licence and notices when it is copied in; the XNU patches stay under APSL-2.0.
