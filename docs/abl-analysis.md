# Redmi K60 Pro (socrates) ABL 逆向分析报告

- 分析对象：`D:\gittest\unixnu-work\firmware\extracted\socrates_images_OS3.0.304.0.WMKCNXM_16.0\images\abl.elf`（233,272 字节）
- 固件版本：HyperOS OS3.0.304.0.WMKCNXM（Android 16），bootloader unlocked:yes，fastboot getvar `crc:1`
- 分析日期：2026-11-04
- 结论适用：`fastboot boot` 自制 v0 boot.img 返回 OKAY 后"关屏、不跳转、fastboot 仍在线"的问题定位与绕过

---

## 0. 二进制本身的关键发现：abl.elf 代码段是加密的（无法直接反汇编）

abl.elf 不是普通的明文 Qualcomm aarch64 ELF，结构如下：

```
ELF32 头（machine=0x28/ARM32 包装，entry=0x9fa00000）
PH0: p_type=0, p_flags=0x7000000, 覆盖文件头 0x94 字节
PH1: p_type=1 (LOAD), vaddr=0x9fa00000, filesz=0x37000  ← 代码段，整段加密
PH2: p_type=0, p_flags=0x2000000, off=0x38000, 0xf38 字节 ← 签名/attestation 元数据段
```

- PH1 代码段（0x1000–0x38000）熵值 **7.99/8.0**，无任何可读字符串、无 ARM64 指令特征 → **AES 加密**（文件末尾还有明文 0xff padding，段首 16 字节为零 IV 区，符合 Qualcomm ELF v7 加密段格式）。
- PH2 元数据段为明文，含 attestation 字段（hw_id=0x18、msm 区段、sw_id 等）与证书链：
  `CDMA Technologies / General Use for Xiaomi Secureboot`（Qualcomm 根证书）→ `Generated Xiaomi Attestation CA / SecToolsV2` → Xiaomi 三级证书（2024/2021 年签发）。
- 对照组证明这是格式而非偶然：
  - `imagefv.elf` **同样加密**（完全相同的 ELF32 包装 + 单加密段 + 相同尺寸的 PH2 元数据段）；
  - `xbl_config.elf`、`uefi_sec.mbn`、`aop.mbn` 均为**明文**。
- 即：小米从某个 HyperOS 版本起对 abl（和 imagefv）分区启用了 Qualcomm sectools 的**镜像段加密**，密钥经 QFPROM/设备端密钥体系封装，**离线无法解密**，静态反汇编这条路线对本机 abl.elf 不可行。这也是社区"小米 ABL 已不可打补丁"的原因。

### 那么这台机器的启动链是什么结构？（uefi.elf 分析结论）

本机是新式"两段式"布局：

- `uefi.elf`（2.9MB，**明文**，FV 结构）：平台 UEFI——SEC core、DxeCore、DisplayDxe、QcomBds、QcomChargerApp、Ebl、VerifiedBootDxe、SecurityStubDxe、uefiplat.cfg、BDS_Menu.cfg 等（DXE 卷整体 LZMA 压缩，GUID 1D301FE9…）。**其中没有任何 "fastboot"/"Load Error"/"vbmeta" 字符串**。
- `abl.elf`（加密，代码 225KB @ 0x9fa00000）：真正的 ABL/QcomModulePkg——fastboot 应用、LinuxLoader、AVB 校验、boot image 解析等全部在这里。

因此本报告的代码级结论来自两条途径交叉验证：
1. **上游 Qualcomm ABL 源码**（CodeLinaro 世系，本机使用了 `prabhatkrmishra/android_bootable_bootloader_edk2` 的 LA.UM.9.12.r1 SM7450 快照逐行分析；SM8550/LA.UM.9.15+ 为同源更新版，逻辑一致）；
2. **同项目 raphael（K20 Pro, HyperOS4）上的实机 log 证据**（本仓库 issue #26，从 logfs 分区取到的真实 ABL 日志，行为与本机症状完全一致）。

