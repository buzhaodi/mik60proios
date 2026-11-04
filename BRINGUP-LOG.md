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

`prebuilt/boot-pmgrlate-boot.img`（72 MB，v0，boot.json `kernel_sha256 e5909857...`，卷内内核为当时构建的探针版）：
```
fastboot boot boot-pmgrlate-boot.img    # 前置：先进一次 Android！
```

`prebuilt/boot-userland-boot.img`（72 MB，v0，2026-11-05，首个 EL0 里程碑）：FD/DTB/内核段与上机验证过的
boot-pmgrlate **逐字节同 sha**，只有 payload 卷换了——多一个 `Payloads/userland.img`（N4KROOT 容器，内含
ad-hoc 签名的静态 `launchd.macho`，cdhash `d9ea65f7...`）和它自己的信任缓存，菜单多出 `userland`（默认）
与 `userland-full` 两条目。
```
fastboot boot boot-userland-boot.img    # 前置：先进一次 Android！
```

---

## 7. RAM root → 首个 EL0 进程：整条链路都是现成的，缺的只有 CLI 一个参数

### 7.1 内核侧零改动（取证）

- 现役内核（`out/socrates/kernel/kernel.macho`，源 sha `668c0eb5...`）**早就编进了 mockfs + N4KROOT**：
  二进制里有 `N4KROOT` magic、`mockfs_mountroot`、`mockfs_readonly_open`（test-file 补丁独有）、
  `failed to destroy test node`（同上）、`load_init_program`。机制：`build-xnu-4k-baseline.sh:51` 把
  `patches/xnu/*.patch` 整个 glob 进 `.cache/xnu-work`，`build-mockfs-fixture.py` 从打过补丁的源码编出
  fixture 并 `force_load`（`CONFIG_XNU_SOURCE_MOCKFS=y`）。
- **诚实记录一条谱系**：上机验证"Failed to mount root"的镜像（11-04 22:35 打包）用的 payload 内核是
  `d16b0027...`；WSL 树里的内核是 23:32 串口阶段顺手做的一次**增量重编**（源状态、板仓内容、工具链相同，
  字节不同）。本里程碑镜像采用现树内核。两个内核做了逐项符号取证（mockfs/N4KROOT/test-file/PMGR 桥/
  齿轮素材/探针三色条/panic 屏）**全部一致**；且探针补丁被证明是确定性的——同一 kernel.macho 两次
  payload 构建打出同一个 `payload_kernel_sha256 86574694...`。风险定性：同源重编的字节漂移，非功能变更。

### 7.2 唯一的缺口：`build payload --userland` 不在上游 CLI

上游 main（c1ecc5b）的 `scripts/unixnu/{cli,payload}.py` 没有 userland 支持；它在 vermeer 移植者的 fork
（`yyx2025/UniXNU@vermeer-fix`，board 仓 userland.yml 里 pin 的就是它）。但 fork 基于老得多的上游（没有
schema-2/release 那批），**不能整分支拉**——那会污染已经真机验证过的内核构建。做法：读 fork 的两个文件，
把 userland 的 hunk 移植到我们的检出上（cli.py +2 行；payload.py 五处：userland 校验、staging、ADT
`--ramdisk`、菜单条目 userland/userland-full/默认项、size_mib_userland、报告字段）。
补丁固化：`tools/unixnu-userland-payload.patch` + `tools/apply-unixnu-userland-patch.sh`（幂等），
Windows 与 WSL 两个 UniXNU 检出都应用。

下游链路一行没改、全部现成：UniXNULib 的条目 `initrd` 字段（Config.c）→ DarwinBoot 校验/拷贝 ramdisk 并
把物理区间写进 ADT 占位符（DarwinBoot.c）→ `IOKitBSDInit` 发 `/dev/md0` → `rd=md0` → `vfs_mountroot`
里 mockfs 挂载 → `load_init_program()` exec `/sbin/launchd`。

### 7.3 两个非显然的坑

