# mik60proios — 在红米 K60 Pro 上引导 iPadOS 内核（XNU）

把 **iPad Pro 10.5（iPad7,1 / iPadOS 17.7.11）的 XNU 内核**移植到 **红米 K60 Pro（代号 socrates，骁龙 8 Gen 2 / SM8550）**上运行。

基于 [UniXNU](https://github.com/UniXNU/UniXNU) 移植框架（通过 UEFI 在非 Apple ARM64 设备上引导 XNU）。

> 本仓库是**研究性移植**：目标是让 iOS 内核在第三方硬件上启动，最终形态是"离线平板"（SpringBoard 桌面 + GPU 渲染 + 触摸；Wi-Fi / 蜂窝 / 音频不在目标内）。它**不是**一个可以日常使用的"刷 iOS"方案。

## 当前状态

| 里程碑 | 状态 | 日期 |
| --- | --- | --- |
| ABL 跳转（fastboot boot 真正启动我们的代码） | ✅ | 2026-11-04 |
| UEFI DXE 全链跑通（屏幕 console 输出） | ✅ | 2026-11-04 |
| XNU 内核首启到 console（vm_init 完成） | ✅ | 2026-11-04 |
| AMFI 关卡突破（provider-less ApplePMGRNub 桥） | ✅ | 2026-11-04 |
| **内核完整引导链直到 `Failed to mount root device`**（无存储阶段的预期终点） | ✅ | 2026-11-04 |
| 首个 EL0 用户态进程（RAM root） | ⬜ 下一步 |  |
| UFS 存储阶段（"系统装上了"） | ⬜ |  |
| GPU / 显示 / 触摸 | ⬜ |  |

进度估约 **30%**（以"SpringBoard 桌面跑起来"为 100%）。

## 仓库结构

```
mik60proios/
├── README.md                 # 本文件（复现说明书）
├── BRINGUP-LOG.md            # 调试战记：每个关卡的根因、证据与修复
├── board/UniXNU-socrates/    # 设备仓（board.toml + 内核构建脚本 + 驱动 + 校验器）
├── firmware/uefi-socrates/  # 固件仓（Mu-Silicium 检出 + socratesPkg，含全部修复）
├── tools/                    # 移植过程中自研的诊断 / 注入 / 验证脚本
├── docs/                     # ABL 源码级分析、社区先例研究
└── prebuilt/                 # 可直接 fastboot boot 的成品镜像（省去编译）
```

两个子目录保留了**完整的 git 提交历史**——每条提交信息都写明了当时的真机证据（"first-boot hardware evidence"），是本移植的第一手记录。

## 快速开始（不用编译）

1. 手机解 BL 锁。
2. 下载 `prebuilt/boot-pmgrlate-boot.img`。
3. **先完整开机进一次 Android**（详见下方"测试协议"）。
4. ```bash
   adb reboot bootloader
   fastboot boot boot-pmgrlate-boot.img
   ```
5. 屏幕依次出现：绿色条（loader handoff）→ 蓝条（内核入口探针）→ 红紫条（MMU 开启探针）→ ……最终停在：

   ```
   Failed to mount root device @IOKitBSDInit.cpp:984
   ```

   **这不是错误**——这是没有存储设备时内核引导链的预期终点（AMFI 已通过，root 卷不存在）。

## 完整复现

### 0. 环境要求

- Windows 10/11 + **WSL2（Ubuntu 24.04）**，WSL 内存建议 16 GB+
- 一台已解 BL 的红米 K60 Pro（socrates）
- 代理（如需）：WSL2 mirrored 网络下宿主机代理 `127.0.0.1:10808` 直通
- 下载 **官方线刷包** `socrates_images_OS3.0.304.0.WMKCNXM_..._cn_*.tgz`（约 8.4 GB，从小米官方/MIUI 历史版本站自取，**不入本仓库**——产权归小米）——放到 `firmware/` 下解压
- 磁盘：另需约 40 GB 空闲

### 1. 取得上游与本仓库

```bash
mkdir -p ~/unixnu-work && cd ~/unixnu-work
git clone https://github.com/UniXNU/UniXNU.git
git clone https://github.com/buzhaodi/mik60proios.git
# 本仓库的两个子仓直接可用：
#   mik60proios/board/UniXNU-socrates
#   mik60proios/firmware/uefi-socrates
```

> **注意**：从本仓库复制出来的两个子目录**不带 .git**（历史在父仓对象库里），而 `unixnu` 驱动要求它们是 git 仓（要跑 submodule update）。复制后各执行一次：
> ```bash
> cd ~/unixnu-work/UniXNU-socrates && git init && git add -A && git commit -m snapshot
> cd ~/unixnu-work/uefi-socrates   && git init && git add -A && git commit -m snapshot
> bash mik60proios/tools/restore-uefi-submodules.sh ~/unixnu-work/uefi-socrates
> ```

> 工作区布局（与构建脚本里的路径一致）：
> ```
> ~/unixnu-work/
> ├── UniXNU/                    # 上游 CLI
> ├── UniXNU-socrates/           # ← 复制 mik60proios/board/UniXNU-socrates 到这里
> ├── uefi-socrates/             # ← 复制 mik60proios/firmware/uefi-socrates 到这里
> └── firmware/                  # 官方固件解压目录
> ```

### 2. 安装 Linux 工具链

```bash
cd ~/unixnu-work/UniXNU
python3 scripts/linux/setup-toolchain.py
```

构建 XNU 用的是上游 clang + `scripts/linux/xcrun` shim（无需 macOS）。

### 3. 构建全链路

```bash
cd ~/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808   # 按需

# 3.1 生成设备配置（重要：改过 configs/socrates_defconfig 后必须重跑这一步，
#     它把 CONFIG_XNU_* 解析进 out/socrates/.config，只改文件不生效！）
python3 unixnu defconfig socrates_defconfig -D ../UniXNU-socrates

# 3.2 拉源（XNU、IPSW 组件等；IPSW 约 5 GB，等一次即可）
python3 unixnu fetch --uefi ~/unixnu-work/uefi-socrates -D ../UniXNU-socrates

# 3.3 组装构建树
python3 unixnu tree --uefi ~/unixnu-work/uefi-socrates -D ../UniXNU-socrates

# 3.4 内核（含 AMFI PMGR 桥；首次全量约 1-2 小时，之后增量很快）
# 注意：桥的审计需要一个"已存在的 prelink 产物"做参照——干净首次构建要连跑两次：
# 第一遍没有参照物，自动跳过桥（正常提示，不是错误）；第一遍的 prelink 产物会
# 具现参照物，第二遍把桥编进去。
python3 unixnu build kernel --uefi ~/unixnu-work/uefi-socrates -D ../UniXNU-socrates
python3 unixnu build kernel --uefi ~/unixnu-work/uefi-socrates -D ../UniXNU-socrates

# 3.5 固件（首次 openssl 全量编约 1 小时，edk2 的 -n32 只按模块并行、模块内串行）
python3 unixnu build firmware --uefi ~/unixnu-work/uefi-socrates -D ../UniXNU-socrates

# 3.6 payload 卷（--unique-chip-id 是占位种子，不落盘任何真机数据）
python3 unixnu build payload --uefi ~/unixnu-work/uefi-socrates -D ../UniXNU-socrates \
    --unique-chip-id 0000000000000001

# 3.7 DTB 守卫注入：往 8 块 vendor DTB 里注入 splash 和 XPU 保护节点后拼接
bash mik60proios/tools/inject-nodes.sh   # 产物 out/socrates-all-dtbs.dtb

# 3.8 打包 boot 镜像
python3 unixnu bootimg --uefi ~/unixnu-work/uefi-socrates -D ../UniXNU-socrates \
    --dtb out/socrates-all-dtbs.dtb \
    --ramdisk ~/unixnu-work/UniXNU/out/socrates/payload/payload.img \
    -o out/boot.img
```

### 4. 上机（测试协议！）

```bash
adb reboot bootloader
fastboot boot out/boot.img
```

> **⚠️ 测试协议（本移植用 ~6 轮白测换来的教训）**
>
> **每次 `fastboot boot` 之前，必须让手机完整启动一次 Android。**
> 内核崩溃复位后，ABL/PMIC 会留下污染态——之后**任何**镜像（包括已知良好的）都会在内核入口静默复位（绿条后无蓝条、无 panic、秒级重启）。进一次 Android 清态后同一镜像立即恢复正常。
>
> 屏幕三色条的判读：**绿** = DarwinBoot handoff 标记 → **蓝** = 内核入口探针（MMU off）→ **红紫** = MMU 开启探针。**绿条之后没有蓝条** = 镜像入口坏，或手机态脏。

## 这个移植踩过的坑（详见 BRINGUP-LOG.md）

| 关卡 | 根因 | 修复 |
| --- | --- | --- |
| `fastboot boot` OKAY 但不跳转 | 单块 QCM DTB 的 msm-id 不匹配本机芯片 | 追加全部 8 块 vendor DTB，ABL 自己挑 |
| DXE 阶段 `ASSERT ArmCpuDxe CpuExceptionHandlerLib.c:438`（FAR=0xD8000000，三次逐字节复现） | IortDtDxe 按名查不到 "XBL DT"（生成器把 stock 名改成了 DT 节点名），扫描**未初始化栈变量** 0xD8000000 读 FDT magic | 内存图生成器改为 stock 名优先（名字是 `LocateMemoryRegionByName` 的 ABI）+ 驱动零初始化 + 8 个 XPU 保护洞 |
| `AMFI: No PMGR? @ConfigurationSettings.cpp:235` | AMFI 等 ApplePMGRNub；sheng 的桥在 bsd_bufferinit 后调用 = **IOKit 初始化之前**——registry 不存在、console 未接（panic 画成"花纹"） | 调用点后移到 `IOKitBSDInit()` 之前 + 去掉冗余 kext 加载（ApplePMGR 已在 prelink roots） |
| "任意镜像都重启"假象 | 崩溃后手机引导环境被污染 | 每次测试前先进一次 Android |
| "裁剪参数也重启"假象 | 完整参数行里的开关（`sheng-touch=0` 等）是必需品，内核默认路径会踩硬件 | kernel_args 逐字保留，不做裁剪实验 |

## 已知限制与未解事项

- `dtbo` 叠加固定选 entry 0（babylon overlay 非 socrates 板）——内核阶段需要离线合并处理
- FD @0xA7100000 与平台 UEFI FD 窗潜在重叠（fuxi 先例挪到 0xCE000000）
- 触摸（Goodix SPI）、UFS 存储、GPU（Adreno 740）驱动未接
- `userdata` 的 last_lba 尚未真机实测
- 无串口驱动——调试全靠屏幕录像 + panic 屏（串口移植在 todo 上）

## 致谢

- [UniXNU](https://github.com/UniXNU/UniXNU) 及其社区——移植框架与全部先例记录
- sheng（小米平板 6S Pro）移植者——PMGR 桥、软件栈蓝本
- vermeer（Redmi K70）移植者——同 SoC 模板
- sirius-yooglery 的记录——provider-less ApplePMGRNub 即可满足 AMFI 锁存的关键发现
- fuxi-oddlylabs 的记录——"Failed to mount root device 是无存储阶段的预期终点"的判读基准

## 许可

本仓库自有代码遵循其所在子目录中的许可声明；上游组件（XNU 衍生、Mu-Silicium、edk2）版权归各自所有者。小米官方固件的任何部分**不在**本仓库中，请自行从小米官方渠道获取。