`uefiplat.cfg`（uefi.elf 内）给出的关键内存布局：
```
0xA8000000, 0x10000000, "Kernel"      ← ABL 的 kernel 加载窗口（256MB）
0xA7000000, 0x00400000, "UEFI FD"     ← 平台 UEFI FD（运行中代码）
0xBAB00000, 0x0D1C0000, "DXE Heap"    ← DXE 堆
0xB8000000, 0x02B00000, "Display Reserved"
```

---

## 1. `fastboot boot` 的完整校验链（源码级）

入口 `CmdBoot()`（`QcomModulePkg/Library/FastbootLib/FastbootCmds.c:2806`）。按执行顺序：

### 1.1 前置门槛
| 检查 | 位置 | v0 镜像结果 |
|---|---|---|
| MDTP 激活则拒绝（小米关闭 MDTP） | CmdBoot 2818 | 通过 |
| **`IsUnlocked()` 必须为真**，否则 "Fastboot boot command is not available in locked device" | CmdBoot 2833 | 通过（unlocked:yes）|
| 下载大小 ≥ sizeof(boot_img_hdr) | CmdBoot 2838 | 通过 |
| header_version ≤ 2 → 按 v0/v1/v2 的 cmdline 布局截断；≥3 → 按 v3 布局截断 | CmdBoot 2843 | 通过（v0 走旧布局）|

### 1.2 LoadImageAndAuth（`Library/avb/VerifiedBoot.c:1655`）——"OKAY/FAILED" 就在这里决定
取 AVB 版本 = AVB_2 → `LoadImageAndAuthVB2()`（:1093）：

1. `avb_should_update_rollback()` → `UpdateRollbackSyscall()`：**TZ SCM 调用更新防回滚索引**（这是 ABL 层的 anti-rollback；小米另有 XBL/secureboot 层的 ARB，见 §1.5）。
2. **fastboot boot 的特殊分支**：因为 `Info->NumLoadedImages==1`（内核已由 fastboot 下载在内存里），**"boot" 不会被加进 AVB 验证请求列表**——即 ABL 从不校验你下载的镜像本身，只验证：
   - `requested = {dtbo}`（header v0/v1/v2 时）；
   - header ≥ 3 时再加 `vendor_boot`（新版还会要 `init_boot`）。
   这些是从**闪存分区**读出来、对着设备上的 vbmeta/vbmeta_system 链验证的。
3. `AllowVerificationError = IsUnlocked()`：解锁状态下 `avb_slot_verify` 返回的 `ERROR_VERIFICATION / ERROR_ROLLBACK_INDEX / ERROR_PUBLIC_KEY_REJECTED` 都放行（`ResultShouldContinue()`，:704）；但 `ERROR_IO/OOM/INVALID_METADATA/UNSUPPORTED_VERSION/INVALID_ARGUMENT` 仍会失败并返回 **EFI_LOAD_ERROR**（= fastboot 报的 "Load Error"）。
4. `CheckImageHeader()`（`BootLinux.c:1131`）校验下载镜像的 header：`ANDROID!` magic、page_size（≤4096 且与 ImageHdrSize 匹配）、kernel_size 非零、各 size 算术溢出检查。**v0 只查这些**；dtb_size 字段只对 v2 有意义，v0/v1 忽略。
5. BootState=**ORANGE**（解锁），`KeyMasterSetRotAndBootState()`（把 boot state/ROT 发给 TrustZone KeyMaster）、`ComputeVbMetaDigest`、`SetVerifiedBootHash`。
6. 成功 → `DisplayVerifiedBootScreen(ORANGE)`（小米已删掉橙色警告页）→ 返回 SUCCESS。

**→ 返回 SUCCESS 后 CmdBoot 打印 `FastbootOkay("")`（这就是你看到的 "Booting OKAY"），随后依次：`ExitMenuKeysDetection()`（停掉按键检测 → 解释"按键输入失灵"）→ `FastbootUsbDeviceStop()` → `BootLinux(&Info)`。**

OKAY 只代表 LoadImageAndAuth 通过。**fastboot 协议里没有任何"OKAY 之后再报错"的通道**——之后 BootLinux 里所有失败都是静默的：函数直接 return，主循环 `HandleUsbEvents()` 继续跑，USB 仍应答 → 解释"fastboot 仍在线"。

