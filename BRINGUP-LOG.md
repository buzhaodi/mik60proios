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

> **2026-11-05 起 `prebuilt*/` 整体退役**（仓库体积政策，`.gitignore` 忽略 `*.img` 与整个
> `prebuilt*/`）：镜像二进制、`.json` 清单均不入库，上机记录（各段 sha）就写在本文件文字里。
> 要拿可刷写的镜像请按 `README` §完整复现 或 `repro/build-userland-boot.sh` 自行构建。git 历史里
> 的旧 img/清单不追删；如需彻底瘦身历史（filter-repo 重写）属于破坏性操作，由仓库所有者自行决定。

历史记录（json 清单已删，关键 sha 存档于此）：上机验证到 `Failed to mount root device` 的那一版
（proven 基线）= FD `a3741876...`、DTB `5c731bfe...`、boot 镜像内核段 `e5909857...`；首个 EL0 里程碑
初版 cdhash `d9ea65f7...`（LC_MAIN 版，已被 §8.3 的 `d80d909c...` 取代）。

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

> 本节是完整战况记录与交接文档。判别镜像的 .img 与 .json 清单均已按仓库政策删除（`prebuilt*/` 退役），
> 关键 sha 已写入本节与 §6 文字，镜像一律按 `repro/build-userland-boot.sh` 重建。

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

---

## 8.7 第 8 轮准备：把 exec 死因写进 panic 定格屏（2026-11-05 傍晚）

### 8.7.1 为什么 §8.5 第 1 条作废了

上机录像取证（5.35 s、30 fps、76 帧逐帧 OCR）：菜单横幅（0~3.2 s）→ DarwinBoot 交内核横幅
（3.2~3.8 s）→ `-v` 日志在 ~0.4 s 内高速滚过（全是拖影，30 fps 读不出）→ **panic 渲染器清屏**
（证据：一帧整屏空白、panic 块逐行重绘、定格块上方无任何 `-v` 文字残留）。两个推论：

1. `proc 1: load code signature error %d for file "/sbin/launchd"` 那行**不在 panic 屏上方**——
   被清屏抹掉了，"拍整屏照片找它"这条路不存在（§8.5 第 1 条前提作废）。
2. 内核侧 GENI 串口驱动未移植（README"已知限制"），`-v` 日志唯一出口就是这块被清掉的屏幕。

→ 唯一可靠通道：**把 exec 错误码直接印进 panic 定格块**（240 fps 慢动作重拍理论可行但无法执行，选内核插桩）。

### 8.7.2 机制（全部是 monorepo 内容，v1 板仓补丁）

- **内核埋点** `board/UniXNU-socrates/package/patches/xnu-exec-trace.patch`：mach_loader.c 定义
  `volatile unsigned long g_exec_trace = 0xE7E37ACE00000000ULL`（高 32 位是 canary，兼保证变量落在
  file-backed __DATA 段——patcher 符号校验的要求），7 个阶段戳 + 3 个返回码打包进低 32 位：
  `STAGE | CS_ERR<<8 | MACH_ERR<<16 | LOAD_ERR<<24`。戳位：mach_loader.c（load_machfile 入口、
  parse_machfile 入口、LC_CODE_SIGNATURE 分发、签名错误 printf 处、签名成功处、parse 返回处）
  + kern_exec.c（load_machfile 返回处，紧跟 zzz 的 boot-progress stamp 之后）。
- **v1 补丁机制**：schema v1 板仓**不走** `scripts/unixnu/patches.py` 的 `patch_series`（kernel.py
  只在 `ctx.schema_version == 2` 时才调 `patches.prepare()`，本板不满足——board.toml 里配了也不生效）。
  正路是 `build-xnu-4k-baseline.sh` 的补丁循环：feed 序列（`tree/patches/xnu`，名字序）→
  `kits/NativePrelink/patches` → **新增 `kits/socrates/patches/*.patch` glob**（板仓 package/ 即 kit）。
