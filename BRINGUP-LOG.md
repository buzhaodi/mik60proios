# BRINGUP-LOG — socrates (Redmi K60 Pro) XNU 移植调试战记

记录本移植每个关卡的根因、真机证据与修复。目的：让下一个移植别的机型的人不用再踩一遍。

调试通道说明：本机**没有串口驱动**（socrates.dsc 未接任何 SerialPortLib），
所有内核日志只能靠屏幕（录像 → 逐帧转录）。`patch-xnu-entry-probe.py`
在内核入口/MMU 开启点打了三色进度条作为唯一实时遥测。

---

## 1. fastboot boot 静默不跳转

**症状**：`fastboot boot` 回 OKAY，屏幕黑，fastboot 仍在线——我们的代码一个字节没执行。

**排查**：ABL（Qualcomm 引导器）源码级分析（`docs/abl-analysis.md`）：
- OKAY 只代表 header 校验过，之后 `BootLinux()` 的任何失败都**静默 return** 回 fastboot；
- DTB 选择条件是 `(chip_id & 0xffff) == (dtb msm-id & 0xffff)` 硬匹配；
- 单块 "Kalama QCM" DTB 的 msm-id（0x25C）不匹配本机芯片批次。

**修复**：把 vendor_boot 里的**全部 8 块 DTB** 按原厂顺序追加（0x25c/0x258/0x207/0x25b/0x259/0x218），
ABL 自己挑块 → 2 秒内 USB 离线 = 真跳转。

**工程坑**：fdtput 只重写拼接 blob 的**第一块**（会把表截断！）——splash/守卫节点用
`tools/inject-nodes.sh` 离线注入**每一块**。

---

## 2. DXE 阶段 ASSERT，FAR=0xD8000000，三次逐字节复现

**症状**：`ASSERT [ArmCpuDxe] CpuExceptionHandlerLib.c(438)`，寄存器转储 FAR=0xD8000000、
ESR=0x96000010（same-EL data abort，ISS 0x10 同步外部中止）。

**三次错误归因（都错）**：
1. "DT 保留洞被当成了可分配内存"——修了内存图，无效；
2. "SocratesBootMemoryDxe 按 ABL 的 DT 把洞加成内存"——注入了 DT 守卫节点，无效；
3. **录像破案**：开机录像拍到了 `Loading driver at 0x...` + 寄存器转储同屏 →
   用 Build 目录的模块 map 把 ELR=+0x2FBC 定位到 `QcomPkg/Drivers/IortDtDxe`（IORT **DT** Dxe）。

**真根因**：IortDtDxe 按名字查 "XBL DT" 区域（`LocateMemoryRegionByName`，stock cfg 名字是 ABI），
生成器把 0x81A00000 命名成了 DT 节点名 `xbl_dt_log@81a00000` → 查不到 →
**`XblDtRegion` 保持未初始化栈垃圾**（恰好 = 0xD8000000，是前驱驱动 Ranges 数组残留的
mpss_dsm 终点，每次启动都一样）→ 逐 4 字节扫 FDT magic → 第一笔读取踩 XPU 保护 → 同步外部中止。

**修复**（三件）：
- 内存图生成器 **stock 名优先**（`stock name if covered else DT 节点名`）；
- `IortDtDxe.c` 的 `XblDtRegion = {0}` 零初始化；
- 顺带把 82 描述符里 8 个 XPU 保护洞从 "DRAM gap 填 Conv（可分配 write-back）" 改为 Reserv
  （含 0x82800000 的 70MB TZ 核心区、0xD8000000 实证洞、0xDFC00000 的所有 DRAM bank 之外区）。

**教训**：
- 同源内核（好/坏）先做**逐字节对比**再下结论——我们两个无桥内核可执行码全同（88 字节差异全在元数据），却一度被当成"重链坏了"；
- pre-console 窗口（bsd_bufferinit 之后、IOKitBSDInit 之前）的 panic **画不出来**（vinfo 未初始化，画成"花纹"）——bisect-by-paint 在那个窗口无效。

---

## 3. AMFI: No PMGR? @ConfigurationSettings.cpp:235

**机制**（社区记录已钉死）：未改动的 AMFI 经
`IOService::serviceMatching("ApplePMGRNub") + waitForMatchingService` 等 nub，
读 `nub+0x88` 的 provider 调 readAon/writeAon（OR bit 2）。
**provider 为 NULL 时 nub 返回 0 / no-op——发布"真类、空 provider"的 ApplePMGRNub 即可满足锁存**
（sirius-yooglery 的关键发现）。`amfi_get_out_of_my_way=1` 跳不过。