### 1.3 BootLinux（`Library/BootLib/BootLinux.c:882`）——OKAY 之后的链（v0 路径）
按顺序，任何一步失败都**静默返回 fastboot 循环**（fastboot 不报错）：

1. `GetImage`：取下载的镜像（成功）。
2. `UpdateBootParamsSizeAndCmdLine`（v0：从 header 读 kernel/ramdisk/second/page_size）。
3. `BaseMem`（=0x80000000）。
4. **`UpdateKernelModeAndPkg`**：在 kernel 起始处检查 gzip magic（`1f 8b 08`）→ `BootingWithGzipPkgKernel=TRUE`；否则检查 "ARM\x64" magic（offset 0x38）判定 64 位内核。
5. `UpdateBootParams`：从 UEFI 保留的 kernel 窗口计算 `KernelLoadAddr = 0xA8000000+0x8000`、`RamdiskLoadAddr = 窗口末-ROUND(ramdisk)`、`DeviceTreeLoadAddr = Ramdisk-2MB-4K`。
6. **`GZipPkgCheck`**：ABL **自己用 zlib inflate 解压 gzip 内核**到 KernelLoadAddr；`DtbOffset = gzip 流结束 + 8`（即"追加 DTB"的起点）；然后检查解压输出头部 `magic_64`（"ARM\x64"）≠ 则按 32 位内核处理。你们的 BootShim 在 0x38 处有 "ARM\x64"（已验证解压头 `…41524d64`），64 位路径正确。
7. **`DTBImgCheckAndAppendDT`（`BootLinux.c:417`）—— 最关键的一步，见 §2。**
8. `UpdateCmdLine`、`LoadAddrAndDTUpdate`（内部 `UpdateDeviceTree()` 把 cmdline/内存图/ramdisk 节点写进 DTB，并把 64MB ramdisk 拷到 RamdiskLoadAddr）。
9. `FreeBootLogoBltBuffer` → **`ShutdownUefiBootServices()`** → `PreparePlatformHardware()`（关 cache/MMU）→ `LinuxKernel(DeviceTreeLoadAddr,0,0,0)` 跳转。
   **注意**：Shutdown 之后的任何失败都会走 `CpuDeadLoop()` 死循环——USB 必然失联。你们的 USB 还活着 ⇒ **失败点必然在 Shutdown 之前**，即第 1–8 步之间。

### 1.4 "Booting OKAY 但关屏"
上游代码里没有 OKAY 后立即关屏的调用；结合 raphael 实测（issue #26："the screen stays black the whole time"）与小米 ABL 的已知行为：**小米在提交启动（进入 mission mode / BootLinux）时把面板关掉**，属于小米补丁的正常现象，不代表走到了跳转那一步。按键失灵 = `ExitMenuKeysDetection()` 的直接结果。所以"关屏 + 按键失灵 + fastboot 在线"三件事都与"BootLinux 中途静默失败"完全自洽。

### 1.5 anti-rollback 与 crc 的位置
- **ABL 内的防回滚**：① `UpdateRollbackSyscall()`（TZ SCM，把当前 slot 的 rollback index 写入安全环境/RPMB）；② AVB 的 `ERROR_ROLLBACK_INDEX`——但解锁状态放行，不影响 fastboot boot。
- **Xiaomi ARB（anti=x）**：在 XBL/secureboot 层（降级保护），不拦截 fastboot boot。
- **`crc:1`**：上游 ABL 没有这个 getvar，是小米加的 fastboot 协议扩展（对 download/flash 传输做 CRC 校验的开关，供 MiFlash 协议用）。它作用于**传输完整性**，不在 boot 校验链里——你们的下载都成功完成，与本问题无关。
- **DTB msm-id/board-id 匹配**：不在 LoadImageAndAuth 里，而在 BootLinux 的 DTB 阶段（见下）。

---

## 2. v0 路径"OKAY 但不跳转"的机制（按可能性排序）

