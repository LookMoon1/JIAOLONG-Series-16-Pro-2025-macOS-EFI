# 机械革命蛟龙 16 Pro · macOS 只读性能面板

> 给黑苹果环境（macOS 26.7.3 / 25G342，R9-9955HX + RTX 5060 Laptop）做的
> 机械革命控制中心（MGIC）**只读**替代品。

**全程只读**：不写任何硬件寄存器、不接管风扇、不切换档位。
档位仍由笔记本自带的物理性能键切换。

---

## 📁 目录结构

```text
panel/
├── kext/                  只读 EC 采样驱动
│   ├── MechrevoEC.cpp     源码（v9）
│   ├── Info.plist         驱动描述（com.local.MechrevoEC）
│   └── build.sh           构建脚本（仅需 Command Line Tools）
├── app/                   性能面板 App（常规窗口）
│   ├── main.swift
│   ├── Info.plist
│   └── build.sh
├── widget/                桌面组件（桌面图层悬浮窗）
│   ├── main.swift
│   ├── Info.plist
│   └── build.sh
└── tools/
    ├── ecdump.c           命令行采样工具
    └── watch.sh           连续观察寄存器变化
```

**本仓库只含源码，不含编译产物**（`.app` / `.kext` 二进制）。
为什么这样做，见仓库 [docs/04-许可证与归属.md](../docs/04-许可证与归属.md) 的纯配置版说明。

---

## 🎯 它是什么

