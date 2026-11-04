# K60 Pro (socrates) `fastboot boot` 不跳转问题 —— 社区调研报告

调研日期：2026-11-04。调研范围：本地仓库（UniXNU-sheng / UniXNU-vermeer / UniXNU-socrates / uefi-socrates / UniXNU 主仓及其 docs）、GitHub 社区仓（OddlyLabs/unixnu-fuxi、pubglite55/UniXNU-nuwa、matejkoo217 等）、Qualcomm ABL 源码（mu_qcommodulepkg 镜像）、unixnu.com 文档站、本机固件解包（OS3.0.304.0.WMKCNXM）。

---

## 0. 一句话结论

**容器参数没有问题**——我们的 boot.img 头部与 sheng 真机验证过的逐字段一致。**最大嫌疑是追加 DTB 选错了块**：我们从 vendor_boot 提取的是 "Kalama **QCM** SoC" 参考树（`qcom,msm-id = <604 0x20000>`，即 **QCM8550 计算模块**），而 K60 Pro 的 SoC 是 SM8550（chip id **519 = 0x207**），ABL 按 msm-id 强制匹配 DTB，不匹配即放弃引导、退回 fastboot——与"OKAY 之后关屏、不跳转、fastboot 一直在线"的症状完全吻合。vermeer（K70，同 SoC）真机成功的镜像追加的正是 vendor_boot 里的 "Kalama **v2** SoC" 块（`msm-id = <519 0x20000>`）。**次强嫌疑是 header v0 被本机 ABL 静默拒绝**——nuwa（小米13 Pro，SM8550）有完全相同症状的实测记录，v0/v1 都"停在 fastboot 黑屏"，换 v3 后进 UEFI。

---

## 1. sheng 真机成功的 boot.img 完整参数集（与我们的逐项 diff）

### 1.1 参数来源链

- 容器参数：`uefi-socrates/Resources/Configs/sheng.toml`（与 `socrates.toml`、`vermeer.toml` **逐字节一致**，已 diff 验证）：
  ```toml
  [boot_shim]      requires_kernel_header = true
  [uefi_fd]        base = 0xA7100000, size = 0x300000
  [boot_image_kernel] kernel_compression = "gzip", append_dtb = true
  [boot_image]     header_version = 0, base = 0x00000000,
                   kernel_offset = 0x00008000, tags_offset = 0x01e00000, pagesize = 4096
  ```
- 打包逻辑：`UniXNU/scripts/unixnu/bootimg.py`（mkbootimg.py 取自 Mu-Silicium checkout；其余字段全为 mkbootimg 默认）。
- sheng 真机证据：`UniXNU-sheng/porting.toml` 多条 `kind = "device"` 记录，命令均为
  `fastboot boot boot.img`（Wi-Fi/音频/电源等全在 OS3.0.305.0.WNXMIXM 真机跑通），2026-11 仍在更新。

### 1.2 逐项 diff 表