USB 存活 ⇒ 失败点在 ShutdownUefiBootServices 之前。结合源码 + 你们自己的 raphael 实测证据：

### ① DTBO overlay 应用失败（可能性最高，raphael 上已被实锤）
`DTBImgCheckAndAppendDT` 先 `LoadAndValidateDtboImg()` 读**设备 dtbo 分区**（socrates dtbo 16MB < 上限 24MB，校验通过）→ 进入 **DTBO overlay 分支**：

```
GetSocDtb()      在追加 DTB 里按 qcom,msm-id 找 SoC 匹配
   → 你们的 DTB msm-id = <0x25c 0x20000>，与本机一致（socrates_dtbo.txt 证实设备就是 0x25c/0x20000）→ 匹配 OK
GetDtboNeeded()  你们 DTB 的 board-id=<0 0>、无 qcom,pmic-id → 非完全匹配 → 需要 DTBO
GetBoardDtb()    在设备 dtbo 表里找 board 匹配（本机 board-id=0x10008，dtbo 里有对应条目）→ 找到
ApplyOverlay()   ufdt_apply_multi_overlay() 把 dtbo 里所有匹配 overlay 合到你们的 base DTB 上
   → 失败： "ApplyOverlay: ufdt apply overlay failed" / "Error: Dtb overlay failed" → return → 静默回到 fastboot
```

**实锤证据**：本仓库 issue #26（raphael，HyperOS4 ABL）从 logfs 读到的真实日志：
```
Handling Cmd: boot
Booting Into Mission Mode
VB2: boot state: orange(1)
Decompressing kernel image total time: 361 ms
ApplyOverlay: ufdt apply overlay failed
Error: Dtb overlay failed
Handling Cmd: getvar:product        ← 直接回到 fastboot 菜单
```
症状签名（OKAY → 黑屏 → fastboot 循环活着 → 按键失灵）与 socrates 完全一致。

socrates 更容易踩中：16MB 的 dtbo 是多机型共享表（socrates 家族多 board/`xiaomi,miboard-id` 变体），`ufdt_apply_multi_overlay` 会把**所有**匹配 overlay 全部叠上去；而你们追加的 base DTB 是从 vendor_boot DTB 表抽出的 **"Kalama QCM SoC" 通用 SoC 级 DTB**（`qcom,board-id=<0 0>`、无 pmic-id、无 xiaomi 节点），overlay 的 fragment 引用的 phandle/symbol 在里面不齐 → 合并失败。raphael 上"DTB 看起来完全正确也一样失败"，说明小米的 dtbo 对非原始组合极其挑剔。

### ② GetBoardDtb / dtbo 表解析失败（可能性中）
若 dtbo 条目与追加 DTB 的 `DtbIdx` 对不上（你们只追加了 1 个 DTB，DtbIdx=0，而 dtbo 表里第 0 条未必是 socrates 的 board），`GetBoardDtb` 返回 NULL → `EFI_NOT_FOUND` 静默返回。

### ③ UpdateDeviceTree / UpdateCmdLine 失败（可能性低）
ABL 把最终 cmdline、UEFI 内存图、ramdisk、Xiaomi 附加节点写进你们的 DTB；DTB 结构异常才会挂。

### ④ 小米自定义的 OKAY 后检查（无法排除）
ABL 加密导致无法直接证伪"小米在 BootLinux 里加了额外静默检查"。但 ①+② 已能完整解释现象，且有 raphael 先例，优先按 ① 处理。

### 已排除的假说（供参考）
- **不是 32 位误判**：BootShim 0x38 处有 "ARM\x64"（已验证）。
- **不是 gzip 解压失败**：raphael 日志显示解压 361ms 成功后才挂；socrates 的 gzip/追加 DTB 结构与之相同。
- **不是 Shutdown 之后崩溃**：那会走 `CpuDeadLoop()`，USB 必死。
- **不是 AVB/解锁状态**：OKAY 已经证明 LoadImageAndAuth 全过（fastboot boot 时下载镜像根本不参与 AVB，只验闪存里的 dtbo/vbmeta）。
- **不是 header v0 被拒**：上游对 v0/v1/v2 完全同路；v0 也没触发 v4 那种 Load Error。

