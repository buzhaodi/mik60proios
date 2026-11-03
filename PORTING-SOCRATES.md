# socrates 移植记录（Redmi K60 Pro / SM8550）

本文记录板级决策、从 vermeer/sheng 带来的结论，以及首启前还缺什么。规则与 vermeer 的
PORTING 文档相同：**每个数值都有出处**——要么是本机固件提取，要么是同 SoC 上游板
（sheng / vermeer），要么明确标注为未验证。socrates 尚无任何真机观察，因此除
「手机自报」一栏外，所有状态都是 🔧 未验证或 ❌ 缺失。

## 1. 当前状态

| 环节 | 状态 | 依据 |
| --- | --- | --- |
| UEFI 固件（socratesPkg → SILICIUM_UEFI.fd） | 🔧 骨架来自 vermeerPkg，**尚未构建、未上真机** | 本仓库 + `uefi-socrates` |
| 内核配置 + prelink（iPadOS 17.7.11 / iPad7,1） | 🔧 `configs/socrates_defconfig`，板级数值待固件核对 | vermeer 同款链 |
| payload / boot.img | ⏳ 依赖 kernel + firmware | `build-kernel.yml` 的 `bootimg` job |
| 存储（UFS） | ⏸ 首启阶段关闭，见 §2.1 | `CONFIG_XNU_NATIVE_UFS=n` |
| 显示 | 🔧 走 UEFI GOP + `splash_region`（预期 video-mode 面板，待 dtbo 确认） | `[[bootimg.dtb_node]]` |
| 触摸 | ❌ 控制器型号待 dtbo 确认（预期 Goodix，无驱动） | §4.3 |
| GPU / WiFi / 音频 | ❌ | `CONFIG_XNU_NATIVE_ADRENO=n` |

## 2. 从 vermeer/sheng 继承的结论（同 SoC，预期直接适用）

### 2.1 UFS 必须在 prelink 之后才能进链接

`NativeUfs` 以 `-DNATIVE_VERIFIED_BLOCK=1` 编译，`NativeUfsBlock` 继承 Apple
IOStorageFamily 的 `IOBlockStorageDevice`；其实现只在 prelink 之后存在于内核里。
`NATIVE_UFS` 与 `VERIFIED_ROOT_PROBE` 必须成对开关，恢复顺序：实机
`audit-storage-interface.py` 捕获 → `build-os-root.py` → 两者一起开。首启阶段两者全关，
内核停在 `waiting for root device` 正是验收标准（与 vermeer §2.1 相同，fuxi 的
stage-2a 同证）。

### 2.2 bootstrap log 里 mockfs 未定义是预期的

`unixnu build kernel` 缺编译记录时先跑一次不带归档的 bootstrap pass，失败被吞掉；判据
是第二次 `kernel.log` 能否链接成功。

### 2.3 ABL 与看门狗

- 无 splash 节点时 ABL 关屏：`/reserved-memory/splash_region` 由 `board.toml` 的
  `[[bootimg.dtb_node]]` 注入（值为 vermeer 的 0xb8000000+0x2b00000，**待 socrates dtbo
  确认**）。
- 几秒自动重启 = 看门狗未关（PM8550 WDT），同 vermeer 首启现象。
- `SOCRATES_VENDOR_HW = 0`（纯 Mu 驱动）时固件自己构内存映射，4 GiB 以下可用内存按
  16 MiB 粒度合并，超大 `owned_memory_size` 请求会 `EFI_OUT_OF_RESOURCES`，`board.toml`
  暂用 0x10000000（256 MiB），待真机最大连续段确认。

### 2.4 SEC SP_ELx 与 GIC 假中断

Mu-Silicium 需要 SEC 先切 SP_ELx（沿用）；`Resources/MuPatches/Gic-Spurious.patch`
屏蔽 IPCC INTID 0x105，`board.toml` 已带。

## 3. 板级硬件事实

### 3.1 手机自报（2026-11-03，adb 实测）

