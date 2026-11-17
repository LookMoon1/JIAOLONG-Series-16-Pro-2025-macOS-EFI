# MECHREVO JIAOLONG · macOS 26 Tahoe OpenCore EFI

[![macOS](https://img.shields.io/badge/macOS-26.7.3%20Tahoe-000000?logo=apple&logoColor=white)](#)
[![OpenCore](https://img.shields.io/badge/OpenCore-DBG--109--2026--11--08-blue)](#)
[![CPU](https://img.shields.io/badge/CPU-Ryzen%209%209955HX-E2231A?logo=amd&logoColor=white)](#)
[![GPU](https://img.shields.io/badge/GPU-RTX%205060%20Laptop-76B900?logo=nvidia&logoColor=white)](#)

一台 **AMD Ryzen 9 9955HX + NVIDIA RTX 5060 Laptop（MUX 独显直连）** 的机械革命蛟龙 16 Pro 潮玩版，
通过 [NullMoth 1401](https://github.com/nullmoth/1401) + [NullMoth NVIDIA 驱动](https://github.com/nullmoth/nvidia-macos-driver)
跑上 **macOS 26 Tahoe** 的完整 OpenCore EFI。

> **English**: A working OpenCore EFI for macOS 26 Tahoe on a MECHREVO JIAOLONG 16 Pro
> (AMD Ryzen 9 9955HX, NVIDIA RTX 5060 Laptop, MUX-direct internal panel).
> Graphics, internal keyboard/trackpad, and native Wi-Fi (MediaTek MT7922) all work.
> See [docs/01-硬件与兼容性.md](docs/01-硬件与兼容性.md) for the full status table.

---

> ## ⚠️ 使用前必读：Fn 键会导致系统重启
>
> 这是本 EFI **已知的、尚未修复**的缺陷，不是你的配置装错了：
>
> | 操作 | 结果 |
> |---|---|
> | 单独按 **Fn** | ❌ 无任何反应 |
> | **Fn + F 功能区按键**（Fn+F1…F12） | 🔴 **整机直接重启** |
> | 单独按 F1–F12 | ✅ 正常 |
>
> **日常使用请避开 Fn 组合键。** 调亮度用控制中心/菜单栏滑块（这个是可用的）。
> 排查记录与已排除项见 [docs/02-关键配置与踩坑.md](docs/02-关键配置与踩坑.md) 第四节之二。

---

## 当前状态

| 功能 | 状态 | 说明 |
|---|---|---|
| **内置硬盘引导** | ✅ | **无需 U 盘**，已改 BIOS `Hard Drive BBS Priorities`（见 docs/07） |
| 系统启动 | ✅ | macOS 26.7.3 (25G342)，正常进桌面 |
| 显卡 / Metal | ✅ | RTX 5060 Laptop 8 GB，NullMoth 驱动，内屏正常点亮 |
| 内建键盘 | ✅ | PS/2，VoodooPS2Controller |
| 触控板 | ✅ | I2C HID，VoodooI2C + `-vi2c-force-polling` |
| **Wi-Fi** | ✅ | **MT7922 原生驱动，YYavicWiFi 0.8.0 + `-yyavicnoverify`** |
| **内置声卡** | ✅ | **VoodooHDA 3.7.1 BL 版**；扬声器 / 耳机孔 / 麦克风均可用（见 docs/08） |
| 亮度调节 | ✅ | `nvrmacpibl=1`，**控制中心滑块可用** |
| **Fn 键** | 🔴 | **单独按无反应；Fn + F 功能区按键会导致系统重启。未修复，见上方警告** |
| USB | ✅ | USBToolBox + UTBDefault |
| Windows 双启动 | ✅ | OC 菜单自动列出 Windows Boot Manager |
| 睡眠 / 唤醒 | ⚠️ | 未系统验证 |
| 蓝牙 | ⚠️ | 可正确连接设备，但未验证可用性 |
| 有线网口 | ❌ | Motorcomm YT6801，无 macOS 驱动 |
| 电池百分比 | ❌ | SSDT-EC 隐藏了真实 EC |

---

## 硬件

| 项 | 值 |
|---|---|
| 机型 | MECHREVO JIAOLONG 系列（蛟龙 16 Pro 潮玩版 2025） |
| BIOS | AMI `N.1.15MRO19`，无 Above 4G Decoding / Resizable BAR 选项 |
| CPU | AMD Ryzen 9 9955HX（Granite Ridge / Zen5，16C/32T） |
| 独显 | NVIDIA RTX 5060 Laptop `10DE:2D19`，**内屏 MUX 直连** |
| 核显 | AMD Radeon 610M `1002:13C0`（macOS 无驱动，已 `disable-gpu`） |
| 内屏 | NE160QDM-NZL 2560×1600 eDP |
| 内存 | 32 GB DDR5（≥16 GB 即可） |
| 存储 | NVMe SSD，单盘 GPT |
| 无线 | MediaTek MT7922 `14C3:7922`（Wi-Fi 6E，现已有驱动） |
| 有线 | Motorcomm YT6801（无驱动） |
| 声卡 | Senary SN6140 `14F1:1F87` + NVIDIA HDA `10DE:00AD` |


---

## 快速开始

### 0. 在开始之前请先确定你的设备是否与本仓库一致

如果在硬件上存在差别，那么请务必不要直接复用任何内容，仅供参考。

### 1. 生成你自己的三码（**必做**）

本仓库的 `EFI/OC/config.plist` **已脱敏**，`MLB` / `SystemSerialNumber` / `SystemUUID` / `ROM`
都是占位符。直接拿去用会导致 iCloud / iMessage / App Store 异常。

用 [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) 或 [OCAT](https://github.com/ic005k/OCAuxiliaryTools)
为 **`MacBookPro16,2`** 生成一套三码，填入 `PlatformInfo → Generic`：

```xml
<key>SystemProductName</key><string>MacBookPro16,2</string>
<key>SystemSerialNumber</key><string>你的序列号</string>
<key>MLB</key>            <string>你的MLB</string>
<key>SystemUUID</key>     <string>你的UUID</string>
<key>ROM</key>            <data>你的网卡MAC（6字节）</data>
```

### 2. 校验配置

```bash
# macOS / Linux
./scripts/validate.sh /Volumes/EFI/EFI/OC/config.plist
```

或手动用 `ocvalidate`（本仓库 config 已通过 `No issues found`）。

### 3. 挂载 EFI 分区并替换

把本仓库的 `EFI/` 整个目录覆盖到你的 ESP（EFI 系统分区）根目录，**保留你自己的三码**。

### 4. BIOS 设置

- **Secure Boot → Disabled**（必需，其余设置保持默认，同类机型一般在开机时按F2进入BIOS内）

---

## 关键配置说明

这些值是这个 EFI 能跑起来的原因，**改动前请先读 [docs/02-关键配置与踩坑.md](docs/02-关键配置与踩坑.md)**。

| 配置 | 值 | 为什么 |
|---|---|---|
| `UEFI → Quirks → ExitBootServicesDelay` | **3000** | 突破 AMD 平台 PCI configuration 卡死，**最关键的一条**（见下方说明） |
| `Booter → Quirks → ProtectUefiServices` | **true** | 同上，配合使用 |
| `Booter → Quirks → DevirtualiseMmio` | true | AMD Zen4/Zen5 内存映射必需 |
| `Booter → Quirks → DisableVariableWrite` | true | 防止 macOS 写 NVRAM 导致主板不开机 |
| `Kernel → Block` | `com.apple.iokit.IONDRVSupport` | 防止 boot framebuffer 抢占 NVRMFB 的显示索引 |
| `SMBIOS` | `MacBookPro16,2` | 与同配置成功案例（天选 7Pro）一致 |
| `csr-active-config` | `0x0A43` | NullMoth 驱动与 AMFIPass 需要 |
| `SecureBootModel` | `Disabled` | OpenCore 侧安全启动关闭 |

> ### 🎯 开机卡死是怎么修好的（关键说明）
>
> 本机安装时卡在 `pci (build ...), flags 0xc3080`，**1401**仓库中提到的`npci=0x2000 / 0x3000` 全部无效
> （日志证明参数生效了，但卡点不动），BIOS 也没有 Above 4G Decoding 选项。
>
> **该卡点的修复方案基于同配置成功案例实现：**
>
> **→ [VisualTechStudio/ASUS-TX-Gaming-7Pro-Ryzen-CN-OpenCore-EFI](https://github.com/VisualTechStudio/ASUS-TX-Gaming-7Pro-Ryzen-CN-OpenCore-EFI)**
>
> 那台机器的 CPU（Ryzen 9 9955HX）与独显（RTX 5060 Laptop）**与本机完全相同**。
> 照抄其两项配置后一次启动即通过：
>
> | 配置 | 天选 7Pro | 1401 默认 | 本 EFI |
> |---|---|---|---|
> | `ExitBootServicesDelay` | **3000** | 0 | **3000** |
> | `ProtectUefiServices` | **True** | False | **True** |
>
> 完整来源说明与其它引用见 **[docs/06-参考文献.md](docs/06-参考文献.md)**。

### boot-args

```
-v debug=0x100 keepsyms=1 -amfipassbeta -vi2c-force-polling revpatch=sbvmm
nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1
amfi=0x80 ipc_control_port_options=0 gfxrst=4
nvrmacpibl=1 yyavic-cc=CN -yyavicnoverify
```

| 参数 | 作用 |
|---|---|
| `nvfb=1 nvaccel=1 nvfbheads=4 gfxrst=4` | NullMoth NVIDIA 驱动 |
| `nvrmacpibl=1` | **开启内屏亮度**（仅滑块，**Fn 键不可用**） |
| `-vi2c-force-polling` | 触控板改轮询，绕开 GPIO 中断问题 |
| `yyavic-cc=CN` | Wi-Fi 国家码（决定可用信道） |
| `-yyavicnoverify` | **跳过 YYavicWiFi 的 macOS build 检查，见下方警告** |
| `amfi=0x80 amfi_get_out_of_my_way=0x1` | **必需**，NullMoth 驱动依赖 |
| `revpatch=sbvmm` | Tahoe 安全启动型号检查绕过 |

> ⚠️ **`-yyavicnoverify` 有风险**：YYavicWiFi 0.8.0 的 macOS 26 原生层是针对
> **26.7.2 (25G332)** 编译的，本机是 **26.7.3 (25G342)**。二者 IO80211/Skywalk 布局目前一致，
> 所以可以工作；但**系统更新后可能变化**。更新前请先备份 EFI，并确认有新 build 对应的 kext。

---

---

## 📦 本仓库是「纯配置版」

**本仓库只包含配置，不含任何第三方二进制。** 这是刻意的设计决定：

| 包含 | 不包含 |
|---|---|
| ✅ `config.plist`（已脱敏） | ❌ kext 二进制（GPL/专有许可，且全是上游现成的） |
| ✅ 7 个 ACPI SSDT | ❌ OpenCore.efi / Drivers（请用官方 release） |
| ✅ 完整文档与踩坑记录 | ❌ 开机主题资源（可选功能，占 3.4 MB） |

**理由**：

1. **许可证**：`YYavicWiFi`（GPL-3.0）、`VoodooI2C`/`VoodooPS2`（GPL-2.0）要求随附源码；
   `NullMoth` 驱动是 **PolyForm 非商业许可**，不允许商业再分发。放二进制风险大、收益小。
2. **时效性**：这些 kext 全都能从上游 `git clone` 或 releases 拿到最新版，
   打包固定反而会让人用旧版。
3. **体积**：14.68 MB → **约 1.9 MB**，克隆快、diff 干净。

**你需要自己准备**：OpenCore 引导器 + 各 kext。清单与下载链接见
[docs/03-Kext清单.md](docs/03-Kext清单.md)。

---

## 目录结构

```
EFI/
├── BOOT/
│   └── BOOTx64.efi              ← 需从 OpenCorePkg 官方 release 获取
└── OC/
    ├── OpenCore.efi             ← 同上
    ├── config.plist             ★ 本仓库核心（已脱敏，需填入三码）
    ├── ACPI/                    7 个 SSDT（本仓库提供）
    ├── Drivers/                 5 个 UEFI 驱动（需从 OpenCorePkg 获取）
    ├── Kexts/                   ⚠️ 空 —— 需自行下载（见 docs/03）
    ├── Resources/               ⚠️ 不含 —— 开关机主题，可选
    └── Tools/                   ⚠️ 不含 —— OpenShell 等调试工具，可选
```

> `Kernel → Add` 在仓库里是**空的**。放入 kext 后按
> [docs/03-Kext清单.md](docs/03-Kext清单.md) 列出的顺序逐条添加。

各 kext 的版本、来源与许可证见 [docs/03-Kext清单.md](docs/03-Kext清单.md)。

---

## 许可证与致谢

本仓库分发的 EFI **配置与 ACPI 表**为本人整理；**各个 kext 与 OpenCore 本体版权归各自作者**，
均按其原始开源许可证分发（GPL-3.0 / GPL-2.0 / BSD-3-Clause / Apache-2.0 混合）。

**请勿二次分发本仓库的 kext 二进制而移除其许可证文件。** 详细归属见
[docs/04-许可证与归属.md](docs/04-许可证与归属.md)。

### 特别感谢

- [NullMoth](https://github.com/nullmoth) — 1401 与 NVIDIA macOS 驱动
- [Yusufcan Yavic](https://github.com/yusufcanyavic/YYavicWiFi) — MT7922 原生 Wi-Fi 驱动
- [acidanthera](https://github.com/acidanthera) — OpenCore、Lilu、VirtualSMC、WhateverGreen 等
- [laobamac](https://github.com/laobamac) — SimpleMtkWlan / SimpleMtkBtFw
- **[VisualTechStudio](https://github.com/VisualTechStudio/ASUS-TX-Gaming-7Pro-Ryzen-CN-OpenCore-EFI) — 同配置（9955HX + RTX 5060）参考 EFI，本项目开机卡死的修复方案来源**
- [gqm321](https://github.com/gqm321/macos15-rtx5070-jiaolong) — 同机型（蛟龙 7845HX + RTX 5070）参考
- [Dhinak G.](https://github.com/dhinakg) — AMFIPass、USBToolBox

> 完整的引用来源、许可证归属与二次开发建议见
> **[docs/06-参考文献.md](docs/06-参考文献.md)**。

---

## 免责声明

本仓库仅供技术研究与学习交流，
使用者需自行承担全部风险，包括但不限于数据丢失、硬件损坏、系统无法启动及授权合规问题。
**刷写 EFI 前请务必备份原有 ESP 与全部重要数据。**