---

## 3. v4（官方原版 boot.img）"Load Error" 的触发条件

报错字符串在 `CmdBoot`（FastbootCmds.c:2870）：`"Failed to load/authenticate boot image: %r"`，`%r` = **EFI_LOAD_ERROR** 的名字 "Load Error"。LoadImageAndAuthVB2 内会返回 EFI_LOAD_ERROR 的点：

1. `avb_slot_verify` 结果不在解锁放行名单（ERROR_IO/OOM/INVALID_METADATA/UNSUPPORTED_VERSION/INVALID_ARGUMENT）：
   - **内存压力**：v4 会同时要求验证闪存里的 `dtbo`(16MB)+`vendor_boot`(100MB)，加上已下载的 100MB boot.img，DXE 堆（~209MB）可能吃紧 → ERROR_OOM 不放行 → Load Error；
   - vbmeta/vbmeta_system 结构问题 → ERROR_INVALID_METADATA；
   - 你要 boot 的 boot.img 与设备上 vbmeta 描述的 boot 哈希不一致（例如 boot 分区被改过）时，**上游本来也不该失败**——因为 fastboot 路径里 "boot" 根本不在验证列表。
2. `SlotData==NULL` / `NumLoadedImages < NumRequestedPartition`（请求的分区在 SlotData 里找不到，如 dtbo/vendor_boot 缺失或读失败）。
3. **小米补丁（socrates 上最可能的主因）**：上游逻辑对"原厂 v4 boot.img + fastboot boot"应当放行（每次正常开机都会完整跑通 dtbo+vendor_boot 的 AVB 验证），而你们稳定被拒 ⇒ 小米在 HyperOS 世代 ABL 里对 **header v3+（GKI）的 fastboot boot 增加了拦截**（社区共识：HyperOS 已封 `fastboot boot` 官方 GKI 镜像）。
4. **"脏 ABL 状态"（raphael 实锤的第二路径）**：issue #26 观察到——从硬件按键进入 fastboot、或 crash 重启后进入 fastboot 时，连已知可启动的镜像也稳定报 "Load Error"；先执行一次 `fastboot reboot-bootloader` 让 ABL 干净重启后即可恢复。这可能同时解释你们 socrates 上 v4 的稳定拒绝（如果每次都是按键进 fastboot 测的）。

对 v4 的建议：先 `fastboot reboot-bootloader` 再试一次；若仍拒，则确认是小米 v3+ 拦截，**放弃 v4 路线，坚持 v0/v1/v2**（你们的 v0 已通过认证层）。

---

## 4. 绕过手段清单（让自制镜像真正跳转）

### 4.1 已验证的"唯一确定解"：清零 dtbo 分区（raphael 实测完全成功）
```
# 制作全零 dtbo（注意：必须是全 0/坏 magic，不能是"合法的空 DTBO 表"——
# 合法空表会让 LoadAndValidateDtbo 通过、走 overlay 分支、然后 GetBoardDtb 返回 NULL 反而失败）
fastboot flash dtbo dtbo_empty.img     # 全零，16MB
fastboot boot boot.img                  # ABL 找不到匹配 overlay → 直接用镜像内 DTB → 跳转
```
raphael 上结果：`product: xnuloader` 一次成功，随后 iOS 16.5 完整启动、触控正常。代价：Android 无法正常开机（面板配置在 dtbo 里），实验完必须 `fastboot flash dtbo dtbo.img` 还原（提取目录里有官方 dtbo.img）。socrates 面板配置同样在 dtbo，**还原前别重启进系统**。

