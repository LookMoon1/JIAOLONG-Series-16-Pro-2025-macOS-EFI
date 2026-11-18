#!/usr/bin/env python3
"""
Markdown 排版检查器 —— 按 docs/STYLE.md 的规范检查

用法:
    python3 scripts/check_style.py            # 检查全部
    python3 scripts/check_style.py --fix-hint # 附修复提示
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGETS = ['README.md', 'AGENTS.md', 'LICENSE']
DOCS_DIR = os.path.join(ROOT, 'docs')

# 允许在提示块/警告里出现的整句加粗（白名单：明确的警示语）
BOLD_PHRASE_MAX = 30

issues = []


def add(path, lineno, kind, text, hint=''):
    issues.append((os.path.basename(path), lineno, kind, text.strip(), hint))


def check_file(path):
    try:
        lines = open(path, encoding='utf-8').read().split('\n')
    except Exception:
        return

    in_code = False
    for i, line in enumerate(lines, 1):
        # 代码块开关
        if line.strip().startswith('```'):
            if line.strip() == '```' and not in_code:
                add(path, i, '代码块缺语言标记', line, '改为 ```text 或 ```bash')
            in_code = not in_code
            continue
        if in_code:
            continue

        # 1. 表格第一列加粗
        if re.match(r'^\|\s*\*\*[^*]+\*\*\s*\|', line):
            add(path, i, '表格第一列加粗', line, '去掉 `**`')

        # 2. 整句加粗（>30 字符且不含代码）
        for m in re.finditer(r'\*\*([^*]+)\*\*', line):
            content = m.group(1)
            # 排除：含链接、含警告语、纯路径引用
            if '](' in content or re.search(r'(不要|必须|会导致|禁止)', content):
                continue
            # 排除：状态声明（这类整句加粗是合理强调）
            if re.match(r'^(状态|这意味着|其内嵌|正确做法)', content):
                continue
            # 排除：配置路径（A → B → C 形式）
            if '→' in content and len(content.split('→')) >= 2:
                continue
            # 排除：结论性对比 / 验证环境版本组合（合理强调）
            if re.search(r'(实际|已验证|验证通过|不承担|不涉及)', content):
                continue
            # 排除：版本号组合（如 Tahoe 26.7.1 + OpenCore 1.0.7）
            if re.search(r'\d+\.\d+', content) and ('+' in content or '版本' in content):
                continue
            if len(content) > BOLD_PHRASE_MAX and '`' not in content:
                add(path, i, '整句加粗', line, '改加粗关键词或去掉')

        # 3. 列表项以加粗开头（可能是过重强调）—— 只统计，不报错
        # 4. 裸链接失效由 check_links 处理

    # 5. 层级过深
    for i, line in enumerate(lines, 1):
        if re.match(r'^#####\s', line):
            add(path, i, '标题层级过深(>4级)', line, '重构结构')


def check_status_column():
    """检查状态表格里是否有"部分行加粗"的不一致"""
    for name in ['README.md'] + [f for f in os.listdir(DOCS_DIR) if f.endswith('.md')]:
        path = os.path.join(ROOT, name) if name == 'README.md' else os.path.join(DOCS_DIR, name)
        if not os.path.isfile(path):
            continue
        lines = open(path, encoding='utf-8').read().split('\n')
        # 找出状态表格块（含 emoji 状态列）
        block = []
        for i, line in enumerate(lines, 1):
            if re.match(r'^\|.*\|\s*(✅|⚠️|❌|🔴)', line):
                block.append((i, line))
            else:
                if len(block) >= 3:
                    _check_block(name, block)
                block = []
        if len(block) >= 3:
            _check_block(name, block)


def _check_block(name, block):
    bold_first = sum(1 for _, l in block if re.match(r'^\|\s*\*\*', l))
    if 0 < bold_first < len(block):
        add(name, block[0][0], '状态表加粗不一致',
            f'{bold_first}/{len(block)} 行第一列加粗',
            '统一去掉加粗')


def main():
    check_file(os.path.join(ROOT, 'README.md'))
    check_file(os.path.join(ROOT, 'AGENTS.md'))
    for f in sorted(os.listdir(DOCS_DIR)):
        if f.endswith('.md'):
            check_file(os.path.join(DOCS_DIR, f))
    check_status_column()

    if not issues:
        print('✓ 未发现排版问题')
        return 0

    # 按类型汇总
    from collections import Counter
    kinds = Counter(k for _, _, k, _, _ in issues)
    print('发现 %d 处问题：\n' % len(issues))
    for kind, cnt in kinds.most_common():
        print('  %-24s %d 处' % (kind, cnt))
    print()

    current = None
    for fname, lineno, kind, text, hint in issues:
        if fname != current:
            print('--- %s ---' % fname)
            current = fname
        print('  L%-4d [%s]' % (lineno, kind))
        print('        %s' % (text[:110] + ('...' if len(text) > 110 else '')))
        if hint:
            print('        → %s' % hint)

    return 1


if __name__ == '__main__':
    sys.exit(main())