- **幂等性坑（实机踩过）**：本补丁的 kern_exec hunk 落在 zzz-boot-progress 的 "load_machfile
  returned" stamp 与 `if (lret != LOAD_SUCCESS)` 之间，必须进 LATE 反序列表且**排最前**（最新应用的
  最先反）。不反它，zzz 失去反向能力，连锁把第二遍构建崩在
  `offline-owner-root-binding-audit @ bsd_init.c:987`（补丁既不在已应用态也应用不上，整个序列失去幂等）。
- **panic 屏**：`xnu-panic-screen.c` 新增一行 `EXEC=0x…`（blob `0x9ED`→`0xA14` = 2580 字节，预算
  `0xA30` 内）；`patch-xnu-entry-probe.py` 解析 `_g_exec_trace`（可选符号——没有它的老内核不打印、
  行为不变）；`check-xnu-panic-screen.py` 加了 fixture 与期望行，本机（brew qemu）QEMU 逐像素自检
  **6 行全绿**（真实内核符号地址 + 真实编译产物，`EXEC=0xe7e37ace02020204` 按像素命中）。

### 8.7.3 本机（Mac）全链产物

| 产物 | sha256 前 16 |
| --- | --- |
| kernel.macho（裸，两遍，sheng bridge 10 个符号） | `2d2fea3082021729` |
| payload_kernel_sha256（探针+panic 屏打入后） | `736b064f1a8ffce7` |
| userland launchd cdhash（Apple clang 21） | `dc6ea535b18dedf8`（WSL llvm-18 构建为 `d80d909c`；各自自包含签名，信任缓存链各自一致） |
| FD（屏幕版，含已验证 DarwinBoot 双改动） | `5a556300e360e076`（全新构建，非上机逐字节验证过的 `a3741876`） |
| DTB 表（8 块 + 注入节点） | `5c731bfef20c52e1` —— **与上机验证过的逐字节相同** |
| payload.img | `deeef8cddc165a24` |
| **boot.img（72,040,448 B）** | `f8400bd6a02a42d1` @ `~/unixnu-work/out/boot-userland/boot.img` |

链路全在本机：kernel 两遍增量重编 → userland（test-adhoc 14 项 + verify-userland-artifacts
**PASS**）→ payload → firmware → inject-nodes-mac.sh → bootimg。`repro/repro-build-mac.sh` 全量
复现路径第 1 步整仓拷贝板仓，自动包含本改动；`repro/build-userland-boot.sh`（WSL）已补同步
scripts/ 与 package/patches/（注意：WSL 侧需先重跑一遍 kernel 两遍——该脚本不重编内核）。

### 8.7.4 上机判读表（panic 屏新增 `EXEC=` 行）

高 32 位应为 `e7e37ace`（canary：证明渲染器读数正常；不是它 = 符号解析错，截图回报）。低 32 位四字节：

| 字节 | 含义 |
| --- | --- |
| byte0 STAGE | 1 进了 load_machfile；2 进了 parse_machfile；3 到 LC_CODE_SIGNATURE；**4 签名加载失败（byte1=printf 没能留下的错误码，即 §8.5 想要的那个数）**；5 签名已载入；6 parse 已返回（byte2=返回码）；7 load_machfile 已返回（byte3=返回码） |
| byte1 CS_ERR | load_code_signature 的 load_return_t |
| byte2 MACH_ERR | parse_machfile 的 load_return_t |
| byte3 LOAD_ERR | load_machfile 给 exec 的最终 load_return_t |

LOAD_ 码：0 SUCCESS / 1 BADARCH / **2 BADMACHO** / 3 SHLIB / **4 FAILURE** / 5 NOSPACE / 6 PROTECT /
7 RESOURCE / 8 ENOENT / 9 IOERROR / 10 DECRYPTFAIL / 11 BADMACHO_UPX。

**判读**：
- `STAGE=04` + `CS_ERR=N` → 签名链拒绝，N 对号入座（2 → load_code_signature 判 BAD_MACHO，查
  SuperBlob→CD→cdhash 流水线与 512 字节设备读；4 → 查 cs_validate_* 初页路径）。
- `STAGE=05`（或 06）→ 签名装好了，死在签名后的校验（cs_validate_range 初页 / mockfs UBC 读入）。
- `STAGE=07` + `LOAD_ERR=00` → **加载链全通**，BAD_MACHO 死在 exec 加载之后（activate/thread
  state）；若 AMFI 是凶手，panic 行 namespace 应变 8（SECURITY_POLICY）——即 §8.5 第 4 条的关口。