| 项 | sheng（真机 OK） | 我们 socrates（不跳转） | 判定 |
| --- | --- | --- | --- |
| header_version | 0 | 0（实测 out/boot.img offset 40 = 0） | 一致 |
| magic / page_size | ANDROID! / 4096 | ANDROID! / 4096 | 一致 |
| kernel_addr | 0x8000 | 0x8000 | 一致 |
| ramdisk_addr | 0x1000000（mkbootimg 默认） | 0x1000000 | 一致 |
| tags_addr | 0x1e00000 | 0x1e00000 | 一致 |
| second_size / name / cmdline / os_version | 0 / 空 / 空 / 0 | 0 / 空 / 空 / 0 | 一致 |
| kernel 载荷 | gzip(BootShim+FD)+追加 DTB | 同左（gzip 头 1f8b，解压 3,145,920B = shim 192 + FD 0x300000） | 一致 |
| BootShim ARM64 header | offset 8 text_offset=FD_BASE(0xA7100000)，offset 16 image_size=shim+FD，offset 56 "ARM\x64" | 同左（192 字节 shim，bootimg.py 组装时已自校验） | 一致 |
| FD | shengPkg，3 MiB，FD_BASE 0xA7100000 | socratesPkg，3 MiB（fd_sha256 12efff5b…） | **内容不同**（板级预期差异） |
| **追加 DTB** | `build/sheng/sheng.dtb`：由 **Linux DTS** `ianchb/sm8550-mainline@42f3b40` 的 `sm8550-xiaomi-sheng.dts` 编译，根属性 **`qcom,msm-id = <536 0x20000>`（SM8550P v2.0）、`qcom,board-id = <0x10008 0>`**，再注入 splash 节点 | `scripts/data/socrates.dtb`：stock vendor_boot 的 "**Kalama QCM SoC**" 块，根属性 **`qcom,msm-id = <604 0x20000>`（QCM8550）、`qcom,board-id = <0 0>`**，注入 splash 节点 | **msm-id 不匹配本机 SoC（604≠519）—— 主嫌疑** |
| splash 节点 | `/reserved-memory/splash_region`，label `cont_splash_region`，reg `<0 0xb8000000 0 0x2b00000>`（sheng-abl-dtb.py 注入） | 同左（board.toml `[[bootimg.dtb_node]]` 注入，实测已在 DTB 内） | 一致 |
| ramdisk | 真机长期测试的 boot.img 含 176 MiB payload 卷（boot.img 总 185,733,120 B）；最早真机 fixture（package-sheng-boot.py）为**空 ramdisk** | 64 MiB payload 卷（ramdisk_size 0x4000000） | 大小不同，但 sheng 两种都真机可跳转 → 非阻断项 |

> 追加 DTB 是唯一一处"每块真机验证过的板子都做对了、而我们做错了"的差异。三块成功板子的追加 DTB 携带的 msm-id 都等于本机 SoC 的 chip id：vermeer/fuxi 用 519（SM8550），sheng 用 536（SM8550P）。

### 1.3 vermeer（K70，同 SoC，真机成功）的 DTB 是怎么选的

`UniXNU-vermeer/scripts/data/vermeer.dtb`（510,596 B）根属性实测：model "**Qualcomm Technologies, Inc. Kalama v2 SoC**"，`qcom,msm-id = <519 0x20000>`，`qcom,board-id = <0 0>`——即 vendor_boot 里的 **Kalama v2 块**，加上同款 splash 注入。CI（`build-kernel.yml` / `bootimg-only.yml`）用 `--dtb scripts/data/vermeer.dtb` 打包，真机进 UEFI 菜单（PORTING-VERMEER §1）。

---

## 2. 社区已知"fastboot boot 不跳转/黑屏"案例与解法

### 2.1 nuwa（小米13 Pro，SM8550）——与我们症状相同的实测记录 ⭐

`pubglite55/UniXNU-nuwa` `board.toml` [bootimg.image] 注释（原话）：

> 实测结论：v1（Mu 的 nuwa.toml 值）和 v0（sheng 的值）都被 nuwa 的 ABL 拒绝 —— **设备停在 fastboot、黑屏**；换成 **v3** 后设备离开 fastboot 并进入 UEFI（与官方 Mu-qrd8550.img 的表现一致）。所以 nuwa 要 v3。

- 该机为 GKI/Android 17 固件；v3 成功后全链到 DarwinBoot 交接（UniXNU/UniXNU issue #55：ABL → BootShim → UEFI → UniXNU 菜单 → DarwinBoot 绿条 → 内核入口）。
- 它的追加 DTB 用 sheng 同款 `fetch-sheng-dts.py`（ianchb Linux DTS 编译）+ splash 注入。
- 结论：**"OKAY 后停在 fastbot/黑屏"在 SM8550 系上有被 ABL 静默拒绝 header v0 的先例，解法是 v3**。注意 nuwa 换 v3 时 DTB 未变，说明其失败点在 header 处理而非 DTB——两块板失败原因可以不同，我们两条都要试。

### 2.2 vermeer（K70，SM8550）——真机成功路径

