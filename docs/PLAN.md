# Port plan: laurel_sprout (SM6125) on HakiOS

Order taken from HakiOS's `docs/porting/index.md`: a repository and a configuration, then a boot with
nothing of the phone's, then the drivers one at a time. Each phase names the command that proves it and
what to record here.

## Phase 0 — the repository (this repo)

- [x] `device.conf`, `soc/soc.conf`, `configs/*`, `soc/configs/sm6125.config`
- [x] `tools/pull-firmware.sh`, `tools/pull-soc.sh`
- [x] CI: structure checks on push, kernel+loader with ccache on dispatch
- [ ] `tools/hakios-device.py check laurel_sprout` says it holds together (needs the common tree)
- [ ] `make laurel_sprout_defconfig` succeeds

Evidence goes here: command, date, first line of failure.

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