### 4.2 不动 dtbo 的替代方案："完全匹配"跳过 dtbo —— 复核后判定为【不实用】，仅存档
`GetSocDtb` 里 `CheckAllBitsSet()` 成立时打印 "Exact DTB match found. DTBO search is not required" → 跳过 dtbo。但复核 LA.UM.9.12 源码的 `ALL_BITS_SET`（LocateDeviceTree.h:141）后发现它要求 **PMIC_MATCH_EXACT_MODEL_IDX0…IDXF 全部 16 个位** + SOFTSKU_EXACT + FOUNDRYID_EXACT + SOC + VARIANT + SUBTYPE_EXACT：
- `ReadBestPmicMatch` 默认只按 4 槽（`qcom,pmic-id-size` 缺省=4）打 IDX0..3 位 → IDX4..F 永远为 0 → **4 槽 pmic-id 不可能凑齐 ALL_BITS_SET**；理论上要造 `qcom,pmic-id-size=<16>` + 4 个真值 + 12 组 0（0==0 视为 exact）。
- 更致命：实测 socrates 全部 57 个 dtbo overlay、两个 base DTB、fuxi.dtb **均无 qcom,pmic-id 属性**——现代小米 DTB 根本不带 pmic-id，PMIC 真值只能从 logfs/ABL 日志或运行中系统 dmesg 获取。
- 结论：**Exact-match 路线在本机世代不可达**。缺 pmic-id 不影响 DTB 被选中（fdt_getprop NULL → 跳过、不加位、不拒绝），只影响"跳过 dtbo"。所以实用方案回到 4.1（清零 dtbo）+ 可选的离线 overlay 合并（合并后必须配合清零 dtbo，否则 ABL 会把同一 overlay 再叠一次）。
- 注意：dtbo 表条目的 `id/rev/custom` 字段全为 0，GetBoardDtb 的匹配完全靠 overlay DTB 根节点的属性；ABL **看不到 `xiaomi,miboard-id`**，在 8 个 msm=0x25c/board=0x10008 的 overlay（miboard 1/2/5/6/7/8/4/0x1000，即 entry 0/3/6/28/44/47/50/53）中按 ReadDtbFindMatch 平手 → ABL 选中**第一个**（entry 0，miboard=6）。若做离线合并，合并目标（如 entry 50/miboard=4）与 ABL 在 stock dtbo 下会选的 entry 0 不同——又一个必须清零 dtbo 才能保证确定性的理由。

### 4.3 ABL 状态
每次尝试前先 `fastboot reboot-bootloader`，避免"脏状态 Load Error"（v4 镜像尤其）。

### 4.4 不存在的旁门（分析过、排除）
- **fastboot oem 命令**：上游只有 `oem enable/disable-charger-screen`、`oem off-mode-charge`、`oem select-display-panel`、`oem device-info`、`oem display-cmdline`；小米加了 `oem unlock/lock/reboot-edl` 等，**没有任何能关 DTBO/AVB/校验的 oem**。
- **改 ABL 本身**：abl.elf 加密（§0），XBL 校验签名后才会解密，离线改不了也签不了；xbl/xbl_config/abl 分区在 HyperOS 上还有刷写保护+ARB。**此路不通**。
- **特殊 header 字段**：v0 的 kernel_offset/tags_offset 在现代 ABL 里完全不被读取（地址来自 UEFI kernel 窗口），不需要也不能用来影响行为；`header v1` 与 v0 在 ABL 里同路径，不必改。
- **绕开 header 拦截**：不存在——v0/v1/v2 没有 header 层拦截（你们的 OKAY 已证明）。

### 4.5 先例配方（SM8550 上游同代 ABL 已跑通的 boot.img 结构）
edk2-msm（Renegade Project）支持 Xiaomi 13（fuxi，SM8550，同款 ABL 世代）`fastboot boot`，其构建配方值得逐项对齐：
```
kernel   = cat BootShim.bin UEFI.fd | gzip -c   →  再追加 FdtBlob_compat/*.dtb
mkbootimg --kernel <上面整体> --ramdisk ramdisk \
          --kernel_offset 0 --ramdisk_offset 0 --tags_offset 0 \
          --header_version 1  --os_version 13.0.0 --os_patch_level 2022-11
```
- **header v1**（他们不用 v0/v2+；v1 与 v0 在 ABL 内路径相同，用哪个都行）
- offsets 全 0（ABL 不读）
- 追加的 FdtBlob_compat DTB 是**带完整 msm-id/board-id 的整机 DTB**（fuxi.dtb 根节点 `qcom,msm-id=<0x207 …><0x218 …>`、`qcom,board-id=<0x10008 0>`，802KB）——即 4.2 的思路。
- BootShim 结构与你们一致（192B shim，0x38 处 "ARM\x64"，复制 FD 后跳转）。

