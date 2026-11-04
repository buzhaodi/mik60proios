<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.svg">
    <img alt="UniXNU" src="assets/logo-light.svg" width="200">
  </picture>
</p>

<p align="center">
  <a href="https://unixnu.com"><img alt="Documentation" src="https://img.shields.io/badge/docs-unixnu.com-2A5BD7?logo=readthedocs&logoColor=white"></a>
  <a href="https://t.me/unixnu"><img alt="Telegram" src="https://img.shields.io/badge/Telegram-@unixnu-26A5E4?logo=telegram&logoColor=white"></a>
  <a href="https://x.com/unixnu"><img alt="X" src="https://img.shields.io/badge/X-@unixnu-000000?logo=x&logoColor=white"></a>
</p>

# UniXNU-socrates

Device repository for the **Redmi K60 Pro (socrates, SM8550 / Snapdragon 8 Gen 2, Adreno 740)**.
It holds the board file, kernel defconfig, device scripts, drivers and package.

Ported from [UniXNU-vermeer](https://github.com/yyx2025/UniXNU-vermeer) (Redmi K70), which was
itself ported from [UniXNU-sheng](https://github.com/UniXNU/UniXNU-sheng) (Xiaomi Pad 6S Pro):
the same SM8550 SoC, so UFS, AES, GIC, timers and the GPU platform blocks are the same silicon.
The board-level wiring (panel, touch controller, GMU window, UEFI memory map, splash carveout)
is **not** the same and is being re-read from this phone's own firmware.

- [Documentation](https://unixnu.com)
- [Porting guide](https://unixnu.com/porting/)
- [Build](https://unixnu.com/building)
- Porting record: [PORTING-SOCRATES.md](PORTING-SOCRATES.md)

Firmware: `uefi-socrates` (a Mu-Silicium checkout with `socratesPkg`), kept in a repository of
your own next to this one.

Build with the `unixnu` driver of [UniXNU](https://github.com/UniXNU/UniXNU). Clone both repositories
with `--recurse-submodules`; `unixnu fetch` also updates the module submodules.

## Device support

**Nothing in this table is hardware-verified on the K60 Pro yet.** The vermeer and sheng ports
supply the SoC-level wiring; every row below still needs the socrates firmware inputs and a
first boot on hardware.

| Feature | State | Notes |
| --- | --- | --- |
| Board file / defconfig | 🔧 | This repository; SM8550 SoC fragment from `UniXNU-sm8550-common` |
| Firmware (`socratesPkg`) | 🔧 | Skeleton from vermeerPkg; memory map needs the socrates `uefiplat.cfg` |
| UFS | 🔧 | Native UFS driver ported unchanged from sheng; off until the prelink/verified-root chain exists (see the porting record) |
| Display | 🔧 | UEFI GOP on the splash framebuffer; panel PCDs 3200×1440 TODO from the socrates dtbo |
| Touch | ❌ | Controller unknown until the socrates dtbo is read (expect Goodix; vermeer's GT9916S driver notes apply) |
| GPU | ❌ | Adreno 740 same as sheng; the socrates GMU window must be read from the socrates base dtb before `CONFIG_XNU_NATIVE_ADRENO` can come back |
| Wi-Fi / Bluetooth / Camera / Audio | ❌ | |

🔧 ported but unverified, ❌ not available.

## What is needed before the first boot

1. The stock fastboot archive `socrates_images_OS3.0.304.0.WMKCNXM_*.tgz` (the exact build this
   phone runs) unpacked into `scripts/data/`: the base dtb, `dtbo.img` and the `uefiplat.cfg`
   of the stock `uefi.img` — see [scripts/data/SOCRATES-FIRMWARE-NOT-EXTRACTED.md](scripts/data/SOCRATES-FIRMWARE-NOT-EXTRACTED.md).
2. The board facts re-read from those files: splash carveout, UEFI windows, panel and touch
   entries, the GMU window, the `[userdata]` GPT geometry.
3. `uefi-socrates` with the memory map of this board.

The first-boot acceptance is the same as vermeer's: `fastboot boot out/socrates/boot/boot.img`
shows kernel console output on the panel (or a panic screen) and does not reset after a few
seconds.