- v0 + "Kalama v2" DTB（见 §1.3）。文档另记录两类失败模式可供对照（`docs/userland-in-ram.md`）：
  - 传输中 `Device sent unknown status code` = 超下载上限/链路（65.5 MiB 过，193.5 MiB 被拒）——我们 68.6 MB 已拿到 OKAY，不属此类；
  - 传输成功但**落回菜单**、屏上有 `NO WINDOW … BIG RUN …` = 已进 UEFI、DarwinBoot 内存窗口问题（`owned_memory_size`）——如果我们到了这步，说明问题已变成 §2.5。

### 2.3 fuxi（小米13，SM8550，OS3.0.309）——最完整的真机证据链

`UniXNU/docs/devices/fuxi-oddlylabs.md`（OddlyLabs/unixnu-fuxi，2026-11-02 真机）：

- "the ABL accepts the **v0 image** (fastboot boot answers OKAY), the **DEBUG firmware log appears on the panel**…" —— OS3 固件 + v0 + `fastboot boot` 被证明可行；DEBUG 固件日志直接打在面板上，是判断"跳没跳"的最便宜观测手段。
- "**Measured on hardware in matejkoo217/uefi-fuxi**: with text offset 0 in the shim's ARM64 header the ABL loads the image and the firmware's DEBUG console prints on the panel; **with the firmware address there the ABL answers Load Error**." —— ARM64 header 的 text_offset 字段（我们沿用 sheng 布局 = FD_BASE）是 ABL 敏感参数；matejkoo 的变体上放 FD_BASE 会被拒（症状是 Load Error，与我们的 OKAY 不同，故我们不优先动它）。
- "The firmware's FdtBlob (sm8550-xiaomi-fuxi.dtb, **msm-id 0x207, board-id 0x10008**) carries **the root properties the ABL selects an appended DTB by**; the DTB merged from OS3.0.309 keeps the base DTB's board-id 0 and **is not used** for the boot image." —— 明确说 ABL 按根属性选择追加 DTB，且成功配方刻意带正确 msm-id/board-id。
- 另有 `fuxi-kkkpc.md`：为 fuxi 重打 **v3** + `--os_version 17.0.0 --os_patch_level 2026-07`（当时真机测试 pending）——os_version 不是必需（sheng/fuxi 的 v0 真机镜像 os_version=0）。

### 2.4 sheng（小米平板6S Pro，SM8550P，OS3.0.305）——参考板真机记录

- `package-sheng-boot.py`（真机 fixture）：空 ramdisk；QEMU 先过 shim 拷贝/原地两种场景；打包后逐字节回读校验；report 明确 `bootloader_acceptance_proven: false`，真机验收由 `fastboot boot` 记录完成。
- `sheng-abl-dtb.py` 注释：**stock ABL 的 UpdateSplashMemInfo 在 DTB 无 `/reserved-memory/splash_region` 时会关掉面板和显示控制器** —— "关屏"症状的另一来源（我们的 DTB 已注入 splash，应无此问题）。
- porting.toml 多条 device 记录证明 v0 + 176 MiB ramdisk 的 boot.img 可在 OS3.0.305 真机反复 `fastboot boot`。

### 2.5 其它相关记录（对照表）

| 板 | 现象 | 结论/解法 | 出处 |
| --- | --- | --- | --- |
| asteroids（Nothing Phone 3a） | 所有镜像首启一律 `Load Error` | **slot a retry count 耗尽**（我们的引导从不标记 successful）：`fastboot set_active a` 重置（retry 7）后恢复 | UniXNU docs/devices/asteroids.md T86d |
| vermeer 大镜像 | 传输中 `Device sent unknown status code` | 超过 `fastboot getvar max-download-size` 或链路抖动 | UniXNU-vermeer/docs/userland-in-ram.md |
| vermeer 固件 | 屏幕停在 `ASSERT [ArmCpuDxe](0==1)` | 固件断言死循环（FD 内因），先把小包跑通 | 同上 + board.toml [payload] 注释 |
| nuwa（GKI） | "ABL never loads the boot_a ramdisk"，initrd 指向内核预留区 | ramdisk 是否被 ABL 搬运因机而异，不能假设 | UniXNU/UniXNU issue #55 |
| 官方 Mu-Silicium | qrd8550 参考镜像 `header_version = 3` | SM8550 类 ABL 的"官方可用"容器是 v3 | uefi-socrates/Resources/Configs/qrd8550.toml |

