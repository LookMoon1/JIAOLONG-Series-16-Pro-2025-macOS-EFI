# Notes for AI assistants

本文件告诉 AI 助手（及自动化 harness）如何安全地在本仓库工作。
**优先级**：本文件 > 你的默认习惯。若与用户当次指令冲突，以用户指令为准。

---

## 一、这个仓库是什么

一台 **MECHREVO JIAOLONG 16 Pro 潮玩版**（AMD Ryzen 9 9955HX + NVIDIA RTX 5060 Laptop，
MUX 独显直连）上运行 **macOS 26 Tahoe** 的 OpenCore EFI 配置仓库。

- 目标系统：macOS **26.7.3 (25G342)**
- 引导器：OpenCore **DBG-109-2026-11-08**（1.0.9 dev，**比官方 1.0.8 新，勿降级**）
- 显卡驱动：NullMoth NVIDIA 3.0
- 无线驱动：YYavicWiFi 0.8.0（MT7922）

**这不是通用 EFI**。所有配置针对上述特定硬件，换机器大概率不启动，因此仅能用于参考。

---

## 二、动手前必读（按顺序）

| # | 文件 | 为什么 |
|---|---|---|
| 1 | [README.md](README.md) | 当前状态、关键配置、快速开始 |
| 2 | [docs/02-关键配置与踩坑.md](docs/02-关键配置与踩坑.md) | **每个配置值的因果**，以及已证伪清单 |
| 3 | [docs/04-许可证与归属.md](docs/04-许可证与归属.md) | 改 kext / 发布前**必须**看 |
| 4 | [docs/01-硬件与兼容性.md](docs/01-硬件与兼容性.md) | 哪些能用、哪些不能 |
| 5 | [docs/06-参考文献.md](docs/06-参考文献.md) | 决策来源，避免重复踩坑 |
| 6 | [docs/STYLE.md](docs/STYLE.md) | **改文档前必读**（排版规范） |
| 7 | [docs/09-EC驱动与性能面板.md](docs/09-EC驱动与性能面板.md) | 性能面板原理与事故记录（**R10 相关**） |

---

## 三、绝对红线（违反会导致机器不开机或数据丢失）

### 🔴 R1 — 不要动 macOS 之外的任何分区

典型布局是**单盘双系统**：EFI + MSR + Windows(C:) + Recovery + 数据盘(D:) + macOS(APFS)。

> ⚠️ **具体分区大小因机器而异，本文不记录任何真实容量。**
> 动手前必须自己用 `Get-Partition` / `diskutil list` 现场确认。

**任何** `diskpart` / `diskutil erase` / `sgdisk` / `mkfs` 操作前，必须：

1. 现场确认目标分区**确实是 APFS 的 macOS 分区**（看文件系统类型，不要靠容量猜）；
2. 确认**不是**整盘操作（`diskutil eraseDisk` 会抹掉所有分区）；
3. 涉及磁盘写入时，**先向用户复述你要做的操作并取得确认**。

> 提示：「磁盘工具」里选中物理磁盘顶层点「抹掉」会抹掉整个 Windows 盘。
> 正确做法是选物理磁盘 → 点「**分区**」→「+」新建 → 拖到目标大小 → APFS。

### 🔴 R2 — 不要用官方 OpenCore release 覆盖现有 EFI

当前是 **DBG-109-2026-11-08（1.0.9 dev）**，比官方最新 release **1.0.8 更新**。
用 1.0.8 覆盖是**倒退**，可能破坏 NullMoth 驱动的依赖。

### 🔴 R3 — 不要删这些 boot-args

```text
amfi=0x80 amfi_get_out_of_my_way=0x1     ← NullMoth 驱动硬依赖
nvfb=1 nvaccel=1 nvfbheads=4 gfxrst=4    ← NullMoth 驱动
nvrmacpibl=1                             ← 内屏亮度
```

删任何一个都会导致显卡不工作 / 黑屏 / 无亮度。

### 🔴 R4 — 不要提交真实三码

`config.plist` 中以下字段**必须保持占位符**才能提交到公开仓库：

