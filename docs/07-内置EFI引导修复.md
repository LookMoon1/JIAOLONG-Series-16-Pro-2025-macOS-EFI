# 内置硬盘 EFI 引导修复（无需 U 盘启动）

> **状态：已修复并验证（2026-11-18）**
> 本机现在**不插 U 盘也能从内置硬盘引导 OpenCore → macOS**。

---

## 一、问题

macOS 装在内置盘后，开机**总是直接进 Windows**，无法从内置 EFI 分区引导 OpenCore。
只能插着 U 盘才能进 macOS。

---

## 二、根因（三层，逐层排除）

### 第一层：BIOS 的启动优先级是两级的

UEFI 固件的 Boot 列表顶层是**设备类别**（`usb key` / `hard disk` / `network` …），
而 `hard disk` 类别**内部**先加载哪个 EFI 程序，由子菜单决定：

```text
BIOS → Boot → Hard Drive BBS Priorities
                （或 UEFI Hard Disk Drive BBS Priorities）
```

该机原先这个子菜单的 `Boot Option #1` = **Windows Boot Manager**，所以永远进 Windows。

### 第二层：在 OpenCore 里用 bcfg 加启动项，本机固件不认

在 UEFI Shell 里用 `bcfg boot add` 创建的条目，**确实写进了真实 NVRAM**
（`bcfg boot dump` 能看到），但这个固件**不把它们纳入自启动列表**，
也不会在 BIOS 可见列表里显示。

> **结论：bcfg 路线在本机无效，不要再走。**

### 第三层：两个 OpenCore 设置会造成"假象"或覆盖

| 设置 | 问题 |
|---|---|
| `UEFI → Quirks → RequestBootVarRouting = True` | 在 OC 自带的 OpenShell 里敲 `bcfg`，写入会被**重定向到 OC 私有变量区**。dump 看着对，重启无效 —— 典型的假阳性 |
| `Misc → Boot → LauncherOption = Full` | 每次 OC 启动都会**重写 BootOrder**，把你手动加的顺序挤掉 |

---

## 三、真正生效的修复（唯一需要做的操作）

1. 开机进 BIOS 设置（本机 **F2** / Del）
2. `Boot` 页 → 进入子菜单 **`Hard Drive BBS Priorities`**
3. 把该子菜单的 `Boot Option #1` 从 **Windows Boot Manager** 改为 **OpenCore**
4. 返回上层，确认 `hard disk` 为 `Boot Option #1`（`usb key` 排在后面）
5. **F10 保存退出**
6. 拔掉 U 盘重启 → 直接进内置 OpenCore

> ⚠️ **关键提示**：**顶层类别列表里看不到 OpenCore 是正常的**。
> OC 只出现在 BBS **子菜单**这一层。很多人卡在这里，以为固件没识别到 OC。

---

## 四、验证依据

修复后用以下三条确认真的生效了：

| 证据 | 说明 |
|---|---|
| 内置 EFI 分区根目录出现**本次启动的 OC 日志** | `opencore-2026-11-18-054900.txt`；**修复前内置 EFI 从无日志** |
| 该日志含 `OCB: Found 2 BootOrder entries` | 证明真实 BootOrder 已含 OC + Windows，且被内置 OC 读到 |
| `kern.boottime` 与日志时间吻合 | 日志用 **UTC** 命名（比本地早 8 小时），13:49 本地 = 05:49 UTC |

> **如何判断你启动的是哪份 EFI**：
> 看 OpenCore 日志写在哪个分区根目录。
> 本机之前在 U 盘 EFI 上，因为它从 U 盘引导。

---

## 五、配置现状（重要，勿随意改）

| 位置 | 设置 | 值 | 为什么 |
|---|---|---|---|
| U 盘 + 内置两份 config | `Misc → Boot → LauncherOption` | **`Disabled`** | **必须保持**，否则 OC 会重写 BootOrder，破坏 BIOS 设好的优先级 |
| U 盘 config | `UEFI → Quirks → RequestBootVarRouting` | `True` | 恢复为默认，用于启动项保护 |
| 内置 config | `UEFI → Quirks → RequestBootVarRouting` | `True` | 原本即是 |

---

## 六、回滚

想恢复"内置直接进 Windows"：

```text
BIOS → Hard Drive BBS Priorities → Boot Option #1 改回 Windows Boot Manager → F10
```

config 如需还原，用 `EFI/OC/config.plist.backup-pre-bootvar-*` 覆盖。
**全程未改 Windows 引导文件与数据。**

---

## 七、避坑经验

| 坑 | 教训 |
|---|---|
| 在 OpenCore 里用 `bcfg` 加启动项 | **本机固件不认**，别再走 Shell 路线 |
| 在 OC 自带 Shell 里改启动变量 | 会被 `RequestBootVarRouting` 重定向（假写入）；即便真写固件也不认 |
| 找启动项 | **要看 BBS 子菜单**，顶层类别列表会误导 |
| 对照日志时间 | OC 日志名是 **UTC**，比本地早 8 小时 |
