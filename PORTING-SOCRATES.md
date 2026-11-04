# socrates 移植记录（Redmi K60 Pro / SM8550）

本文记录板级决策、从 vermeer/sheng 带来的结论，以及首启前还缺什么。规则与 vermeer 的
PORTING 文档相同：**每个数值都有出处**——要么是本机固件提取，要么是同 SoC 上游板
（sheng / vermeer），要么明确标注为未验证。socrates 尚无任何真机观察，因此除
「手机自报」一栏外，所有状态都是 🔧 未验证或 ❌ 缺失。

## 1. 当前状态

| 环节 | 状态 | 依据 |
| --- | --- | --- |
| UEFI 固件（socratesPkg → SILICIUM_UEFI.fd） | 🔧 骨架来自 vermeerPkg；**内存图与 RawFiles 已换成 socrates 实测输入**，尚未构建、未上真机 | 本仓库 + `uefi-socrates` |
| 固件解包 | ✅ base dtb / uefiplat.cfg / dtbo / GPT 全部提取（2026-11-03） | `scripts/data/`，§3.3 |
| 内核配置 + prelink（iPadOS 17.7.11 / iPad7,1） | 🔧 `configs/socrates_defconfig`，板级注释已按实测值更新 | vermeer 同款链 |
| payload / boot.img | ⏳ 依赖 kernel + firmware | `build-kernel.yml` 的 `bootimg` job |
| 存储（UFS） | ⏸ 首启阶段关闭，见 §2.1 | `CONFIG_XNU_NATIVE_UFS=n` |
| 显示 | 🔧 走 UEFI GOP + `splash_region`（实测：**command-mode + DSC 面板**，见 §4.5） | `[[bootimg.dtb_node]]` |
| 触摸 | ❌ Goodix SPI（`xiaomi,m11-spi`）已确认，驱动待写 | §4.3 |
| GPU / WiFi / 音频 | ❌ GPU 寄存器表已实测（§3.3），驱动未接 | `CONFIG_XNU_NATIVE_ADRENO=n` |

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
  `[[bootimg.dtb_node]]` 注入（实测值 0xb8000000+0x2b00000，与 stock uefiplat.cfg 的
  Display Reserved 同窗）。
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
| 串号 | （已隐去） |

### 3.2 SoC 级（SM8550，与 sheng/vermeer 共享，出自 `UniXNU-sm8550-common`）

| 项 | 值 |
| --- | --- |
| GIC | dist `0x17100000/0x10000`，redist `0x17180000/0x200000`，stride 0x40000 |
| 计时器 | 19.2 MHz |
| UFS 控制器 | `ufshc@1d84000`（+0x3000），PHY `@1d80000` |
| GPU | Adreno 740 `gpu@3d00000` |
| DRAM 基址 | 0x80000000 |

### 3.3 板级（实测：2026-11-03，自 OS3.0.304.0.WMKCNXM 固件提取）

提取方法：uefiplat.cfg 为 uefi.elf 的明文区（0x4703b–0x490bf，sha256 `90648bc5…`）；
base dtb 为 vendor_boot.img 的两块 dtb 中的 QCM 块（msm-id 0x25c）；板级节点为
dtbo.img entry 50（model "8550 socrates"，`xiaomi,miboard-id = 4`，三个 socrates
条目面板/触摸配置一致）。文件已入 `scripts/data/`，见其 README。