| 字段 | 允许的值 |
|---|---|
| `PlatformInfo → Generic → SystemSerialNumber` | `SERIAL-GENERATE-YOUR-OWN` |
| `PlatformInfo → Generic → MLB` | `MLB-GENERATE-YOUR-OWN` |
| `PlatformInfo → Generic → SystemUUID` | `00000000-0000-0000-0000-000000000000` |
| `PlatformInfo → Generic → ROM` | 空 `<data></data>` |

提交前跑 `python3 scripts/validate.py EFI/OC/config.plist`，它会检查这四项。

### 🔴 R5 — 不要运行 `cleanup-injected.sh`

该脚本是为「驱动注入失败」准备的。当前系统是靠驱动在跑，
照它删文件**可能把显卡搞黑**。

### 🔴 R6 — `-yyavicnoverify` 是高风险参数

它让 YYavicWiFi **跳过 macOS build 检查**（0.8.0 针对 25G332，本机是 25G342）。
布局一旦变化会 **kernel panic**。

- 不要"顺手"删掉它 —— 删了 Wi-Fi 就没了
- 不要用它去适配**其它** macOS build（如 26.8）而没有实测
- 任何涉及系统更新的操作，**先提醒用户备份 EFI**

### 🔴 R7 — 不要动 `LauncherOption`，它会破坏 BIOS 启动优先级

本机已通过 **BIOS `Hard Drive BBS Priorities`** 实现内置硬盘引导 OpenCore（无需 U 盘）。

| 位置 | 设置 | 必须保持 |
|---|---|---|
| 两份 config（U 盘 + 内置） | `Misc → Boot → LauncherOption` | **`Disabled`** |

**原因**：`LauncherOption = Full` 会让 OpenCore 每次启动都**重写 BootOrder**，
把 BIOS 里手工设好的优先级挤掉，导致又变回直接进 Windows。

另外：

- ❌ **不要**再用 UEFI Shell 的 `bcfg` 加启动项 —— **本机固件不认**
- ❌ **不要**在 OC 自带 OpenShell 里改启动变量 —— 会被 `RequestBootVarRouting` 重定向（假写入）
- ✅ 正确做法是改 **BIOS → Boot → Hard Drive BBS Priorities**
- ⚠️ 顶层 Boot 类别列表里**看不到 OpenCore 是正常的**，只在 BBS 子菜单里出现

完整说明见 [docs/07-内置EFI引导修复.md](docs/07-内置EFI引导修复.md)。

### 🔴 R8 — macOS 26 上不要再用 AppleALC 修声卡

**苹果从 macOS 26 Tahoe 起删除了 `AppleHDA.kext`**，而 `AppleALC` 依赖它。

- ❌ 不要尝试 `AppleALC + alcid=15` → **在 Tahoe 上根本不会工作**
- ❌ 不要试各种 `layout-id` → 同上
- ❌ 不要把网上 macOS 15 时代的教程套用过来
- ✅ 本机的正解是 **`VoodooHDA_BL.kext`（3.7.1 BL 版）**

`VoodooHDA_BL` 的两个必要条件：

1. **必须是 BL 版**（内嵌 `IOAudioFamily`）；稳定版 3.6.8 在 EFI 注入会报 `Invalid Parameter`
2. **必须改 `IONameMatch`**：`"HDAS"` → `["AZAL", "pci1022,15e3"]`，否则驱动不加载

完整说明见 [docs/08-内置声卡修复.md](docs/08-内置声卡修复.md)。

### 🔴 R9 — Fn 键会导致系统重启（已知未修复）

| 操作 | 结果 |
|---|---|
| 单独按 **Fn** | ❌ 无反应 |
| Fn + F 功能区按键 | 🔴 **整机重启** |
| 单独按 F1–F12 | ✅ 正常 |

**这是已复现的真实缺陷，不是配置错误。** 遇到"Fn 键不好用"的反馈时：

- ❌ **不要**去删 `BrightnessKeys.kext`（无害，删了滑块也不会好）
- ❌ **不要**在无备份情况下改 `SSDT-EC` 的 EC query 映射
- ❌ **不要**声称"Fn 键已修复"或"亮度 Fn 键可用"——**当前不可用**
- ✅ 正确说法：亮度**滑块**可用，Fn 键不可用且组合键会重启

详见 [docs/02-关键配置与踩坑.md](docs/02-关键配置与踩坑.md) 第四节之二。

