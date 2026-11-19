# Kext 清单与获取方式

> ## ⚠️ 本仓库是「纯配置版」，不含任何 kext 二进制
>
> 下面这张表是**你需要在本地自行准备**的清单。放入 `EFI/OC/Kexts/` 后，
> 还要按**同样的顺序**在 `config.plist → Kernel → Add` 里逐条登记（仓库里该字段是空的）。
>
> **为什么不含二进制**：GPL 组件（YYavicWiFi / VoodooI2C / VoodooPS2）要求随附源码，
> NullMoth 驱动是 PolyForm 非商业许可 —— 打包分发风险大、收益小，
> 而这些都是上游现成且持续更新的。

本 EFI 需要 **21 个 kext**（`Kernel → Add` 共 28 条，含 7 个 PlugIns 条目）。

## 主 Kext（`Kernel → Add` 顺序即加载顺序）

> **完整条目定义**（含 `ExecutablePath` / `PlistPath` / `Enabled`）已导出为
> [kernel-add-reference.json](kernel-add-reference.json)，可直接参考。
> 仓库里 `config.plist` 的 `Kernel → Add` 是**空数组**（纯配置版）。

| # | 名称 | 版本 | Bundle ID | 作用 | 下载来源 | 许可证 |
|---|---|---|---|---|---|---|
| 1 | `Lilu.kext` | 1.7.3 | `as.vit9696.Lilu` | 补丁内核框架，多数 kext 的依赖 | [acidanthera/Lilu](https://github.com/acidanthera/Lilu/releases) | BSD-3-Clause |
| 2 | `VoodooHDA_BL.kext` | 3.7.1 | `org.voodoo.driver.VoodooHDA` | **内置声卡**（macOS 26 唯一可行方案，见 [docs/08](08-内置声卡修复.md)） | [CloverHackyColor/VoodooHDA](https://github.com/CloverHackyColor/VoodooHDA) | GPL-2.0 |
| 3 | `YYavicWiFi.kext` | 0.8.0 | `com.yyavic.WiFi` | **MT7922 原生 Wi-Fi** | [yusufcanyavic/YYavicWiFi](https://github.com/yusufcanyavic/YYavicWiFi/releases) | **GPL-3.0-or-later** |
| 4 | `AMFIPass.kext` | 1.4.1 | `com.dhinakg.AMFIPass` | 在 AMFI 开启状态下放行第三方 kext | [dhinakg/AMFIPass](https://github.com/dhinakg/AMFIPass/releases) | BSD-3-Clause |
| 5 | `AppleMCEReporterDisabler.kext` | 1.2 | `org.xlnc.disabler.MCEReporter` | 禁用 `AppleMCEReporter`，防 AMD 平台 panic | [acidanthera/bugtracker](https://github.com/acidanthera/bugtracker) | BSD-3-Clause |
| 6 | `BlueToolFixup.kext` | 2.7.3 | `as.acidanthera.BlueToolFixup` | 修复非 Broadcom 蓝牙在 macOS 12+ 的加载 | [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM/releases) | BSD-3-Clause |
| 7 | `BrightnessKeys.kext` | 1.0.4 | `as.acidanthera.BrightnessKeys` | Fn 亮度键映射（⚠️ **本机 Fn 键无效，此 kext 实际未起作用**，但保留无害） | [acidanthera/BrightnessKeys](https://github.com/acidanthera/BrightnessKeys/releases) | BSD-3-Clause |
| 8 | `ECEnabler.kext` | 1.0.6 | `com.1Revenger1.ECEnabler` | 支持读取超 8 位的 EC 字段 | [1Revenger1/ECEnabler](https://github.com/1Revenger1/ECEnabler/releases) | MIT |
| 9 | `NVMeFix.kext` | 1.1.4 | `org.acidanthera.NVMeFix` | NVMe 电源管理与兼容性修复 | [acidanthera/NVMeFix](https://github.com/acidanthera/NVMeFix/releases) | BSD-3-Clause |
| 10 | `RestrictEvents.kext` | 1.1.7 | `as.vit9696.RestrictEvents` | 屏蔽不兼容提示、配合 `revpatch=sbvmm` | [acidanthera/RestrictEvents](https://github.com/acidanthera/RestrictEvents/releases) | BSD-3-Clause |
| 11 | `VirtualSMC.kext` | 1.3.9 | `as.vit9696.VirtualSMC` | **必需**，模拟 SMC 芯片 | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC/releases) | BSD-3-Clause |
| 12 | `SMCBatteryManager.kext` | 1.3.9 | `ru.usrsse2.SMCBatteryManager` | 电池信息（本机受 EC 隐藏影响，无百分比） | VirtualSMC 包内插件 | BSD-3-Clause |
| 13 | `SMCLightSensor.kext` | 1.3.9 | `ru.usrsse2.SMCLightSensor` | 环境光传感器 | VirtualSMC 包内插件 | BSD-3-Clause |
| 14 | `SimpleMtkBtFw.kext` | 1.0.0 | `com.laobamac.SimpleMtkBtFw` | MediaTek 蓝牙固件加载（**实测可配对连接**，可用性未验证） | [laobamac/SimpleMtkWlan](https://github.com/laobamac/SimpleMtkWlan) | GPL-2.0 |
| 15 | `USBToolBox.kext` | 1.2.0 | `com.dhinakg.USBToolBox.kext` | USB 端口映射框架 | [USBToolBox/kext](https://github.com/USBToolBox/kext/releases) | BSD-3-Clause |
| 16 | `UTBDefault.kext` | 1.0 | `com.dhinakg.USBToolBox.injector` | USB 默认端口注入 | USBToolBox 包内 | BSD-3-Clause |
| 17 | `VoodooI2C.kext` | 2.9.1 | `com.alexandred.VoodooI2C` | **触控板**（I2C HID） | [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C/releases) | GPL-2.0 |
| 18 | `VoodooI2CHID.kext` | 1 | `com.alexandred.VoodooI2CHID` | I2C HID 设备支持 | VoodooI2C 包内 | GPL-2.0 |
| 19 | `VoodooPS2Controller.kext` | 2.3.8 | `as.acidanthera.voodoo.driver.PS2Controller` | **内建键盘**（PS/2） | [acidanthera/VoodooPS2](https://github.com/acidanthera/VoodooPS2/releases) | GPL-2.0 |
| 20 | `WhateverGreen.kext` | 1.7.2 | `as.vit9696.WhateverGreen` | 显卡补丁框架 | [acidanthera/WhateverGreen](https://github.com/acidanthera/WhateverGreen/releases) | BSD-3-Clause |
| 21 | `MechrevoEC.kext` | v9 | `com.local.MechrevoEC` | **性能监控**（只读 EC 采样，见 [panel/](../panel/)） | **本仓库自研**（源码在 [panel/kext/](../panel/kext/)） | MIT |

> ### 🔊 关于 `VoodooHDA_BL.kext` 的两个关键点
>
> **1. 必须用 BL 版**。稳定版 3.6.8 依赖外部 `IOAudioFamily`，从 Big Sur 起
> 直接 EFI 注入会报 `Invalid Parameter`。BL 版内嵌了 IOAudioFamily。
>
> **2. 必须改 `IONameMatch`**。原值 `"HDAS"` 改为 `["AZAL", "pci1022,15e3"]`，
> 只匹配本机声卡，不碰 NVIDIA HDMI 声卡。**不改则驱动不会加载。**
>
> 完整说明见 [docs/08-内置声卡修复.md](08-内置声卡修复.md)。

> **关于 NullMoth NVIDIA 驱动**：`NVRM` / `NVAccel` / `NVRMFB` 等**不在这张表里**，
> 因为它们不是 OpenCore 注入的 kext，而是装进 `/Library/Extensions` 的系统级驱动。
> 请从 [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver/releases) 下载后
> 在 macOS 里运行其 `install.sh`。**这是显卡能工作的前提。**

## PlugIns（由父 kext 携带，`Kernel → Add` 也需单独登记）

| 名称 | 父 kext | 说明 |
|---|---|---|
| `VoodooInput.kext` | VoodooI2C | 输入设备抽象层（**只启用这一个**） |
| `VoodooGPIO.kext` | VoodooI2C | GPIO 控制器 |
| `VoodooI2CServices.kext` | VoodooI2C | 服务层 |
| `VoodooInput.kext` | VoodooPS2Controller | **已禁用**（与上者冲突） |
| `VoodooPS2Keyboard.kext` | VoodooPS2Controller | PS/2 键盘 |
| `VoodooPS2Mouse.kext` | VoodooPS2Controller | PS/2 鼠标 |
| `VoodooPS2Trackpad.kext` | VoodooPS2Controller | PS/2 触控板 |

> ⚠️ **`VoodooInput` 冲突**：`VoodooI2C` 和 `VoodooPS2Controller` 各带一份，
> **只能启用一个**。本机启用的是 VoodooI2C 那份，PS2 的置 `Enabled=false`。

### 如何把它们加入 `Kernel → Add`

仓库里 `Kernel → Add` 是**空数组**。你需要为每个 kext 加一条 dict，顺序严格如下
（`Lilu` 必须在所有 Lilu 插件前，`VirtualSMC` 必须在 SMC 插件前）：

```xml
<dict>
    <key>Arch</key><string>Any</string>
    <key>BundlePath</key><string>Lilu.kext</string>
    <key>Comment</key><string>Lilu</string>
    <key>Enabled</key><true/>
    <key>ExecutablePath</key><string>Contents/MacOS/Lilu</string>
    <key>MaxKernel</key><string></string>
    <key>MinKernel</key><string></string>
    <key>PlistPath</key><string>Contents/Info.plist</string>
</dict>
```

> **PlugIns 的写法**：`BundlePath` 用相对父 kext 的完整路径，例如
> `VoodooI2C.kext/Contents/PlugIns/VoodooGPIO.kext`，
> `ExecutablePath` 为 `Contents/MacOS/VoodooGPIO`。
>
> **两个例外**：`SMCBatteryManager` / `SMCLightSensor` 顶层没有可执行文件，
> 它们的 `ExecutablePath` 留空字符串 `<string></string>`。
>
> 最简单的做法：参考 `EFI-分发包`（若你有）或任一现成 EFI，
> 用 [OCAT](https://github.com/ic005k/OCAuxiliaryTools) 图形化添加。

---

## 非 Kext 组件（不在本仓库，需自行获取）

| 组件 | 来源 | 说明 |
|---|---|---|
| `OpenCore.efi` / `BOOTx64.efi` | [OpenCorePkg releases](https://github.com/acidanthera/OpenCorePkg/releases) | 本机用的是 DBG-109（1.0.9 dev）；用官方最新 release 亦可 |
| `apfs_aligned.efi` | OpenCorePkg `Utilities/` | APFS 驱动（对齐版），**macOS 12+ 必需** |
| `HfsPlus.efi` | OpenCorePkg `Drivers/` | HFS+ 读取（从 HFS 卷启动时需要） |
| `OpenCanopy.efi` | OpenCorePkg `Drivers/` | 图形开机菜单（可选，需要 `Resources/` 主题） |
| `OpenRuntime.efi` | OpenCorePkg `Drivers/` | **必需**，OpenCore 运行时服务 |
| `ResetNvramEntry.efi` | OpenCorePkg `Drivers/` | 菜单里提供 Reset NVRAM 项（强烈建议） |

> 本机 `Misc → Boot → PickerMode` 已设为 **`Builtin`**（纯文本菜单），
> 因为仓库不含 `Resources/` 主题资源。
>
> ⚠️ **重要**：如果你从本机 U 盘复制 `config.plist` 过来，它的 `PickerMode` 是
> `External`（因为 U 盘上有 `Resources/`）。**直接拿去用在没有 Resources 的 EFI 上，
> OpenCore 开机菜单会失败**（黑屏或直接跳到默认项）。
>
> 两种解决办法：
> - 保持 `Builtin`（简单，纯文本菜单）
> - 或从 OpenCorePkg 复制 `Resources/` 到 `EFI/OC/Resources/`，并用 `External`
>
> 想要图形菜单：从 [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg/releases) 的
> `X64/EFI/OC/Resources/` 复制整个目录过来，再把 `PickerMode` 改成 `External`。

---

## ACPI（7 个 SSDT，**本仓库提供**）

| 文件 | 作用 |
|---|---|
| `SSDT-ALIBFix.aml` | **ALIB→XLIB 重命名**，解决部分 PCI configuration 卡死 |
| `SSDT-EC.aml` | 伪造 Apple EC（同时隐藏真实 EC，导致无电池百分比） |
| `SSDT-PLUG-ALT.aml` | CPU 电源管理 |
| `SSDT-USB-Reset.aml` | USB 复位 |
| `SSDT-USBX.aml` | USB 供电属性 |
| `SSDT-XOSI.aml` | 操作系统检测兼容层 |
| `SSDT-Disable_Network_GPP5.aml` | 禁用无驱动的 YT6801 有线网卡 |

---

## 关于许可证

本仓库**不包含任何第三方二进制**，因此不涉及 GPL 源码附带义务，
也不涉及 NullMoth 的 PolyForm 非商业限制。

**你自行下载的 kext 由你自行承担许可合规**。下载时请注意：

| 许可证类型 | 组件 | 你的义务 |
|---|---|---|
| GPL-3.0-or-later | `YYavicWiFi` | 再分发时需提供源码 |
| GPL-2.0 | `VoodooI2C*`、`VoodooPS2*`、`SimpleMtkBtFw` | 同上 |
| BSD-3-Clause | OpenCore、Lilu、VirtualSMC、WhateverGreen、RestrictEvents、NVMeFix、BrightnessKeys、BlueToolFixup、AMFIPass、USBToolBox | 保留版权声明 |
| MIT | `ECEnabler` | 保留版权声明 |
| PolyForm Noncommercial | NullMoth NVIDIA 驱动（装进 `/Library/Extensions`，不进 EFI） | **仅限非商业个人使用** |

### 关于 `JiaoLongEC.kext`

曾经有一份自制 `JiaoLongEC.kext`（`com.nullmoth.JiaoLongEC` 0.3.0）在本 EFI 中被尝试过，
**现已从本仓库移除**，原因：

1. 它是实验性自制代码，**从未生效过** —— 数轮修改后依然没有带来任何可观察的变化；
2. 它做的是 **EC 解锁 + 风扇转速钳制 + PL1 功耗墙切换**，需要配套用户态 App 才能真正使用，
   而那个 App 从未被写出来；
3. 它包含解除 EC 写保护的操作（`EC unlocked`），存在风扇失控风险；
4. Bundle ID 冒用了 `com.nullmoth.` 前缀，但它**不是** NullMoth 官方组件，容易误导他人。

> 如果你也想做风扇/功耗控制，建议不要从零写 kext，而是先看看
> NullMoth 官方是否已提供相关功能，或使用 `SMCAMDProcessor` 这类成熟方案。
> **直接操作 EC 是有风险的动作。**
