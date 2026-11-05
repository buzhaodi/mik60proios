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

> **2026-11-05 起镜像二进制不再入库**（仓库体积政策，`.gitignore` 已加 `*.img`）：`prebuilt*/` 里只保留
> `.json` 清单作为上机记录（内核/ramdisk/FD/DTB 各段 sha、大小、`hardware_tested` 标志）。要拿可刷写的
> 镜像请按 `README` §完整复现 或 `repro/build-userland-boot.sh` 自行构建。git 历史里的旧 img 不追删；
> 如需彻底瘦身历史（filter-repo 重写）属于破坏性操作，由仓库所有者自行决定。

`boot-pmgrlate-boot.json`（上机验证到 `Failed to mount root device` 的那一版）：FD `a3741876...`、
DTB `5c731bfe...`、boot 镜像内核段 `e5909857...`。

`boot-userland-boot.json`（首个 EL0 里程碑初版，见 §8 的失败与修复记录）。

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

---

## 8. 首个 EL0 攻坚战（2026-11-05，7 轮真机判别）——交接记录

> 本节是完整战况记录与交接文档。所有判别镜像的 .img 已按仓库政策删除，`.json` 清单留在 `prebuilt-test/`。

### 8.1 七轮判别地图

| # | 镜像 | 问的问题 | 真机结果 | 结论 |
| --- | --- | --- | --- | --- |
 | 1 | `boot-userland-boot.img`（20b8a3e，proven FD） | 里程碑镜像能过吗 | 绿条后复位，无蓝条 | 失败基线确立 |
 | 2 | `boot-pmgrlate-boot.img`（proven） | 手机态干净吗 | ✅ 停在 `Failed to mount root device` | 状态干净 |
 | 3 | `boot-kcheck-console.img`（同内核 86574694、无 userland、全参数） | 重编内核有毒吗 | ✅ 同上 | **内核重编嫌疑洗清** |
 | 4 | `boot-userland-fullargs.img`（userland+全参数行） | 最小参数行的锅吗 | ✗ 同 #1 死法 | **参数行嫌疑洗清** |
 | 5 | `boot-v2-trustcache.img`（只带 56B 信任缓存） | ramdisk 还是信任缓存 | ✗ 复位 | **多读任何一个文件即触发** |
 | 6 | `boot-diag-trustcache.img` / `boot-diag-userland.img`（诊断 FD：Entry.S 分段色带） | 死在哪一段 | ✅ 全链跑通！userland 版跑到 exec，PID 1 被杀 `EXEC_EXIT_REASON_BAD_MACHO` | **窗口挪位理论实锤** + exec 首次执行 |
 | 7 | `boot-diag-userland-v2/v3/v4.img` | LC_UNIXTHREAD 修复 + 固定窗口 | v3 起内核每轮全通，但 exec 仍 BAD_MACHO；v4 证明 `cs_enforcement_disable` 被 AMFI 封杀 | **窗口已根治；exec 签名校验链是最后关卡** |

### 8.2 坑 #3（已根治）：256 MiB 内核窗口挪位

**机制**：DarwinBoot `AllocateWindow` 对 UEFI 内存图 first-fit 扫描。板子的 UEFI 内存图
（`socratesPkg/Library/MemoryMapLib/MemoryMapLib.c`）里 4 GiB 以下唯一能容纳 256 MiB 窗口的
"可分配"连续区 = DXE Heap（0xBAB00000，209 MiB）+ **"DRAM gap 0xC7CC0000"（208 MiB，注释自认是
"非 stock cfg 非 DT 覆盖的洞，因 stock 也从这里分配而保留为 Conv"）**拼起来的 402 MiB。任何窗口
必然吃进这段未知归属的洞；payload 卷里**多读任何一个文件**（哪怕 56 字节信任缓存 → 一个 4 KiB 池）
都分裂空闲表、改变 first-fit 落点，且每次开机本身也有波动——窗口在洞里滚骰子，滚到保护区上，
`DarwinEnter` 对全窗口 `dc civac` 清洗撞**异步外部中止**（灾难延迟到青带画完才递达，所以 #7 的 v2
看到"绿+黄+青在、白和蓝不在"），复位。

**修复（已在 tools/darwinboot-socrates-diag.patch 固化，两处）**：
1. `Entry.S`：绿条后加黄（civac 前）/青（civac 后）/白（跳转前）三条带——无串口时代的分段遥测，保留为常规工具；
2. `DarwinBoot.c`：`AllocateWindow` 优先固定落在 `0x880000000`（"DRAM bank 1 low"，947 MiB 整段无洞）
   + 横幅新增 `window 0x… fixed/scan` 行。v3 起内核每轮全通，**窗口问题关闭**。

**后续根治（未做）**：MemoryMapLib 把 `DRAM gap 0xC7CC0000` 改 Reserv（则 4 GiB 下无 256 MiB 连续区，
窗口必然走 >4G bank——需先验证该 bank 在本机真实可用）；补洞后可把固定窗口改回扫描。上游化方向：
把"固定窗口 + 洞避让"回馈 UniXNU 社区。

### 8.3 坑 #4（已修复）：LC_MAIN 需要一个不存在的 dyld