### 🔴 R10 — 不要启用 `SSDT-MechrevoData.aml`

| 项 | 状态 |
|---|---|
| `MechrevoEC.kext` | ✅ **已启用**（v9 只读采样，稳定） |
| `SSDT-MechrevoData.aml` | ❌ **必须保持 `Enabled=False`**（文件在，不启用） |

**原因**：2026-11-19 曾把该 SSDT 与改版驱动 v7 **同时启用**，
导致 macOS **完全无法启动**，被迫进 Windows 修复。**元凶未定位**（无法确定是 SSDT、
v7 驱动、还是两者组合）。

**当前组合（v9 驱动 + SSDT 禁用）是稳定的，不要再改动。**

其它禁令：

- ❌ **不要**一次性启用多个未验证的 kext / SSDT —— 出问题无法二分定位
- ❌ **不要**用 PowerShell 的 `[xml]` 改 `config.plist` —— 会把 `<true/>`
  写成非法的 `<true>false</true>`，OpenCore 直接解析失败。**必须改原文文本**
- ✅ 改完必须 `plutil -lint` 验证

性能面板相关详见 [docs/09-EC驱动与性能面板.md](docs/09-EC驱动与性能面板.md)
与 [panel/](panel/)。

---

## 四、改 config.plist 的固定流程

**必须按此顺序**，否则会产出不可引导的配置：

### 1. 备份

```bash
cp EFI/OC/config.plist "EFI/OC/config.plist.bak-<改动说明>-$(date +%Y%m%d-%H%M%S)"
```

命名约定：`config.plist.<备注>-<时间戳>`（与本仓库历史备份一致）。

### 2. 修改

- **只能**用 XML plist 格式读写。写成二进制 plist 会让 `ocvalidate` 报
  `Couldn't parse serialized file`。
- 用 `plistlib`（Python）或直接文本编辑，**不要**用会改编码的工具。
- 不要写 UTF-8 BOM。
- 行尾保持 **LF**（见第七节「文件编码」）。

**Python 正确写法**：

```python
import plistlib
p = "EFI/OC/config.plist"
raw = open(p, "rb").read()
assert not raw.startswith(b"bplist"), "二进制 plist，必须先转 XML"
d = plistlib.loads(raw)
# ... 修改 d ...
out = plistlib.dumps(d, fmt=plistlib.FMT_XML, sort_keys=False)
assert not out.startswith(b"\xef\xbb\xbf")
open(p, "wb").write(out)
```

### 3. 校验（**不可跳过**）

```bash
# 本仓库脚本：结构 + 关键值 + 三码 + 文件存在性
python3 scripts/validate.py EFI/OC/config.plist

# 如果有 ocvalidate 二进制
ocvalidate EFI/OC/config.plist
# 必须输出：No issues found
```

`scripts/validate.py` 退出码：`0` = 通过（可能有 warning），`1` = 有错误，`2` = 用法错误。

### 4. 汇报

改动完成后，向用户报告：

- 改了哪个字段、从什么改成什么
- 备份文件路径（**精确路径**）
- 校验结果
- 如何回滚（具体命令）

---

## 五、常见任务怎么做

### 校验当前配置是否健康

```bash
python3 scripts/validate.py EFI/OC/config.plist
```

关注 9 项关键配置（`ExitBootServicesDelay=3000` 等）与 9 个 boot-args 是否齐全。

### 判断某个改动是否安全

先查 [docs/02-关键配置与踩坑.md](docs/02-关键配置与踩坑.md) 的
**「已证伪清单」**——如果某个做法在表里，直接告诉用户为什么不行。

### 添加 / 更新 kext（仅限使用者本地操作，**不要提交进仓库**）

> ⚠️ 本仓库是纯配置版，`EFI/OC/Kexts/` 不存在是**正常状态**，不是缺失。

使用者本地要做的事：

1. 从 [docs/03-Kext清单.md](docs/03-Kext清单.md) 的上游链接下载 `.kext`，放进 `EFI/OC/Kexts/`
2. 在 `config.plist` → `Kernel → Add` **按加载顺序**插入条目
   （仓库里该数组是空的，需要使用者自己填）