- 全 0 → exec 压根没进 load_machfile（前置路径/权限问题，另一种案子）。

### 8.7.5 测试协议增量

- 照常：先完整进一次 Android → `fastboot boot ~/unixnu-work/out/boot-userland/boot.img` → 全程录像。
- panic 定格后 **`EXEC=` 行就是本轮要的答案**；拍照/录像帧都行，发对话即可 OCR（本地 Vision 流水线
  可用；flash 模型图片子智能体 2026-11-05 起报 `[1113] 余额不足`，充值前以本地 OCR 替代）。
- 主机侧复跑渲染器自检：`PATH=/opt/homebrew/opt/llvm/bin:$PATH UNIXNU_UEFI=~/unixnu-work/uefi-socrates
  python3 board/UniXNU-socrates/scripts/check-xnu-panic-screen.py --candidate
  ~/unixnu-work/UniXNU/out/socrates/kernel/kernel.macho`。

---

## 8.8 第 8 轮三连闪：exec 全通、__LINKEDIT 真凶归案、PID 1 跑进 EL0（2026-11-05 晚）

### 8.8.1 事实链（三次上机照片，EXEC/FAULT 行都是本地 Vision OCR 读出）

| 轮 | 插桩 | 屏上证据 | 结论 |
| --- | --- | --- | --- |
| v1（计数编码） | STAGE=7/CS=0/MACH=2/LOAD=2 | 签名加载无错；parse_machfile 返回 **LOAD_BADMACHO(2)**；初始页校验失败会是 4 —— 排除 | 凶手在 parse_machfile 内 |
| v2（位掩码+SITE） | SITE=**05**，MACH=2，CS=0 | **load_segment() 在 pass 2 返回 BADMACHO**（pass 1 签名已无错先过） | 凶手是段加载 |
| 修复上机 | panic 换成 `initproc failed to start -- exit reason namespace 2 subcode 0xa` | **exec 全链通过；PID 1 进 EL0 执行后死于 SIGBUS(10)** | exec 关卡关闭 |
| v3（EL0 abort 上下文） | FAULT_PC/AT/ESR/SP **全零** | SIGBUS 死了但 **handle_user_abort 从未走到** —— 异常不来自 EL0 硬件 abort | 凶手在别的异常→信号路径 |
| v4（信号漏斗） | 待上机 | 新增 SIG_CODE/SIG_AT/SIG_INFO + FAULT_K | 见下 |

### 8.8.2 真凶：adhoc.py 的 `__LINKEDIT.filesize` 写成了文件终点

段表 dump + xxd 实证：`__LINKEDIT fileoff 0xC000, filesize 0xD230`（= 整个文件大小 53,808，而非段长 0x1230）
→ 内核 `load_segment` 的第二道检查 `fileoff + filesize > macho_size` 直接 `LOAD_BADMACHO`
（0xC000+0xD230=0x1D230 ≫ 0xD230）。根因：`set_linkedit_size(code_limit + datasize)` 把**文件终点**
当 filesize 直写。test-adhoc.py 的断言 `filesize == len(image)` 还把这个 bug 固化成了规范，三处验证链全漏。

修复（全部 monorepo）：`adhoc.py set_linkedit_size(file_end)` 按段自身 fileoff 求长度；
`test-adhoc.py` 断言改 `fileoff + filesize == len(image)`；
`tools/verify-userland-artifacts.py` 新增"每段必须落在文件内 + __LINKEDIT 必须终止于文件尾"两条内核级不变量。
修复后 userland `__LINKEDIT 0xC000+0x1230=0xD230` ✓，cdhash `3b3521eb…`，上机即通。

**对 §8.3 的连坐修正**：第 6 轮把 BAD_MACHO 归因于 LC_MAIN→needs_dynlinker —— 该修复本身仍然必要
（否则 LOAD_FAILURE），但第 7/8 轮的 BAD_MACHO 从未"修完过"；v1 的 MACH=2 才首次把两者区分开。