**桥的实现**（`package/ShengPlatformPower.cpp`，vermeer→sheng 血统）：
`CONFIG_XNU_SHENG_PMGR=y` + `sheng-pmgr=2`，从 `sheng_pmgr_run`（bsd_init 钩子）发布。
340 槽 vtable 全部由 `scripts/build-sheng-platform-power.py` 对着**原始 kernelcache** 逐槽审计
（AMFI 指令契约 + ApplePMGR 340 槽 + T8011 参照，`scripts/audit-amfi-pmgr-contract.py` 全 PASS）。

**踩坑记录（每条都是一轮真机白测）**：
- `defconfig` 的 `CONFIG_XNU_*` 是被 `unixnu defconfig` **解析进 `out/<device>/.config`** 的——只改 defconfig 文件不生效（第一次编出的内核根本没编进桥，靠符号校验 `strings kernel.macho | grep sheng_pmgr` 发现）；
- payload 构建需要 `--unique-chip-id`（占位种子）；
- 清洁检出没有 sheng 要求的 `native-owner-ufs-*-candidate.macho`——用**自己树里编出的 kernel.macho + kernel.json** 具现为候选参照（同一 kernelcache、同一 slide、同一 ApplePMGR 类）；
- `llvm-objcopy` 不支持 Mach-O——它做的两件事（清空 `__DATA,__mod_init_func`、
  全局化初始化符号）改为 Python 直接做 Mach-O 结构体手术（section_64: size@+40、reloff/nreloc@+56 清零；nlist_64 n_type@+4 |= N_EXT）；
- 树的 `.cache` 是指向设备仓的 symlink——相对路径符号链接会解析到错误位置，**必须绝对路径**；
- sheng 的 `OSKextLoadKextWithIdentifier("com.apple.driver.ApplePMGR")` 对我们**多余且硬崩**
  （ApplePMGR 在本板 prelink roots 里、类启动时已注册；sheng 的 roots 没有它所以需要加载）；
- **致命坑：调用点**。sheng 补丁把 `sheng_pmgr_run()` 放在 `bsd_bufferinit()` 之后——
  距离 `IOKitBSDInit()` 还有 500+ 行，**IORegistry 的 platform 还不存在、console 还没接上**。
  在那里跑桥 = 硬崩且 panic 画成"花纹"。修复：构建脚本里加 `PMGR_MOVE` 块，把调用块
  挪到 `IOKitBSDInit()` 紧前（console 已接 panic 可读、registry ready、nub 在 AMFI 的匹配开始前注册）。

**结果**：`AMFI: No PMGR?` 消失，内核一路跑到：

```
Failed to mount root device @IOKitBSDInit.cpp:984
```

——fuxi 先例预言的**无存储阶段预期终点**。至此 iOS 内核完整引导链在本机活了。

---

## 4. 两大"假象"（浪费轮次最多的两个）

### 4.1 崩溃污染态
内核崩溃复位后，ABL/PMIC 留下污染态——之后**任何**镜像（含已知良好镜像）都在入口静默复位。
进一次 Android 清态后同一镜像立刻正常。**协议：每次 fastboot boot 前先进一次 Android。**

### 4.2 参数行不可裁
为了"隔离变量"做过 kernel_args 最小化实验——结果每种裁剪组合都"花纹复位"，误导排查方向一整晚。
事实：完整行里的开关（`sheng-touch=0`、`offline-legacy-gop=1`、`sheng-disable-watchdogd=1`……）
是必需品；去掉任何一个，内核的默认路径就会去碰没有驱动支撑的真硬件。
**协议：kernel_args 逐字保留；要隔离变量，用 `sheng-pmgr=0/2` 这种显式开关。**

---

## 5. 屏幕遥测的判读基线

| 现象 | 含义 |
| --- | --- |
| 绿条 | DarwinBoot handoff 标记（loader 画的） |
| 绿 + 蓝条 | 内核入口探针（stage 1，MMU off）执行了 |
| + 红紫条 | MMU 开启探针（stage 2）执行了 |
| 蓝条后无任何输出且复位 | 内核在早期死掉（无 panic 屏） |
| "花纹"（彩色横纹覆盖屏幕）后复位 | pre-console 窗口的 panic 尝试绘制（vinfo 未初始化）——崩溃在 IOKit 初始化之前，或 panic 路径本身崩了 |
| 干净 panic 文字 | 崩溃在 console 接上之后——文字本身就是最好的线索 |
| `Failed to mount root device` 定住 | 无存储阶段预期终点，通关 |

## 6. 复现战果的镜像

`prebuilt/boot-pmgrlate-boot.img`（72 MB，v0，内核 sha `de368b67...`）：
```
fastboot boot boot-pmgrlate-boot.img    # 前置：先进一次 Android！
```