| 项 | 值 |
| --- | --- |
| 机型 | Redmi K60 Pro（`Redmi/socrates/socrates`） |
| 系统 | HyperOS `OS3.0.304.0.WMKCNXM`（Android 16，BP2A.250605.031.A3） |
| SoC | SM8550（`ro.soc.model`，`ro.board.platform=kalama`） |
| 内核 | Linux 5.15.194-android13（ab15212794） |
| root | 无（Magisk 30.7 应用在装，未打补丁进 boot） |
| 串号 | e5945880 |

### 3.2 SoC 级（SM8550，与 sheng/vermeer 共享，出自 `UniXNU-sm8550-common`）

| 项 | 值 |
| --- | --- |
| GIC | dist `0x17100000/0x10000`，redist `0x17180000/0x200000`，stride 0x40000 |
| 计时器 | 19.2 MHz |
| UFS 控制器 | `ufshc@1d84000`（+0x3000），PHY `@1d80000` |
| GPU | Adreno 740 `gpu@3d00000` |
| DRAM 基址 | 0x80000000 |

### 3.3 板级（TODO：全部待 socrates 固件提取）

| 项 | 状态 | 预期 |
| --- | --- | --- |
| UEFI FD / stack / Display Reserved 窗 | ⏳ 待 `uefiplat.cfg` | vermeer：FD 0xA7000000、stack 0xA760D000、DispReserved 0xB8000000 |
| splash carveout | ⏳ 待 dtbo | 与 Display Reserved 同窗 |
| 面板 / PCD | ⏳ 待 dtbo | 3200×1440 双 DSI video-mode（K60 Pro 2K 屏），以 GOP 实报为准 |
| 触摸控制器 | ⏳ 待 dtbo | Goodix（vermeer 为 GT9916S @ I²C 0x5d，SE4 GPIO 44–47） |
| GMU 窗 | ⏳ 待 base dtb | sheng 0x3d6a000 / vermeer 0x3d68000，**必须实测** |
| `[userdata]` GPT | ⏳ `fastboot oem get-partition-info` | board.toml 现为 sheng 占位值 |

## 4. 首启前必须解决的缺口

### 4.1 固件解包（阻塞项）

`socrates_images_OS3.0.304.0.WMKCNXM_*.tgz` → `scripts/data/`：
`socrates.dtb`（boot 镜像内核 dtb）、`socrates-uefiplat.cfg`（uefi.img 的 gzip GUIDed
section `1D301FE9-…`）、`socrates-dtbo.img`。见
`scripts/data/SOCRATES-FIRMWARE-NOT-EXTRACTED.md`。

### 4.2 `unique_chip_id`

首启用 CI 值（如 `0000000000000001`）即可；正式设备换真值，避免 `IOPlatformUUID` 撞车。

### 4.3 触摸

控制器待 dtbo 确认后写驱动；可借力 `dipa-studio/ios-sweet` 的 Goodix 补丁
（0060/0062/0063）。注意 edge touch 标记。板里 `sheng-touch` 相关参数保持 0。

### 4.4 GPU

`CONFIG_XNU_NATIVE_ADRENO=n` 直到 socrates 的 GMU 窗从 base dtb 读出，
`prepare-sheng-gmu.py` 的输入集换成 socrates 的。

## 5. 首启验收标准

`boot.img` 组成：BootShim + SILICIUM_UEFI.fd + socrates 固件 DTB（含 splash 节点）
+ payload 卷。真机（不写任何分区）：

```bash
fastboot boot out/socrates/boot/boot.img
```

通过标准：**屏幕上出现内核 console 输出**（或 panic screen 文字），且不发生几秒后
自动重启（后者 = 看门狗）。

## 6. 上游与社区参考

| 来源 | 借什么 |
| --- | --- |
| `yyx2025/UniXNU-vermeer` | 本仓库的底本：板级流程、ADT 生成器、bring-up 阈值 |
| `UniXNU/UniXNU-sheng` | SoC 级驱动、payload 链、porting record 写法 |
| `hanzi123-bilp/unixnu-fuxi` 等 | SM8550 手机板级数值佐证（fuxi/nuwa/ishtar 同为 8 Gen 2） |
| `dipa-studio/ios-sweet` | Goodix 触摸协议、无串口调试 |
| `oosexgang/hakios-xnu-kernel` | 设备目录化移植结构、日志回传 |