### 2.6 Qualcomm ABL 源码层面的机制（解释症状与差异）

来源：`Daniel224455/mu_qcommodulepkg`（Qualcomm ABL 的公开镜像，QcomModulePkg）。

1. `FastbootCmds.c: CmdBoot()`：`LoadImageAndAuth` 失败 → 回 `"Failed to load/authenticate boot image: %r"`（**解释了我们喂 stock v4 时得到的 "Load Error"**——v4 单独 fastboot boot 缺 vendor_boot/dtbo，正常被拒，不是安全锁）。通过后 **先 `FastbootOkay("")`、停 USB，再 `BootLinux()`**；`BootLinux()` 任何一步失败会返回 → ABL 留在/回到 fastboot。**我们的症状 = OKAY 已回、BootLinux 中途失败返回**。
2. `LocateDeviceTree.c: GetPlatformMatchDtb()`：`(BoardPlatformRawChipId() & 0xffff) == (DTB qcom,msm-id & 0xffff)` 为**硬性条件**，不等即 `NONE_MATCH` 拒绝该 DTB；board-id 的 variant_id==0 是**通配符**（vermeer 用 board-id 0 成功即因此）；subtype 0、foundry 0 也都按默认匹配放行；soc_rev 只影响排序。→ **msm-id 是唯一必须精确的项**。
3. `BootLinux.c: DTBImgCheckAndAppendDT()`：dtbo 可加载时走 `DeviceTreeAppended()`（对追加 DTB 逐块做上述匹配），dtbo 不可用时走 `GetSocDtb()`（同样强制匹配、无单块回退）。上游代码里 `DeviceTreeAppended` 失败后还有一段"Single appended DTB found"的兜底（直接照抄不匹配的单块 DTB），**但小米 OS3 ABL 可能有裁剪**，且该兜底路径的前提是 fdt 恰好单块、后续 fdt_check_header 恰好失败——不能指望它。
4. `UpdateBootParams()`：现代 ABL 的 kernel/ramdisk/DT 装载地址来自 UEFI 变量（KernelBaseAddr 0xA8000000 等），**header 里的 kernel_addr/tags_addr/ramdisk_addr 基本被忽略**；所以 v0 头里的地址字段本就不是成败点。
5. `UpdateSplashMemInfo`：无 splash 节点 → 关屏（见 §2.4）。

---

## 3. 按证据强度排序的下一步实验

### 实验 1（首推）：把追加 DTB 换成 vendor_boot 的 "Kalama v2" 块，其余全部不动

- **做什么**：从本机固件 `firmware/extracted/.../images/vendor_boot.img` 偏移 **0x1e256b3**、长度 **0x7ca84**（511,620 B）取出 "Kalama v2 SoC" DTB（model `Qualcomm Technologies, Inc. Kalama v2 SoC`，`qcom,msm-id = <519 0x20000>`，`qcom,board-id = <0 0>`，reserved-memory 222 子节点与 QCM 块相同结构、均无 splash 需注入），用与现 `socrates.dtb` 相同的 `patch_dtb` 流程注入 `/reserved-memory/splash_region`（label `cont_splash_region`，reg `<0 0xb8000000 0 0x2b00000>`），再以同样的 `--dtb` 传入重打 v0 镜像（ramdisk 64 MiB 先保持不变，控制单变量）。
- **依据**：(a) ABL 源码 msm-id 掩码匹配为硬性条件（§2.6-2），QCM8550(604)≠SM8550(519) 必拒；(b) vermeer（K70，同一颗 SM8550、同为手机 ABL）真机成功用的正是这一块（§1.3）；(c) fuxi 真机记录明说 ABL 按 msm-id/board-id 选追加 DTB（§2.3）；(d) sheng 用 0x218（SM8550P）同理成立；(e) 失败机制与症状吻合（§2.6-1）。
- **注意**：vendor_boot 里共有 **8 块**参考 DTB（PORTING-SOCRATES 写的"两块"是错的），逐块 msm-id 见附录 A；其中 SM8550 对应 v1(0x10000)/v2(0x20000) 两块，选 v2。

