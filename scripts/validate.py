#!/usr/bin/env python3
"""
OpenCore config.plist 校验器

用法:
    python3 scripts/validate.py <path/to/config.plist>

检查项:
    1. XML plist 能否解析（二进制 plist 会被 ocvalidate 拒绝）
    2. 三码是否为占位符（提醒填入真实值）
    3. 本 EFI 的关键配置项是否处于期望值
    4. Kernel>Add / ACPI>Add 的条目数是否与 kext / aml 实文件对应
"""

import os
import sys
import plistlib

# ---- 本 EFI 的期望关键配置 ----
EXPECTED = {
    ("UEFI", "Quirks", "ExitBootServicesDelay"): 3000,
    ("Booter", "Quirks", "ProtectUefiServices"): True,
    ("Booter", "Quirks", "DevirtualiseMmio"): True,
    ("Booter", "Quirks", "DisableVariableWrite"): True,
    ("Booter", "Quirks", "ResizeAppleGpuBars"): 0,
    ("PlatformInfo", "Generic", "SystemProductName"): "MacBookPro16,2",
    # 注意：UpdateSMBIOSMode 在 PlatformInfo 顶层，CustomSMBIOSGuid 在 Kernel>Quirks
    ("PlatformInfo", "UpdateSMBIOSMode"): "Custom",
    ("Kernel", "Quirks", "CustomSMBIOSGuid"): True,
    ("Misc", "Security", "SecureBootModel"): "Disabled",
    # 内置硬盘引导依赖：LauncherOption 必须 Disabled，否则 OC 会重写 BootOrder
    ("Misc", "Boot", "LauncherOption"): "Disabled",
    ("UEFI", "Quirks", "RequestBootVarRouting"): True,
    # 静默启动：Target 只写文件(0x40)，AppleDebug 关闭（否则刷屏）
    ("Misc", "Debug", "Target"): 0x40,
    ("Misc", "Debug", "AppleDebug"): False,
    ("Misc", "Debug", "ApplePanic"): True,
}

# boot-args 中必须存在的关键参数
REQUIRED_ARGS = [
    "nvfb=1", "nvaccel=1", "gfxrst=4",
    "amfi=0x80", "amfi_get_out_of_my_way=0x1",
    "nvrmacpibl=1",          # 亮度
    "-vi2c-force-polling",   # 触控板
    "yyavic-cc=CN",          # Wi-Fi 国家码
    "-yyavicnoverify",       # Wi-Fi build 门槛
]

# 代表"尚未脱敏"的真实三码特征（占位符则通过）
PLACEHOLDERS = {
    "SERIAL-GENERATE-YOUR-OWN",
    "MLB-GENERATE-YOUR-OWN",
    "00000000-0000-0000-0000-000000000000",
    "",
}

NVRAM_GUID = "7C436110-AB2A-4BBB-A880-FE41995C9F82"

OK, WARN, FAIL = "[ OK ]", "[WARN]", "[FAIL]"

errors = []
warnings = []


