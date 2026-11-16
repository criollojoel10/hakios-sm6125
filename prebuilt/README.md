# prebuilt/

| file | where it comes from |
|---|---|
| `SILICIUM_UEFI.fd` | `python3 build_uefi.py -d laurel_sprout` in Project-Silicium/Mu-Silicium (3 MiB, base `0x5FC00000`) |
| `BootShim.bin` | made by the common tree's `mkxnuimg.py` from Mu-Silicium/BootShim |
| `device-tree.dtb` | Mu-Silicium `Resources/DTBs/laurel_sprout.dtb` (from the phone's own Android boot image) |
| `ramdisk` | Mu-Silicium `Resources/ramdisk` |
| `mkbootimg.py` | Mu-Silicium `Resources/Scripts/mkbootimg.py` |
| `fd.conf` | `base` and `size` of the FD, from `Resources/Configs/laurel_sprout.toml` |

The binaries carry the vendor's own drivers (UEFI DXEs) and are not redistributed in git: the files above are
gitignored except this README and `fd.conf`.