### 8.8.3 里程碑与当前卡点

**exec 正式通关**（研究 agent 取证：上游 UniXNU 的 mockfs+adhoc PID 1 里程碑在 gta4l 真机通过，
vermeer 的 userland 是同构公开孪生 —— 路线有先例）。现卡点：**PID 1 的某个内存访问触发
KERN_PROTECTION_FAILURE 类异常 → SIGBUS → init 死于 spawn 窗口内**。v3 证明该异常**没有**走
EL0 abort 路径（FAULT 全零）；`handle_ux_exception`（bsd/uxkern/ux_exception.c —— Mach 异常→
UNIX 信号总漏斗）的栈溢出改判逻辑还透露：故障地址**不在** `[user_stack-MAXSSIZ, user_stack)` 栈区间内。

### 8.8.4 v4 插桩（本轮镜像）

- 内核补丁第 4 版（4 文件 21 hunks）：mach_loader.c `g_exec_fault[8]`（双 kind 位：1=EL0 abort,
  2=信号漏斗）；sleh.c 打点改累积 `|= 1`；**新增 bsd/uxkern/ux_exception.c** —— 在
  `handle_ux_exception` 投递信号处记 `(code, subcode, exception<<32|signal)`。
- panic 屏新增：`FAULT_K=`（kind+canary）、`SIG_CODE=`（kern_return）、`SIG_AT=`（**故障地址**）、
  `SIG_INFO=`（异常类型|信号）。渲染器 0xAEE=2798 字节（重定位预算 3008 内）。
- 判读表：
  - `SIG_AT≈0x16FE00000±`（USRSTACK64）→ 默认栈放置/保护问题（sp 落进保护区或栈顶上方 guard）；
  - `SIG_AT≈0x10000xxxx`（__TEXT/__DATA）→ 页读入/权限问题（W^X、cs_validate 页）；
  - `SIG_AT≈0x1A0/0x0` → sp 根本没被设好；
  - `FAULT_K=…01` = 有 EL0 abort（看 FAULT_PC/AT/ESR/SP）；`…02` = 仅信号漏斗；
  - `SIG_CODE=2` = KERN_PROTECTION_FAILURE（SIGBUS 对应）；`=1` = KERN_INVALID_ADDRESS。

### 8.8.5 产物（v4，全部本机）

内核 `661b9c74ee7c40b9`（裸，两遍，`_g_exec_trace`/`_g_exec_fault` 双符号在案）；
boot.img `85339780e51545ca`（72,040,448 B，`~/unixnu-work/out/boot-userland/boot.img`）；
渲染器 0xAEA=2798 字节 → 溢出重定位第二次触发（0x12d0 free）；QEMU 自检 **14 行逐像素 PASS**；
userland cdhash `3b3521eb…`（__LINKEDIT 修复版，Apple clang 21）。
WSL 复现：`repro/build-userland-boot.sh` 已同步 scripts/+package/patches（注意先跑 kernel 两遍）。

---

## 8.9 第 9 轮：SIGBUS 归案（EXC_ARM_SP_ALIGN）与第一个存活的 PID 1（2026-11-05 夜）

### 8.9.1 v4 上机解码（FAULT_K/SIG_* 四行）

```
initproc failed to start -- exit reason namespace 2 subcode 0xa description: no…
EXEC      = 0xe700000000000077    ← 掩码 0x77：stages 1/2/3/5/6/7 全走，签名加载成功，stage4 未触发
FAULT_K   = 0xe700000000000002    ← 仅信号漏斗走过（bit0 无：EL0 abort 路径根本没执行！）
SIG_CODE  = 0x0000000000000103    ← EXC_ARM_SP_ALIGN（osfmk/mach/arm/exception.h:75）"SP Alignment Fault"
SIG_AT    = 0x000000016FDFFC28    ← 故障地址 = USRSTACK64-0x3D8（栈顶串区）
SIG_INFO  = 0x000000010000000a    ← EXC_BAD_ACCESS | SIGBUS
```