3. **必须**检查依赖顺序（`Lilu.kext` 在所有 Lilu 插件之前；
   `VirtualSMC` 在 `SMCBatteryManager` 之前）
4. 检查 `VoodooInput.kext` 冲突：`VoodooI2C` 与 `VoodooPS2Controller` 各带一份，
   **只能启用一个**（本项目启用 VoodooI2C 那份，PS2 的置 `Enabled=false`）
5. 跑校验

**你可以帮使用者**：说明顺序、排查缺失、解释 `validate.py` 的报错。

**你不要做**：把二进制下载并提交到本仓库。这是刻意的设计决定。

### 准备发布 / 检查是否能公开

```bash
# 1. 三码是否已脱敏
python3 scripts/validate.py EFI/OC/config.plist    # 看 WARN 是否为占位符

# 2. 逐文件确认没有真实序列号
grep -r "C0[0-9A-Z]\{9\}" EFI/OC/config.plist
```

然后读 [docs/04-许可证与归属.md](docs/04-许可证与归属.md)。
**本仓库已是纯配置版，请不要把任何二进制加回来。**

---

## 六、许可证约束（改代码/发布前必读）

> **本仓库是「纯配置版」，不含任何第三方二进制。**
> 下面的表是**使用者自行下载时**要注意的，也是**你如果要把二进制加回来**时必须遵守的。

| 许可证 | 组件 | 约束 |
|---|---|---|
| GPL-3.0-or-later | `YYavicWiFi.kext` | 分发二进制**需提供对应源码**；含 MediaTek 固件（另有条款） |
| GPL-2.0 | `VoodooI2C*`、`VoodooPS2*`、`SimpleMtkBtFw` | 同上 |
| BSD-3-Clause | OpenCore、Lilu、VirtualSMC、WhateverGreen、RestrictEvents、NVMeFix、BrightnessKeys、BlueToolFixup、AMFIPass、USBToolBox、AppleMCEReporterDisabler | 保留版权声明即可 |
| MIT | `ECEnabler` | 保留版权声明 |
| PolyForm Noncommercial | NullMoth NVIDIA 驱动、`NullMothSafe.efi` | ⚠️ **仅限非商业用途**，**不得加入本仓库** |

**AI 助手特别注意**：

- ❌ **不要**把任何 kext / `.efi` 二进制加进本仓库 —— 这是刻意的设计决定，不是遗漏
- ❌ **不要**"为了方便"把 `JiaoLongEC.kext` 之类自制组件加回来（已因失效和风险移除）
- ✅ 使用者需要二进制时，**指向上游 releases 链接**，不要代存

---

## 七、环境与工具

### 运行 `scripts/validate.py` 需要 Python 3

脚本只用标准库（`os` / `sys` / `plistlib`），无第三方依赖。

```bash
python3 scripts/validate.py EFI/OC/config.plist
```

> Windows 上若 `python3` 不在 PATH，用完整路径调用你本机的 `python.exe`。

### 路径约定