1. **FD 是串口版**：`uefi-socrates/Build/` 里的产物是串口构建留下的（sha `25ca7734...` == prebuilt-test
   `boot-serial.img` 的 `fd_sha256`；dsc 标志早已改回 0 但 Build 没重跑）。直接打包会把没上机验证过的串口
   固件带进里程碑镜像。修法：从 `prebuilt/boot-pmgrlate-boot.img` 的内核段（gzip）里**原样解出**上机
   验证过的 FD（192 字节 BootShim 后 3,145,728 字节，sha `a3741876...` 逐字节比对通过）用 `--fd` 传给
   bootimg。效果：新镜像的内核段/FD/DTB 与上机镜像逐字节同 sha——**变量只剩 payload 卷本身**。
2. **ADT 每次构建都不同**：`make-socrates-adt.py` 往 `/chosen` 写 `random-seed = os.urandom(64)`——
   所以 `payload_sha256`/`adt_sha256` 每次构建必然不同，这是熵，不是构建漂移。结构验证改用重放对比：
   同参数带/不带 `--ramdisk` 各构建一次 ADT，差异恰好是 `RAMDisk` 属性（+52 字节）；卷内 ADT 与重放件
   逐字节 diff 只有那 64 字节随机种子。

### 7.4 `-progress`（"苹果启动画面"能做到的极限）

XNU 在 iOS 系目标默认 `show_progress = FALSE`（`pexpert/arm/pe_init.c:296-298`），`-progress` 引导参数
打开后 `PE_init_iokit` 用内核编译内置的 `gGearPict` 素材在屏中央转白色齿轮（素材在两个内核里都取证到）。
它只是画面、不影响引导逻辑；只加在默认 `userland` 条目的参数行里，真出问题去掉一个参数即可隔离。
SpringBoard 真桌面本阶段不可行（APFS 块设备/Apple 签名链/SEP keybag 全缺），userland README 自己就写明了。

### 7.5 主机侧验证链（全过）

| 检查 | 结果 |
| --- | --- |
| `userland/test-adhoc.py`（签名器自检 14 项） | all passed |
| `tools/verify-userland-artifacts.py`（容器头/Mach-O 静态无 dyld/签名/信任缓存==cdhash/类别字节/大小） | PASS |
| payload：unixnu.toml 默认=`userland`，args=`-v -progress serial=3 debug=0x14e kt_fixed_zones=120 sheng-pmgr=2 rd=md0` | ✓ |
| payload：卷内 4 个 Payloads 文件 + toml，内容 51.1 MiB / 64 MiB | ✓ |
| payload：`kernel_sha256 668c0eb5...` 未动、`payload_kernel_sha256 86574694...` 与上一构建一致 | ✓ |
| payload：ADT 含 `RAMDisk`+`TrustCache` 16 字节占位符（重放对比取证） | ✓ |
| boot.img：kernel 段 `e5909857...` / FD `a3741876...` / DTB `5c731bfe...` 与上机镜像逐字节同 | ✓ |
| boot.img：ramdisk 段 == payload.img（`709fddac...`），总 72,032,256 B | ✓ |

### 7.6 上机判读（做完实验回填本节）

- **通关标志**：`-v` 日志后出现 userland banner（双线框 + PID/UID + sysctl 探针 + 1 MiB 内存校验 +
  `/probe.bin` motd）+ 心跳 tick。这就是"内核把 PID 1 拉起来、AMFI 放行、mockfs 根成立"的四合一证据。
- 回到菜单 = 窗口/参数问题（屏上找 `NO WINDOW`）；停在 `Failed to mount root device` = `rd=md0`
  没吃进去（查 ADT RAMDisk 占位符被 loader 填了没有）；panic 文字 = 直接线索；"花纹" = pre-console panic。
- 菜单里 `userland-full` 是**已知会 ASSERT 的对照项**（完整探针行撞 same-EL data abort，见 board.toml
  注释）——不要拿它做首测；`xnu` 条目是上一里程碑的一键复现。