### 实验 2：若实验 1 无效 → 重打 header v3

- **做什么**：socrates `board.toml` 加 `[bootimg.image] header_version = 3`（base/kernel_offset/tags_offset/pagesize 保留，v3 下被忽略），当前 `UniXNU/scripts/unixnu/bootimg.py` 的 `verify()` 已支持 v3/v4 布局，直接可用。
- **依据**：nuwa 同 SoC 家族、**同症状**（"停在 fastboot、黑屏"）的实测修复（§2.1）；官方 qrd8550 参考镜像也是 v3；fuxi-kkkpc 也为 fuxi 备了 v3 配方。
- **提示**：v3 没有 name/cmdline 字段（本来为空，无损）；os_version 可留 0（sheng/fuxi 真机 v0 均 0），如想对齐 nuwa/fuxi-kkkpc 可加 `--os_version`。

### 实验 3：空 ramdisk 对照（与实验 1 叠加或单独）

- **做什么**：用修正后的 DTB 重打 `boot-minimal`（`out/boot-minimal.img` 已存在同款 kernel+DTB、ramdisk_size=0 的版本，只需换 DTB）。等价于 unixnu.com bring-up Stage 2 的官方最小化测试：`./unixnu bootimg --dtb <new.dtb> --ramdisk none`。
- **依据**：`unixnu.com/porting/bring-up` Stage 2 明确"Minimal test: an empty ramdisk"；sheng 最早的真机 fixture 也是空 ramdisk（§2.4）；排除 64 MiB ramdisk 搬运/重叠变量。sheng 后期 176 MiB ramdisk 也真机可跳，故排为对照而非主修复。

### 实验 4：DEBUG 固件构建（观测手段，随实验 1/2 一起上）

- **做什么**：用 `--target DEBUG` 重出 FD 打进镜像（fuxi-oddlylabs 的 DEBUG 固件把 SEC 起始的日志直接画在面板上）。
- **依据**：fuxi-oddlylabs 真机记录（§2.3）——"the DEBUG firmware log appears on the panel"。一旦 ABL 真的跳转，屏幕立即可见；若依旧全黑则证明控制权没离开 ABL，实验 2 优先级立即提升。

### 实验 5（保险叠加项，可与实验 1 同时做）

- 在替换的 DTB 根上补 `qcom,board-id = <0x10008 0>`（socrates dtbo entry 50 与 fuxi/sheng 的取值；ABL 源码中 0 是通配符所以纯保险），或把 **v2 + QCM + SG 等多块 DTB 直接拼接**追加（ABL 的 DeviceTreeAppended/GetSocDtb 都会迭代多块取最优匹配）。
- **依据**：ABL 匹配循环（§2.6-2/3）；多块拼接是 community 中处理 id 不确定性的常规手段。

### 实验 6（环境项，随手查）

- 上机时确认 `fastboot getvar current-slot` 与 slot retry 计数；必要时 `fastboot set_active a`（asteroids 案例：slot unbootable 会让一切镜像报 Load Error，§2.5）。我们已拿到 OKAY，此项不是主因，但便宜。

### 实验 7（仓库勘误，不改引导但防后人踩坑）

- `UniXNU-socrates/scripts/data/README.md` 称 socrates.dtb 的 `qcom,board-id = 00010008` —— 实测该文件 board-id 为 `<0 0>`（0x10008 是 dtbo entry 50 的值，被张冠李戴）；`PORTING-SOCRATES.md` §3.3 称 vendor_boot 有"两块 dtb"——实测 **8 块**。建议在下次提交时修正，并注明 socrates.dtb 为 QCM8550 参考树（芯片 id 604），与手机 SoC（SM8550/519）不符。

---

## 附录 A：socrates OS3.0.304 vendor_boot 中的全部 DTB 块（自 `images/vendor_boot.img` 扫描）