Windows 版 MGIC 的驱动栈**搬不到 macOS**（见 [为什么](#-为什么不能移植-mgic)），
所以这里是一套自建的只读数据通道：

```text
EC 共享内存窗口 0xFED50000
        ↓  MechrevoEC.kext 每 1.5 秒只读采样
IORegistry 属性（FanMap / MidMap / HighMap / IPCMap / Seq / Failures）
        ↓
面板 App / 桌面组件（纯读取展示）
```

### 面板显示内容

性能档位徽章、CPU 负载、内存占用、CPU / GPU 温度、风扇档位、
GPU 利用率、显存占用、CPU 温度趋势（近 2 分钟）、电量供电、采样状态。

---

## 🔧 编译

### 驱动（`kext/`）

```bash
cd panel/kext
./build.sh
```

产物：`panel/kext/MechrevoEC.kext`

**仅需 Command Line Tools**，不需要完整 Xcode。

### 面板 App（`app/`）

```bash
cd panel/app
./build.sh
```

产物：`机械革命性能面板.app`

### 桌面组件（`widget/`）

```bash
cd panel/widget
./build.sh
```

产物：`机械革命桌面组件.app`

---

## 📦 部署

### 1. 安装驱动

把 `MechrevoEC.kext` 放进**两份 EFI**（U 盘 + 内置盘）的 `EFI/OC/Kexts/`，
然后在 `config.plist` 的 `Kernel → Add` 末尾追加：

```xml
<dict>
    <key>Arch</key><string>Any</string>
    <key>BundlePath</key><string>MechrevoEC.kext</string>
    <key>Comment</key><string>Mechrevo EC read-only sampler</string>
    <key>Enabled</key><true/>
    <key>ExecutablePath</key><string>Contents/MacOS/MechrevoEC</string>
    <key>MaxKernel</key><string></string>
    <key>MinKernel</key><string></string>
    <key>PlistPath</key><string>Contents/Info.plist</string>
</dict>
```

**重启生效**。`kmutil load -z` 只会返回 `requires a reboot`，热加载不可用。

### 2. 验证驱动

```bash
ioreg -c MechrevoEC -r -d 1 | grep -E "ProbeOK|Failures|Seq"
```

期望：`ProbeOK = Yes`、`Failures = 0`、`Seq` 每 1.5 秒递增。

### 3. 运行面板

```bash
open 机械革命性能面板.app
open 机械革命桌面组件.app
```

桌面组件：拖动摆位（位置会被记住），右键可「立即刷新」或「退出」。

---

## ❓ 为什么不能移植 MGIC

机器是 **Uniwill（同方 / 志奥）** 方案：

| 事实 | 影响 |
|---|---|
| `INOU0000` 提供 `ECRR` / `ECRW`，读写 `0xFED50000` eSPI 窗口 | **不是**标准 EC 端口 `0x62`/`0x66`，通用 EC 驱动读不到 |
| `EC0`（`PNP0C09`）是真实 EC，`SSDT-EC` 已把它隐藏 | 强行读实存**曾导致开不了机**（见[风险](#-已知限制与风险)） |
| SMC 里没有风扇键，也没有 `SMCAMDProcessor` | 第三方风扇控制方案无接口可用 |

**结论**：MGIC 的 Windows 驱动栈（WMI + EC 私有命令）无法整套搬过来。
可行路线是自建只读通道，也就是本方案。

---

## 📊 已实测的寄存器语义

全部经现场实测对拍，**不是猜的**。

| 地址 | 含义 | 实测证据 |
|---|---|---|
| `0x461` | **当前性能档位**（持久，按键切换才变） | 100 / 126 / 200 三点与用户操作逐一对应 |
| `0x469` | 档位镜像值（与 `0x461` 恒等） | 同步变化 |
| `0x449` | **CPU 温度（℃）** | 空闲 47 → 满载 56 → 回落 49 |
| `0x44F` | **GPU 温度（℃）**（DSDT 命名 `VGAT`） | 恒 79–82；本机 5060 在 macOS 下无电源管理 |
| `0xD8` | 风扇档位（0–7） | 换档随动，负载下 1 → 6 |
| `0x43E` | 温度限值（**恒定值，不是实时温度**） | 全程 91–92，不随负载变化 |

### 档位映射（已逐档确认）

| `0x461` 值 | 档位 |
|---|---|
| 100 | 办公 |
| 126 | 均衡 |
| 200 | 狂暴 |

按键循环顺序：**均衡（126）→ 办公（100）→ 狂暴（200）**

> Windows 下顺序是 办公 → 均衡 → 狂暴，macOS 下前两档对调，
> 属 **EC 固件行为**，与软件无关。

### 显卡数据（不依赖自研驱动）

来自系统原生接口，非 EC：

| 项目 | 字段来源 |
|---|---|
| 显存总量 | `VRAM,totalsize`（IOPCIDevice） |
| 已用显存 | `inUseVidMemoryBytes`（NVAccel） |
| 显存占用率 | `GPU Memory Utilization %`（NVAccel） |
| GPU 核心利用率 | `GPU Core Utilization %`（NVAccel） |

> ⚠️ 这几个属性在 `ioreg` 里是**紧凑写法**（`"键"=值`，等号两边无空格），
> 解析时不能按 `"键" = 值` 匹配。

---

## ⚙️ 驱动工作原理

`MechrevoEC.kext`（`com.local.MechrevoEC`）匹配 `INOU0000` 设备：

1. `start()` 里先用 `ECRR(0x00)` 探活，结果写入 `ProbeOK` / `ProbeStatus`
2. 挂 `IOTimerEventSource`，每 **1500ms** 采一轮
3. 每轮读四段窗口，发布为 `OSData` 属性：

| 属性 | 地址范围 | 内容 |
|---|---|---|
| `FanMap` | `0x0D0`–`0x0DF` | 风扇占空比 / 风扇档位 |
| `MidMap` | `0x430`–`0x4AF` | 温度 / 风扇表 / 功率 |
| `HighMap` | `0x700`–`0x7FF` | 电量 / 功耗墙 / 性能字段 |
| `IPCMap` | `0xEA0`–`0xECF` | OEM IPC 命令块 |

4. 每轮发布 `Seq`（采样序号）、`ReadOK`（累计成功）、`Failures`（累计失败）

**单字节读取之间插 1ms 延时**（`IOSleep`），避免把 EC 打爆。
每轮 448 次读取约 0.45 秒。

---

## ⚠️ 已知限制与风险

| # | 限制 |
|---|---|
| 1 | **没有风扇 RPM**。窗口寄存器内找不到转速字段（已排查 `0x000`–`0xFFF` 与 `0x1800`–`0x18FF`） |
| 2 | **CPU 温度偏低**。`0x449` 是 EC 侧采样，满载仅 56℃（真实应在 85℃+）。**只看趋势，别当绝对温度** |
| 3 | **GPU 空闲 80℃ 是真实情况**，不是读数错误（5060 在 macOS 下无电源管理） |
| 4 | **软件不能切档**。档位由 EC 固件处理物理按键，OS 侧无入口 |
| 5 | 🔴 **不要启用 `SSDT-MechrevoData.aml`**。曾与 v7 驱动同时启用导致 macOS **完全无法启动**，元凶未定位 |

### 关于 Fn 键

`Fn + F10` 组合键会导致系统直接重启（这是本 EFI 的已知缺陷，与面板无关）。
**不要尝试**。详见 [docs/02-关键配置与踩坑.md](../docs/02-关键配置与踩坑.md)。

---

## 🔧 踩过的坑（改代码前务必看）

1. **`kmutil unload` 在这个环境用不了**，卸载驱动只能改 config 重启
2. **provider 必须 `static_cast<IOACPIPlatformDevice*>`**；用 `OSDynamicCast` 会绑定 metaClass 失败
3. **kext 必须导出 `kmod_info`**（`KMOD_EXPLICIT_DECL`），否则内核集合拒绝链接
4. **kext 文件权限必须 `root:wheel` + `755`**，否则不加载
5. **`plutil` / PlistBuddy 在本系统上写 `Info.plist` 会出问题**（报 `Close tag on line 9 does not match`），改用 Python `plistlib` 生成
6. **改 EFI 后务必 `plutil -lint` 验证 `config.plist`**，非法 XML 会直接导致开不了机
7. **不要一次性启用多个未验证项**（曾因同时启用自定义 SSDT + 改版驱动导致无法启动）

---

## 🚑 开不了机的救援

进 Windows，管理员 PowerShell：

```powershell
mountvol S: /S
```

用**文本编辑器**打开 `S:\EFI\OC\config.plist`，把 `MechrevoEC.kext` 那条的
`<key>Enabled</key><true/>` 改成 `<false/>`，保存后重启。

> ⚠️ **不要用 PowerShell 的 `[xml]` 对象改**，它会把 `<true/>` 写成非法的
> `<true>false</true>`，OpenCore 直接解析失败。必须改原文文本。

---

## 🚫 软件切档：结论是不做

| 路线 | 结论 | 依据 |
|---|---|---|
| **① 盲写窗口寄存器** | ❌ **不做** | `0x000`–`0xFFF` 内找不到干净的档位写入位点；盲写可能锁死风扇、黑屏，甚至影响自检 |
| **② 模拟物理按键** | ❌ **不通** | 内置键盘走 PS/2（非 USB HID）；该键由 EC 固件直接处理，**不上报操作系统** |
| **③ 复刻 MGIC 命令协议** | ⚠️ 唯一可行方向，需 Windows 侧配合 | 在 Windows 下用 RW-Everything 对 `0xFED50000` 切档前后各 dump 一次做对比，拿到确定偏移与值后用 `ECRW` 复刻 |

> 💡 当前做法：**档位只用笔记本物理键切换，软件不写寄存器。**

---

## 🔮 后续可做（未做）

- 读 EC 真实 RAM 拿 `XHPP`（权威 CPU 温度）与 `PL1L`/`PL2L`/`PL3L`/`PL4L`（功耗墙）
  —— 需重新启用自定义 SSDT，**有再次开不了机的风险**
- 风扇 RPM 继续找（可能要读 EC RAM 而非窗口）
- 面板开机自启（可加 LaunchAgent）

---

## 相关文档

| 文档 | 内容 |
|---|---|
| [docs/09-EC驱动与性能面板.md](../docs/09-EC驱动与性能面板.md) | 技术背景、事故记录、与 EFI 的集成 |
| [docs/02-关键配置与踩坑.md](../docs/02-关键配置与踩坑.md) | 整体配置因果与已证伪清单 |
| [docs/04-许可证与归属.md](../docs/04-许可证与归属.md) | 本仓库为什么不含二进制 |