### 4.6 你们镜像的下一步（按优先级）
1. `fastboot reboot-bootloader`；
2. 方案 A（最快）：清零 dtbo → `fastboot boot` → 验证跳转；
3. 方案 B（可长期用）：按 4.2 把 socrates 的 msm-id/board-id/pmic-id 补进追加 DTB（或离线合并 overlay），做成 Exact match；
4. 跳转成功后再核对 FD 目标地址：你们 shim 的 UEFI_BASE=0xA7100000，与平台 UEFI FD 区（0xA7000000+4MB，uefi.elf FD 实际 2.9MB）重叠。这在 Shutdown 之后理论上是安全的（BootShim.Dualboot 正是这么干的），但若出现跳转后黑屏/USB 掉线，可参考 edk2-msm 把 FD 挪到空闲 DDR（fuxi 用 0xCE000000）再试；
5. 出问题时读 `logfs` 分区拿 ABL 日志（raphael 方法）——比猜有效得多：关键字 `ApplyOverlay`、`Dtb overlay failed`、`Decompressing`、`Mission Mode`。

---

## 5. 一句话总结

ABL 对 `fastboot boot` 的认证层（header 检查 + AVB(dtbo/vbmeta) + anti-rollback）你们已经全部通过（"OKAY"），卡死在 **OKAY 之后 BootLinux 的 DTB/DTBO 阶段**：ABL 把设备 16MB dtbo 的 overlay 用 ufdt 合并到你们追加的通用 "Kalama QCM" DTB 上失败，于是**静默**退回 fastboot 主循环——关屏（小米提交启动即关面板）、按键失灵（ExitMenuKeysDetection）、USB 继续应答（主循环未死）三个症状全部由此解释；v4 官方镜像的 "Load Error" 则是小米对 GKI/v3+ 的 fastboot boot 拦截（叠加"按键进 fastboot 的脏状态"效应）。**首选绕过 = 清零 dtbo 分区（raphael 实测成功），长期方案 = 把追加 DTB 做成完全匹配（msm-id 0x25c/0x20000 + board-id 0x10008 + pmic-id）或离线合并 overlay。**

---

### 附：证据与来源索引
- abl.elf 加密结构：本地解析（ELF32 头/PH/熵分析）；`imagefv.elf` 同构对照；`uefi_sec.mbn`/`xbl_config.elf` 明文对照。
- 上游源码：`prabhatkrmishra/android_bootable_bootloader_edk2`（LA.UM.9.12.r1，CodeLinaro 世系；关键文件 `QcomModulePkg/Library/FastbootLib/FastbootCmds.c`、`Library/avb/VerifiedBoot.c`、`Library/BootLib/BootLinux.c`、`Library/BootLib/LocateDeviceTree.c`、`Library/BootLib/Decompress.c`、`Library/BootLib/PartitionTableUpdate.c`）。
- raphael 实机日志与 dtbo 清零 workaround：`oosexgang/hakios-xnu-kernel` issue #26。
- SM8550 同代先例：`edk2-porting/edk2-msm`（`Silicon/platform.sh.inc` 打包脚本、`configs/devices/fuxi.conf` header v1、`Platform/Xiaomi/sm8550/FdtBlob_compat/fuxi.dtb` 完整 id）。
- 本机 id 数据：`out/socrates_dtbo.txt`（msm-id 0x25c/0x20000、board-id 0x10008、xiaomi,miboard-id 4）、`firmware/base_dtb/`（你们当前追加的 QCM 通用 DTB，board-id=0）、`out/boot.json` + `out/boot.img` 实测结构（gzip 3MB+192B shim、单追加 DTB 0x7152e 字节、BootShim "ARM\x64" 在 0x38）。
- `uefiplat.cfg` 内存布局：uefi.elf 内 FFS 提取（out/uefi.elf.report.txt 前期产物）。
