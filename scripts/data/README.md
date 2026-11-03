# socrates firmware inputs

Measured from the stock fastboot archive
`socrates_images_OS3.0.304.0.WMKCNXM_20260713.0000.00_16.0_cn_cdb5f7269f.tgz`
(the exact build this phone runs, fingerprint
`Redmi/socrates/socrates:16/BP2A.250605.031.A3/OS3.0.304.0.WMKCNXM`):

| File | Contents | Source in the archive | SHA-256 |
| --- | --- | --- | --- |
| `socrates.dtb` | the base device tree (Kalama QCM, msm-id 0x25c, `qcom,board-id 00010008`) | the dtb blobs of `images/vendor_boot.img` (464090 bytes) | `2424324ec16a39620822111beb181f916e5cf1cc16ca998b87e2d1d8759e0e07` |
| `socrates-uefiplat.cfg` | the stock UEFI platform config: memory map, register map, feature flags | the plain-text region at 0x4703b..0x490bf of `images/uefi.elf`, before the two gzip FV members | `90648bc5b3aaffd3a509abe2c20121798826a9c27e8c39be3f90bd62366797ee` |

Board facts read from these files (and where the dtbo is still needed):
`dtbo.img` entry 50 is the socrates overlay (model
"Qualcomm Technologies, Inc. 8550 socrates", `xiaomi,miboard-id = 4`).
The dtbo itself is not stored here; the panel (`m11_42_02_0a`, 1440x3200,
cmd mode + DSC), the touch controller (Goodix SPI, `xiaomi,m11-spi`,
fw `goodix_firmware_m11`) and `splash_region` (0xb8000000+0x2b00000) were
read from it. The vendor freeform files (panel XMLs, BDS_Menu.cfg,
SecParti.cfg, uefipil.cfg, ...) live in the uefi-socrates repository,
`Platforms/Xiaomi/socratesPkg/RawFiles/`.
