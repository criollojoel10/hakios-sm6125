# Port plan: laurel_sprout (SM6125) on HakiOS

Order taken from HakiOS's `docs/porting/index.md`: a repository and a configuration, then a boot with
nothing of the phone's, then the drivers one at a time. Each phase names the command that proves it and
what to record here.

## Phase 0 — the repository (this repo)

- [x] `device.conf`, `soc/soc.conf`, `configs/*`, `soc/configs/sm6125.config`
- [x] `tools/pull-firmware.sh`, `tools/pull-soc.sh`
- [x] CI: structure checks on push, kernel+loader with ccache on dispatch
- [x] `make laurel_sprout_defconfig` succeeds — 2026-11-16, common tree at `63fc2b46`:
      `.config made from defconfig, common_defconfig, sm6125.config, laurel_sprout.config,
      laurel_sprout_defconfig`, `kernel.ver=2.3.4-hakios-darwin22.5-sm6125-g63fc2b46`,
      106 characters of boot-arguments
- [ ] `tools/hakios-device.py check laurel_sprout` says it holds together (needs the common tree)
- [ ] firmware pulled: `fw-audio`, `fw-gpu`, `fw-modem`, `fw-wifi` (the four `hakios-config.py needs` asks)
- [ ] `soc.args` generated with `tools/pull-soc.sh` (needs Android on adb)

## Phase 1 — the boot chain

- [ ] `uefi/BASE` pinned; Silicium `laurel_sproutPkg` copied into `uefi/files/`; ClockDxe patch kept
- [ ] `prebuilt/SILICIUM_UEFI.fd` + `BootShim.bin` built
- [ ] `prebuilt/device-tree.dtb` + `ramdisk` from the phone's own boot image (Android 11 stock, slot a)
- [ ] `./xl enter` on the phone reaches the loader banner, one session, and `./xl reboot` returns to Android

Gate: the phone shows HakiOS UEFI and comes back. Nothing written.

## Phase 2 — kernel with nothing of the phone's

- [ ] `make kernel` green in CI with ccache
- [ ] `make loader`
- [ ] `make phone SECS=120`: reaches launchd and ends by itself; logs in `common/logs/`

Record: kernel.ver, driver count printed by `hakios-kernel: N drivers built in (...)`, and the last line.

## Phase 3 — drivers, one at a time

| # | Driver | Note for SM6125 |
|---|---|---|
| 1 | CPUFREQ / THERMAL / SOCINFO | SM6125 is RPM, not RPMh: `soc.args`' `soc_rsc` does not apply |
| 2 | BUTTONS, then touch (FT3518 over i2c2) | `CONFIG_HAKIOS_GOODIX` is the template; FT3518 is FocalTech |
| 3 | display (DSI0 + panel `samsung,s6e8fc0-m1906f9`) | mainline panel driver name is a good start; XNU driver is new |
| 4 | GPU Adreno 610 | **hard blocker**: no `gpu` node in `sm6125.dtsi`; needs node + zap path + `hakios-metal` |
| 5 | storage (UFS 2.1) | the loader reads it first |
| 6 | audio (ADSP) | philipplinux/mia3-postmarketos carries an out-of-tree DTBO for audio |
| 7 | WiFi WCN3990 | needs modem up, then `pd-mapper`, then `ath10k_snoc` (proven order in Kupfer) |
| 8 | cellular | modem image from the phone; IPA addresses from `pull-soc.sh` |
| 9 | camera | CAMSS is not enabled upstream for sm6125: last |

## Phase 4 — dual boot, no data loss

- [ ] `darwin` partition carved from the end of `userdata` (`tools/userdata-carve.py`), keeping Kupfer's
      `sda15` rootfs and Android's slot a intact
- [ ] boot image in the **inactive** slot; slot switch is the rollback
- [ ] `make doctor` read-only report recorded before and after

## Open questions (answered by the phone, not by reading)

1. Does Silicium's laurel platform still boot at today's `BASE`? (Inactive since the port landed.)
2. Does `a610` come up under XNU with the same zap/firmware pair that works under Linux?
3. Is 4 GB enough for the RAM-run mode, or is the `darwin`-partition mode mandatory here?

## 2026-11-16 — toolchain and first boot attempt (evidence)

- `xnu-deps/setup.sh` stage 1 + 2 OK with `THEOS=~/theos` (cctools + iPhoneOS16.5.sdk from github.com/theos/sdks);
  `xnu/apply.sh` applied 82 changed + 72 new files + 49 drivers to `xnu-8796.121.2`.
- `make kernel` produced `xnu-src/.../BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837`
  (the kext symbol-set checks exit 2 on this configuration, as `tools/make-kernel.sh` says).