| 环境 | EFI 挂载点 |
|---|---|
| macOS | `/Volumes/EFI/EFI/` |
| Windows | 你挂载的 ESP 盘符 + `\EFI\` |
| Linux | `/mnt/efi/EFI/` |

> **不要硬编码盘符**。`F:` / `G:` 在不同机器上会变，脚本里请先探测或用参数传入。

OpenCore 位于 U 盘上时，**开机引导依赖该 U 盘，运行期间不能拔**。

### 文件编码

- 文档：UTF-8
- `config.plist`：UTF-8 **无 BOM**，**LF** 行尾（实测本仓库为裸 LF，2464 行；写入时保持 LF）
- `SHA256SUMS.txt`：UTF-8 无 BOM，格式 `<hash>  <path>`（**两个空格**分隔）
- Shell 脚本：**LF** 行尾，无 BOM（否则 macOS 上会报 `No such file or directory`）
- Python 脚本：UTF-8

### 中文文件名的处理

`docs/` 下 6 份文档使用中文文件名。git / GitHub 完全支持，
但在**某些终端（尤其是旧版 Windows cmd、CI 日志）**里可能显示为乱码或转义序列。

- **引用文件时**，用 Markdown 链接，不要手拼路径
- **脚本里不要硬编码这些中文文件名**，改用 `glob` 或遍历 `docs/*.md`
- 若必须在 shell 里传中文路径，先 `export LANG=zh_CN.UTF-8`（macOS/Linux）
  或 `chcp 65001`（Windows）
- 新增文件时**优先用 ASCII 文件名**，中文只用于已存在的这 6 份文档

**写入前先确认现有行尾，并保持一致**：

```bash
# 检查是否有 CRLF（输出 0 表示纯 LF）
grep -c $'\r' EFI/OC/config.plist
```

> 历史教训 1：带 BOM 的 `.sh` 在 macOS Recovery 里执行会报
> `#!/bin/bash: No such file or directory`。写 shell 脚本时务必确认无 BOM + LF。
>
> 历史教训 2：用 PowerShell 的 `Set-Content -Encoding UTF8` 会**写入 BOM** 并可能改变行尾；
> 在 Windows 上编辑本仓库文件后，务必复查前 3 字节不是 `EF BB BF`。

---

## 八、不要做的事（已证伪，勿重试）

| 做法 | 结果 |
|---|---|
| `npci=0x2000` / `npci=0x3000` | 参数生效但**不解 PCI 卡点**；正解是 `ExitBootServicesDelay=3000` |
| 改 AMFI 去修「安装器损坏」 | 真因是载荷放错（裸 dmg vs 整个 pkg） |
| 拿裸 `SharedSupport.dmg` 当载荷 | 必报 `pkgdmg is missing a footer` |
| Recovery 里 `kmutil create` | 跨卷缺系统 KC 上下文，必然失败 |
| 二进制 plist 写 config | ocvalidate 报 `Couldn't parse serialized file` |
| `-x` 安全模式 | 内核起不来 |
| `ResizeAppleGpuBars = 12` | 该值是 PCI 规范代码，`12` = **4 KiB**，会导致禁止符/瞬断 |
| 把 `ResizeGpuBars` 放 `Booter>Quirks` | 位置错误，应在 `UEFI>Quirks` |
| 给内屏做 HiDPI 自定义分辨率 | 驱动拒绝自定义 framebuffer |
| 移除 `SSDT-EC` 恢复电池 | AppleACPIEC 卡死，启动不完成 |

完整列表见 [docs/02-关键配置与踩坑.md](docs/02-关键配置与踩坑.md) 第七节。

---

## 九、汇报纪律

1. **不要声称完成了未验证的事**。跑过校验就说跑过，没跑就说没跑。
2. **给出可复现的命令**，不要只说"已修改"。
3. 涉及 EFI 修改时，**永远附上回滚方法**。
4. 不确定用户想要什么时，**先问**，不要猜着改 `config.plist`。
5. 引用外部结论时**给出链接**（见 [docs/06-参考文献.md](docs/06-参考文献.md)）；
   不要把别人的方案说成自己的原创。

---

## 十、快速自检清单

修改前：

- [ ] 我读过节二列出的 5 份文档了吗？
- [ ] 我的改动是否撞上第三节的红线？
- [ ] 我是否要碰磁盘分区？（是 → 必须先向用户确认）
- [ ] 我是否在动 kext？（是 → 检查许可证与加载顺序）

修改后：

- [ ] 备份文件已生成，路径已记录
- [ ] `scripts/validate.py` 退出码为 0
- [ ] `Kernel > Add` / `ACPI > Add` 引用的文件都真实存在
- [ ] 三码仍是占位符（若要提交）
- [ ] 已向用户报告改动内容 + 回滚命令

---

## 十一、注意事项（待补充）

> **状态：占位章节，内容待定。**
> 作者会在此补充额外注意事项。AI 助手读到本节时：
> **不要自行填充内容**，也不要把它当作空章节删除。
> 当用户向你提出某个设想时，务必先进行分析，将无法理解或存在歧义的问题向用户提出，而不是直接执行。

<!-- 预留区开始 —— 以下条目待作者填写 -->

<!--
建议可按以下类别组织（待作者确认后再启用）：

### 11.1 已知不稳定的行为

### 11.2 特定操作顺序要求

### 11.3 与其他工具/环境的冲突

### 11.4 用户个人偏好与工作流约定

### 11.5 排查线索（日志位置、常见误报）
-->

<!-- 预留区结束 -->