| 偏移 | 大小 | model | qcom,msm-id | 说明 |
| --- | --- | --- | --- | --- |
| 0x1d47000 | 0x714da | Kalama QCM SoC | `<604 0x20000>` | **当前 socrates.dtb 的来源（QCM8550）** |
| 0x1db84da | 0x6d1d9 | Kalama SG SoC | `<600 0x20000>` | |
| **0x1e256b3** | **0x7ca84** | **Kalama v2 SoC** | **`<519 0x20000>`** | **SM8550 v2 —— 应使用（vermeer 真机同款）** |
| 0x1ea2137 | 0x8128e | Kalama SoC | `<519 0x10000>` | SM8550 v1 |
| 0x1f233c5 | 0x705c3 | KalamaP QCS SoC | `<603 0x20000>` | |
| 0x1f93988 | 0x6c2c2 | KalamaP SG SoC | `<601 0x20000>` | 提取脚本曾误当作"第二块" |
| 0x1fffc4a | 0x7bb6d | KalamaP v2 SoC | `<536 0x20000>` | SM8550P v2（sheng 的 SoC id） |
| 0x207b7b7 | 0x80094 | KalamaP SoC | `<536 0x10000>` | SM8550P v1 |

id 对照：`include/dt-bindings/arm/qcom,ids.h`：**519 = SM8550**、**604 = QCM8550**（iot/计算模块）、536 = SM8550P。所有块 `qcom,board-id = <0 0>`、`reserved-memory` 结构一致（222 子节点）、均无 splash（需注入）。

## 附录 B：证据文件索引（本地绝对路径）

- 配置对比：`D:\gittest\unixnu-work\uefi-socrates\Resources\Configs\{sheng,socrates,vermeer,nuwa,qrd8550}.toml`（socrates/sheng/vermeer 三者逐字节一致）
- 打包器：`D:\gittest\unixnu-work\UniXNU\scripts\unixnu\bootimg.py`；真机 fixture：`D:\gittest\unixnu-work\UniXNU-socrates\scripts\package-sheng-boot.py`、`sheng-abl-dtb.py`
- 我们失败的镜像与头部实测：`D:\gittest\unixnu-work\out\boot.img` / `boot.json` / `boot-minimal.img`（头部字段 dump 见本报告 §1.2）
- 错误来源 DTB：`D:\gittest\unixnu-work\UniXNU-socrates\scripts\data\socrates.dtb`（= vendor_boot 0x1d47000 QCM 块 + splash）
- vermeer 真机 DTB：`D:\gittest\unixnu-work\UniXNU-vermeer\scripts\data\vermeer.dtb`（Kalama v2）
- sheng Linux DTS：`ianchb/sm8550-mainline@42f3b40c…/sm8550-xiaomi-sheng.dts`（`qcom,msm-id = <536 0x20000>; qcom,board-id = <0x10008 0>`）
- ABL 源码（镜像）：github.com/Daniel224455/mu_qcommodulepkg —— `BootLinux.c`（CmdBoot→BootLinux 序列、DTBImgCheckAndAppendDT、UpdateBootParams）、`LocateDeviceTree.c`（GetPlatformMatchDtb/GetBoardMatchDtb/DeviceTreeAppended）、`FastbootCmds.c`（CmdBoot 的 OKAY 时序与 "Failed to load/authenticate" 字样）
- 社区真机记录：`D:\gittest\unixnu-work\UniXNU\docs\devices\fuxi-oddlylabs.md`、`ishtar.md`、`asteroids.md`、`fuxi-kkkpc.md`；`D:\gittest\unixnu-work\UniXNU-vermeer\docs\{userland-in-ram,dual-boot,flash-checklist}.md`、`PORTING-VERMEER.md`；`D:\gittest\unixnu-work\UniXNU-socrates\PORTING-SOCRATES.md`、`docs\flash-checklist.md`；`pubglite55/UniXNU-nuwa` `board.toml`（v0/v1 被拒、v3 成功的实测注释）；UniXNU/UniXNU issue #55（nuwa 真机报告）
- 文档站：unixnu.com/porting/bring-up（Stage 1/2 判据、空 ramdisk 最小测试）、/porting/packaging（package 步骤与 [bootimg] 接口）