def get(d, path):
    cur = d
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    path = sys.argv[1]
    if not os.path.isfile(path):
        print(f"{FAIL} 文件不存在: {path}")
        return 2

    print(f"校验目标: {path}")
    print("=" * 62)

    # ---- 1. 解析 ----
    raw = open(path, "rb").read()
    if raw.startswith(b"bplist"):
        print(f"{FAIL} 这是二进制 plist！OpenCore 只接受 XML 格式")
        return 1
    if raw.startswith(b"\xef\xbb\xbf"):
        print(f"{FAIL} 文件带 UTF-8 BOM，会导致解析失败")
        return 1

    try:
        d = plistlib.loads(raw)
        print(f"{OK} plist 解析成功（XML 格式）")
    except Exception as e:
        print(f"{FAIL} plist 解析失败: {e}")
        return 1

    # ---- 2. 三码 ----
    print()
    print("三码状态:")
    serial = get(d, ("PlatformInfo", "Generic", "SystemSerialNumber"))
    mlb = get(d, ("PlatformInfo", "Generic", "MLB"))
    uuid = get(d, ("PlatformInfo", "Generic", "SystemUUID"))
    rom = get(d, ("PlatformInfo", "Generic", "ROM"))

    for label, val in (("SystemSerialNumber", serial), ("MLB", mlb),
                       ("SystemUUID", uuid)):
        if val in PLACEHOLDERS:
            print(f"{WARN} {label} 仍是占位符 → {val!r}")
            warnings.append(f"{label} 未填写")
        else:
            print(f"{OK} {label} 已填写")

    if not rom:
        print(f"{WARN} ROM 为空 → 需要填入网卡 MAC（6 字节）")
        warnings.append("ROM 未填写")
    else:
        print(f"{OK} ROM 已填写（{len(rom)} 字节）")

    # ---- 3. 关键配置 ----
    print()
    print("关键配置:")
    for path_tuple, want in EXPECTED.items():
        got = get(d, path_tuple)
        name = " → ".join(path_tuple)
        if got == want:
            print(f"{OK} {name} = {got!r}")
        elif got is None:
            print(f"{FAIL} {name} 缺失（期望 {want!r}）")
            errors.append(name)
        else:
            print(f"{FAIL} {name} = {got!r}，期望 {want!r}")
            errors.append(name)

    # ---- 4. boot-args ----
    print()
    print("boot-args:")
    ba = (get(d, ("NVRAM", "Add", NVRAM_GUID, "boot-args")) or "")
    missing = [a for a in REQUIRED_ARGS if a not in ba.split()]
    if missing:
        for m in missing:
            print(f"{FAIL} 缺少 {m}")
            errors.append(f"boot-args: {m}")
    else:
        print(f"{OK} 全部 {len(REQUIRED_ARGS)} 个关键参数都在")
    print(f"       完整值: {ba}")

    # NVRAM Delete 中是否含 boot-args（防旧值覆盖）
    delete = get(d, ("NVRAM", "Delete", NVRAM_GUID)) or []
    if "boot-args" in delete:
        print(f"{OK} NVRAM > Delete 含 boot-args（可覆盖旧值）")
    else:
        print(f"{WARN} NVRAM > Delete 不含 boot-args → 改参数可能不生效")
        warnings.append("NVRAM Delete 缺 boot-args")

    # 静默启动检查：不应含 -v
    if "-v" in ba.split():
        print(f"{WARN} boot-args 含 -v → 每次开机会刷屏（排查模式）")
        warnings.append("boot-args 含 -v（非静默启动）")
    else:
        print(f"{OK} boot-args 无 -v（静默启动）")

    # ---- 5. 条目数 ----
    print()
    print("条目统计:")
    add = get(d, ("Kernel", "Add")) or []
    acpi = get(d, ("ACPI", "Add")) or []
    print(f"{OK} Kernel > Add : {len(add)} 条")
    print(f"{OK} ACPI   > Add : {len(acpi)} 条")

    disabled = [e.get("BundlePath", "?") for e in add if not e.get("Enabled", False)]
    if disabled:
        print(f"{WARN} 有 {len(disabled)} 个 kext 被禁用: {', '.join(disabled)}")
        warnings.append(f"{len(disabled)} 个 kext 被禁用")

    # 检查 kext 文件是否真的存在
    oc_dir = os.path.dirname(path)
    kexts_dir = os.path.join(oc_dir, "Kexts")
    if not os.path.isdir(kexts_dir):
        # 本仓库是「纯配置版」：不带 kext 二进制
        print(f"{WARN} Kexts/ 目录不存在 —— 本仓库为纯配置版，kext 需自行下载")
        if add:
            print(f"{FAIL} 但 Kernel > Add 仍有 {len(add)} 条条目，指向不存在的文件！")
            print("        请放入对应 kext，或清空 Kernel > Add")
            errors.append("Kernel>Add 有条目但 Kexts/ 不存在")
        else:
            print(f"       Kernel > Add 为空（符合纯配置版预期）")
            print(f"       请按 docs/03-Kext清单.md 下载 kext，放入 EFI/OC/Kexts/")
            print(f"       再按加载顺序把它们加入 Kernel > Add")
        warnings.append("Kexts/ 未就绪（纯配置版，需自行补充）")
    else:
        missing_kexts = []
        for e in add:
            bp = e.get("BundlePath")
            if bp and not os.path.exists(os.path.join(kexts_dir, bp)):
                missing_kexts.append(bp)
        if missing_kexts:
            print(f"{FAIL} 有 {len(missing_kexts)} 个 kext 在 Kexts/ 里找不到:")
            for m in missing_kexts:
                print(f"         - {m}")
            errors.append("kext 文件缺失")
        else:
            print(f"{OK} 全部 {len(add)} 个 kext 文件均存在")

        acpi_dir = os.path.join(oc_dir, "ACPI")
        if os.path.isdir(acpi_dir):
            missing_aml = [e.get("Path") for e in acpi
                           if e.get("Path") and not os.path.exists(os.path.join(acpi_dir, e["Path"]))]
            if missing_aml:
                print(f"{FAIL} ACPI 文件缺失: {', '.join(missing_aml)}")
                errors.append("ACPI 文件缺失")
            else:
                print(f"{OK} 全部 {len(acpi)} 个 ACPI 文件均存在")

    # ---- 汇总 ----
    print()
    print("=" * 62)
    if errors:
        print(f"{FAIL} 有 {len(errors)} 个错误:")
        for e in errors:
            print(f"       - {e}")
        return 1

    if warnings:
        print(f"{WARN} {len(warnings)} 个提醒（不阻断）:")
        for w in warnings:
            print(f"       - {w}")
        print()
        print("结构与配置校验通过。填入三码后即可使用。")
        return 0

    print(f"{OK} 全部校验通过，无问题。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