| 项 | 实测值 |
| --- | --- |
| UEFI FD / stack / Display Reserved | FD 0xA7000000（4 MiB 窗）、stack 0xA760D000+0x40000、Display Reserved 0xB8000000+0x2B00000 —— 与 sheng/vermeer 相同；DXE Heap 0xBAB00000+0xD1C0000、Kernel 0xA8000000+0x10000000、PIL 0x8A800000+0x18280000、TZApps 0xD8800000+0x7400000 |
| splash carveout | dtbo `splash_region` = 0xb8000000+0x2b00000（= Display Reserved 窗） |
| 面板 | `qcom,mdss_dsi_m11_42_02_0a_dsc_cmd`，**1440×3200，DSI command mode + DSC**，"xiaomi 42 02 0a cmd mode dsc dsi panel"；原厂 XML `Panel_M11_42_02_0a_dsc_cmd.xml` 已提取（uefi-socrates/RawFiles） |
| 触摸 | **Goodix SPI**：`goodix@0`，compatible `xiaomi,m11-spi`，fw `goodix_firmware_m11` / cfg `goodix_cfg_group_m11`，SPI 15 MHz，IRQ GPIO 25、reset GPIO 24（pinctrl GPIO 44–46），panel-max 14400×32000 |
| GPU（base dtb 实测） | `qcom,kgsl-3d0@3d00000`，adreno gen7.2.1：kgsl 窗 **0x3d00000+0x400000（4 MiB）**、cx_dbgc 0x3d61000+0x8000、rscc 0x3d50000+0x10000、isense 0x3d8b000+0x20000、cx_misc 0x3d9e000+0x1000、zap-shader 走 memory-region |
| `[userdata]` GPT | first_lba **0x2f7840**（stock GPT，4096B 扇区）；last_lba 为 256 GiB 机型估算值，待 `fastboot oem get-partition-info` 实测 |
| 保留内存 | 30 个固定 no-map 区 + splash（见 uefi-socrates 的 MemoryMapLib，全部来自实测） |
| 其他 | 功放 2× CS35L41（@40/@42）、NFC sn-nci nq@28、dtbo 的 disp_rdump_region 在 Display Reserved 窗内 |

## 4. 首启前必须解决的缺口

### 4.1 固件解包（✅ 已完成，2026-11-03）

`socrates.dtb` 与 `socrates-uefiplat.cfg` 已在 `scripts/data/`（出处与 sha256 见其
README）。uefiplat.cfg 实际是 uefi.elf 里两个压缩 FV 之前的**明文区**（0x4703b–
0x490bf），无需解压 FV；FV 本身用 UEFIExtract 全量解开以提取 RawFiles（见
uefi-socrates）。`[userdata]` last_lba 仍需真机 fastboot 实测（估算值已注明）。

### 4.2 `unique_chip_id`

首启用 CI 值（如 `0000000000000001`）即可；正式设备换真值，避免 `IOPlatformUUID` 撞车。

### 4.3 触摸

实测为 **Goodix SPI**（`xiaomi,m11-spi`，fw `goodix_firmware_m11`，IRQ 25 / reset 24，
SPI pinctrl GPIO 44–46，15 MHz）。sheng 的 `NativeNovatekTouch`（I²C NT36532E）与此
无关，保持 `sheng-touch=0`。可借力 `dipa-studio/ios-sweet` 的 Goodix 补丁
（0060 GENI SPI、0062、0063），但报文格式要按 m11 固件核对；注意 edge touch 标记。
`proprietary-files.txt` 的条目要等确认 `/vendor/firmware/goodix_firmware_m11.bin`
（或同名）后再加，配 SHA-256。

### 4.4 GPU

寄存器表已实测（§3.3）：kgsl 窗 4 MiB（0x3d00000+0x400000），cx_dbgc 0x3d61000。
`CONFIG_XNU_NATIVE_ADRENO=n` 保持，直到 `prepare-sheng-gmu.py` 的输入集（SHA 固定的
Linux a6xx 源 + 编译后的 DTS）换成 socrates 版本并在真机上验证。

### 4.5 显示：command-mode 面板是首启显示链的首要风险

实测面板是 **DSI command mode + DSC**（`m11_42_02_0a_dsc_cmd`），不是 vermeer 的
video-mode。video-mode 面板自扫描 splash 缓冲，UEFI 不动显示控制器也能"亮"；command
模式面板的像素流由 MDP 从 framebuffer 持续发出，ABL 交出的 splash 状态在 XNU 接管
后能否维持未经验证。首启验收允许"屏幕保持 ABL 画面而日志在走"；真黑屏/花屏时优先
怀疑这条链，再考虑接 DisplayDxe + `Panel_M11_42_02_0a_dsc_cmd.xml`（已提取，在
uefi-socrates/RawFiles）。

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
