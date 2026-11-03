# socrates firmware inputs: not extracted yet

This directory must hold, extracted from the socrates (Redmi K60 Pro) stock fastboot
archive `socrates_images_OS3.0.304.0.WMKCNXM_*.tgz` (the exact build this phone runs):

| File | Extracted from | Used by |
| --- | --- | --- |
| `socrates.dtb` | the base device tree of the boot image (kernel dtb) | `scripts/check-socrates.py`, board facts |
| `socrates-uefiplat.cfg` | the gzip GUIDed section `1D301FE9-...` of the stock `uefi.img` FV | `scripts/check-socrates.py`, MemoryMapLib |
| `socrates-dtbo.img` | `images/dtbo.img` | panel, touch, GMU window, splash_region |

Do not copy the socrates or sheng equivalents here: same SoC, different board wiring.