第 6 轮首次跑到 exec，PID 1 被 `OS_REASON_EXEC`/`EXEC_EXIT_REASON_BAD_MACHO`（namespace 9 code 1）杀。
源码逐行取证：lld `-e _start` 写 **LC_MAIN**；内核从不读它的 entryoff（mach_loader.c 原注释
"kernel does *not* use entryoff from LC_MAIN. Dyld uses it."），该路径只置 `needs_dynlinker`；
我们剥了 LC_LOAD_DYLINKER → `parse_machfile` 末尾 `needs_dynlinker && !dlp → LOAD_FAILURE` →
exec 以 BAD_MACHO 杀 init。**修复**：`userland/adhoc.py` 第三步手术 `main_to_unixthread()`——
LC_MAIN 换成 288 字节 LC_UNIXTHREAD（arm_thread_state64：flavor 6/count 68/sp=0 内核放默认栈/
pc=__TEXT.vmaddr+entryoff=0x100004000）。test-adhoc.py/build.sh(头空档 16→304)/CI userland.yml/
tools/verify-userland-artifacts.py 全部加了对应用例。新 cdhash `d80d909c…`（旧 `d9ea65f7` 作废）。
（顺带修了 test-adhoc.py 合成二进制 dyld 命令声明尺寸错误：声明 40 实际 28，LC_MAIN 落跳跃死区。）

### 8.4 当前战况（交接点，2026-11-05 午后）

**已经通的**：菜单 → 绿/黄/青/白带 + 蓝/紫探针条 → `-v` 日志 → **mockfs 把 md0 挂成根**（N4KROOT 容器）→
`load_init_program` 找到 `/sbin/launchd` → **进入 exec**。

**卡住的**：exec 的 `load_machfile` 仍以 BAD_MACHO 拒绝这个二进制（LC_UNIXTHREAD 修复后依旧）。
主机端已逐条复现并排除：parse_machfile 全部结构检查（段表/PAGEZERO prot=0/对齐/W^X/LC_UNIXTHREAD
flavor+count+pc）、`cs_validate_codedirectory` 全部 11 项、全部 13 页哈希、mockfs 块算术
（`DEV_BSIZE=512`，4096 对齐无偏移）、卷内字节逐层抽验（LC_UNIXTHREAD 在、cdhash==信任缓存条目）。

**剩余嫌疑**（主机不可完全复现的运行时路径，按可能性排序）：exec 时 `cs_validate_range` 对
"初始页"的校验（mockfs+UBC 页面读入交互）、`load_code_signature` 内部、或某个我复现遗漏的结构检查。

**已封死的路**：`cs_enforcement_disable=1`（v4）→ AMFI 直接 panic
`"can't has cs_enforcement_disable" @AppleMobileFileIntegrity.cpp:5261`——此判别法作废，参数已从板仓撤除。

### 8.5 下一步清单（接手人从这里开始）

1. **最高价值、零成本：拿 -v 滚动文字**。内核在签名加载失败时**无条件打印**
   `proc 1: load code signature error %d for file "/sbin/launchd"`（mach_loader.c:1305）——它就在
   `unexpected SIGKILL` panic 屏**上方的滚动日志里**，翻录像逐帧就有。这行直接写明凶手。
2. 若是签名链：查 mockfs 的 UBC 页读入（`cs_validate_range` 校验的"初始页"字节源）、
   `load_code_signature` 的 SuperBlob→CD→cdhash 流水线与 512 字节设备读的交互。
3. 若无打印（纯结构拒绝）：给 `parse_machfile`/`load_segment` 的每个 `LOAD_BADMACHO` 出口加无条件
   printf（内核重编，两遍构建见 README §3.4；`macho_printf` 只是 sysctl，PID 1 活不过去，改不了）。
4. exec 过了 load 这关后，下一个关口是 AMFI 的平台二进制判定：看 kill code 是否变成
   `SECURITY_POLICY(8)`；若 AMFI 拒绝，查我们信任缓存条目的"类别字节"语义（adhoc.py 用 HASH_TYPE=2，
   AMFI 的 platform-only 模式可能要求 platform 类）。
5. 窗口雷的根治与上游化（见 8.2）。

### 8.6 环境与资产交接

- **构建环境**：WSL2 Ubuntu（用户 `yang`），`~/unixnu-work/{UniXNU, UniXNU-socrates, uefi-socrates}`；
  代理 `http://127.0.0.1:10808`；`ld64.lld` 在 `/usr/lib/llvm-18/bin/`；mtools 齐备；增量固件重建 ~3 分钟。
  新机器按 `README §完整复现` 重建；`tools/wsl-setup.sh` + `tools/restore-uefi-submodules.sh` 可复用。
- **本地修改（不在任何上游仓）**：①UniXNU CLI 的 `--userland` 补丁（`tools/unixnu-userland-payload.patch`
  + 幂等应用脚本）；②DarwinBoot 的色带+固定窗口（`tools/darwinboot-socrates-diag.patch`，基底
  `3c75734` + 幂等应用脚本）。两个 apply 脚本 `repro/build-userland-boot.sh` 都会自动调用。
- **关键产物 sha**（WSL 树现状）：内核 `out/socrates/kernel/kernel.macho` = `668c0eb5…`（探针补丁
  确定性：payload 后 `86574694…`）；userland cdhash `d80d909c…`（launchd `b239bc28…`、容器
  `78656e7a…`）；诊断+固定窗口 FD = `44c152c1…`（`SOCRATES_SERIAL_CONSOLE=0` 屏幕控制台版）。
- **板仓 `userland_args` 现值**：`-v -progress serial=3 debug=0x14e kt_fixed_zones=120 sheng-pmgr=2`
  （fork 逻辑自动追加 `rd=md0`；`cs_enforcement_disable` 已撤）。
- **测试协议**：每次 `fastboot boot` 前先完整进一次 Android；全程录像；判读靠色带 + `-v` 文字
  （OCR 只能转录文字，颜色条只能靠眼睛/录像）。