**根因链**：`exec_copyout_strings`（kern_exec.c 5700-5748）按 argv/env 字节数从栈顶扣减，
**没有任何 16 字节对齐**就交付 `*stackp` —— 本次 argv 恰好把 sp 留在 8-mod-16；
SCTLR=0x…3454593d 的 bit4（SA0，EL0 栈对齐检查）=1；`_entry` 首条
`stp x26,x25,[sp,#0x190]`（sp-0x50=0x16FDFFC28）触发 SP-alignment trap，
异常分类器在 `handle_user_abort` **之前**直接 `exception_triage(EXC_BAD_ACCESS, EXC_ARM_SP_ALIGN, addr)`
（这正是 v3 打点为全零的原因），`ux_exception` 按 code≠KERN_INVALID_ADDRESS 翻成 SIGBUS；
`handle_ux_exception` 的栈溢出改判要求 code==KERN_PROTECTION_FAILURE(2)，0x103 不满足 → SIGBUS 保持 → init 死。

（顺带解释上一次"直接重启"：sp 的对齐量随 argv/env 布局浮动，那一次开机可能恰好 16 对齐、
init 跑过了这一关，死在了后面某个会复位的地方 —— 修复后此变量消除。）

### 8.9.2 修复：start.S 防御性对齐（用户态单方修，内核零改动）

`userland/start.S` 在捕获 `x0 = sp`（&argc）之后、任何栈访问之前把 sp 对齐到 16：
`mov x17, sp; and x17, x17, #0xf; sub sp, sp, x17`（ARM64 逻辑立即数不能写 SP，只能 SUB；
x17 是 scratch——syscall 号寄存器，每次 `_syscall_raw` 重写）。新 cdhash `9d35be3e…`。

### 8.9.3 🎉 第一个存活的 PID 1（修复版上机）

boot.img `dedc67fb186fd8d6`（内核 `661b9c74` 不变 + 对齐修复 userland）上机：
**绿（DarwinBoot）→ 蓝（探针 stage1）→ 粉（stage2）→ 黄（civac 前）→ 白（跳转前）全带，
齿轮 spinner（`-progress`，PE_init_iokit 的 gGearPict）持续转动，无 panic。**
init 若死必在秒级定格 "initproc failed to start"（v1-v4 四轮皆如此）——
**spinner 持续转 = PID 1 存活 = 本机第一个自建 adhoc EL0 进程落地。**
待录像复核：齿轮下方 `-v` 滚动里的 N4KROOT banner（双线框 + PID/UID + sysctl 探针 + /probe.bin motd）与心跳 tick。

### 8.9.4 战役总结与本轮武器资产

八天战役（§8.1-8.9）从"菜单复位"到"第一个活的 EL0 进程"，三关连破全靠 panic 定格屏插桩：

| 关 | 证据通道 | 真凶 | 修复 |
| --- | --- | --- | --- |
| exec BAD_MACHO | v1 STAGE/MACH、v2 SITE 位点 | `__LINKEDIT.filesize`=文件终点而非段长 | adhoc.py 语义修正 + 三验证链不变量 |
| PID 1 SIGBUS | v3 FAULT 全零、v4 SIG_CODE/AT | 内核交付 sp 8-mod-16，SA0 → EXC_ARM_SP_ALIGN | start.S 三指令对齐 |
| （工具） | EXEC/FAULT_K/SIG_* 上屏 | — | exec-trace v1-v4 内核补丁 + 信号漏斗打点 + 渲染器溢出重定位 |

所有插桩与修复均为 monorepo 内容（`package/patches/xnu-exec-trace.patch`、board scripts、
userland 三件套），WSL/Mac 双路复现（`repro/build-userland-boot.sh` / `repro/repro-build-mac.sh`）。

### 8.9.5 下一步

1. 录像确认 banner/心跳（§7.6 通关标志逐项），回填 8.9.3；
2. userland README 的探针清单按需加码（cs op、port、更广 sysctl）；
3. 下一大关按 §8.5-4：AMFI 平台二进制判定已在身后（签名链已过，AMFI 未拦）——
   实际下一关自选：存储阶段（APFS/UFS + Apple 原版 launchd，研究 agent 取证的 sheng 路线）
   或继续深挖自建 userland 的能力清单。