- `make loader` needs an IPSW device tree; `make loader-open` builds a **placeholder** identity (66 048-byte
  `xnuloader/loader.efi`) — fine for the open kernel, not for Darwin.
- Mu-Silicium built for this phone: `Build/laurel_sproutPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd`
  (3 145 728 bytes = 0x300000 at base 0x5FC00000, from `Resources/Configs/laurel_sprout.toml`).
  Needs `mono` + `nasm` on Arch; `stuart_update -c Platforms/Xiaomi/laurel_sproutPkg/DeviceBuild.py` fixes
  the `mu_nasm` dependency.
- `mkxnuimg.py` was made device-aware (`-d`, `devices/<device>/prebuilt/fd.conf`, `<device>Pkg`, `<device>.dtb`);
  `xl`'s firmware probe likewise. Image built: `xnu-laurel_sprout.img` (1 705 984 bytes).
- **`fastboot boot` is refused by this bootloader** (`FAILED (remote: 'unknown command')`), so the image went to
  `boot_a` with `set_active a`. After the reboot the phone did not enumerate on USB (neither fastboot nor adb)
  within a minute: the loader/shim path is not right yet. Recovery is `set_active b`, which restores the
  Kupfer/Android slot.
- Next attempt: check the BootShim/FD base contract against `laurel_sprout.toml` (`base = 0x5FC00000`,
  `size = 0x300000`) and confirm the Android boot header version the bootloader accepts, before writing to
  `boot_a` again.

## 2026-11-16 (later) — the boot chain, step by step

1. `fastboot boot` is refused (`unknown command`): the only way to run anything is to write a slot.
2. Slot a was flagged `unbootable`; `fastboot set_active a` alone does not clear it, `fastboot set_active a`
   followed by `fastboot reboot-bootloader` does (`slot-unbootable:a: no`).
3. The working Kupfer image on this phone is **header v0, page 4096, base 0, kernel 0x8000, ramdisk 0x1000000,
   tags 0x100, kernel = gzip(Image) + DTB appended**. With those exact values the phone got past the bootloader
   to the Android One logo instead of dropping to fastboot.
4. Silicium's own recipe (`build_uefi.py` → `Mu-laurel_sprout.img`) is **header v1, page 2048, kernel 0x10008000,
   kernel = gzip(shim+FD) + DTB**, and it stays at the logo too.
5. Two suspects, both recorded: `vbmeta_a` was still the vendor one (now replaced with `avbtool make_vbmeta_image
   --flags 2`, verification disabled), and the gzip stream produced by `gzip.open()` carries a **FNAME header**
   (`1f 8b 08 08 …`), while the Kupfer image that boots is `1f 8b 08 00`. ABL's decompressor is a plausible
   place for that difference to matter. An image recompressed with `gzip.compress(..., mtime=0)` (`1f 8b 08 00`)
   was flashed at 14:30 and the phone stopped falling back to fastboot; whether the screen shows UEFI is the
   open question.
6. No serial console on this phone: the screen is the only log until a ramoops entry appears.

## Root cause found: the wrong BootShim

`Mu-Silicium/BootShim/BootShim.S` (upstream Silicium) only copies the **FD** to `FD_BASE` and jumps to it:

```asm
_Start:
  mov x4, x1 ; ldr x5,=FD_BASE ; cmp x4,x5 ; beq _Entry
  ldr x6,=FD_SIZE
_CopyLoop: ldp x2,x3,[x4],#16 ; stp x2,x3,[x5],#16 ; subs x6,x6,#16 ; b.ne _CopyLoop
_Entry: br x5
```

It never copies the **XNUP container** that carries the XNU loader, so with an image built from plain Mu-Silicium the
UEFI (if it starts at all) has no kernel to start and the phone shows the vendor splash and no USB. HakiOS's own
patched shim does that copy:

> `uefi/apply.sh`: "BootShim.S copies the 'XNUP' container behind the UEFI image to 0xF0000000, where the loader
> finds the kernel" (`hakios-uefi/hakios.patch`).

So the images built so far (`xnu-laurel_sprout.img`, `boot-laurel.img`, `uefi-nofname.img`, `uefi-v2.img`) were
built from the **unpatched** tree. The correct chain is:

```sh
cd hakios-common
# devices/laurel_sprout/uefi/files/Platforms/Xiaomi/laurel_sproutPkg  (copied from Mu-Silicium)
./uefi/apply.sh laurel_sprout     # clones Silicium at uefi/BASE, applies hakios.patch, adds the platform
cd Mu-Silicium && python3 build_uefi.py -d laurel_sprout
```

then rebuild the boot image with the **hakios** `BootShim.bin` and flash. That is the step in progress.
