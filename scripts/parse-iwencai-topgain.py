#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""解析问财涨幅榜 read-url 输出的 Markdown 表格，提取股票列表。

用法:
    omp web-operator read-url "<url>" --limit 8000 | python3 scripts/parse-iwencai-topgain.py --period 60

输入: omp web-operator read-url 输出的 Markdown 文本
输出: JSON 数组 [{code, name, source, price, change_pct, rank, period_gain_pct}, ...]

问财返回的 Markdown 表格有两个（完整表 + 精简表），只解析第一个（含涨幅数据的）。
"""

import json
import re
import sys
import argparse


def parse_numeric(val: str):
    val = val.replace(",", "").replace("\\", "").strip()
    if not val or val == "--":
        return None
    try:
        f = float(val)
        return int(f) if f == int(f) else f
    except ValueError:
        return None


def parse_markdown(text: str, period: int) -> list[dict]:
    source = f"iwencai_{period}d"
    results = []
    seen_codes = set()

    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue

        cells = [c.strip() for c in line.split("|")]
        # 去掉首尾空字符串（split '|' 产生的）
        cells = [c for c in cells if c != "---"]

        # 跳过分隔行
        if all(c.strip("-: ") == "" for c in cells):
            continue

        # 查找包含 6 位股票代码的行
        code_match = None
        for c in cells:
            m = re.search(r"\b(\d{6})\b", c)
            if m:
                code_match = m.group(1)
                break

        if not code_match:
            continue
        if code_match in seen_codes:
            continue  # 跳过第二个表格的重复数据
        seen_codes.add(code_match)

        # 提取名称（从 [名称](url) 格式）
        name = None
        for c in cells:
            m = re.search(r"\[([^\]]+)\]", c)
            if m:
                name = m.group(1)
                break

        if not name:
            continue

        # 提取排名（先提取，用于过滤序号）
        rank = None
        for c in cells:
            m = re.search(r"(\d+)/\d+", c)
            if m:
                rank = int(m.group(1))
                break

        # 提取数值列：过滤掉非数值单元格
        numeric_cells = []
        for c in cells:
            if not c.strip():
                continue
            if re.search(r"\d{6}", c):
                continue
            if "[" in c:
                continue
            if re.search(r"\d+/\d+", c):
                continue
            val = parse_numeric(c)
            if val is not None:
                numeric_cells.append(val)

        # 问财表格数值列顺序: 序号, 现价, 涨跌幅, 区间涨幅
        # 序号等于排名，去掉
        if len(numeric_cells) >= 2 and rank is not None and numeric_cells[0] == rank:
            numeric_cells = numeric_cells[1:]

        price = numeric_cells[0] if len(numeric_cells) >= 1 else None
        change_pct = numeric_cells[1] if len(numeric_cells) >= 2 else None
        period_gain_pct = numeric_cells[-1] if len(numeric_cells) >= 3 else None

        results.append({
            "code": code_match,
            "name": name,
            "source": source,
            "price": price,
            "change_pct": change_pct,
            "rank": rank,
            "period_gain_pct": period_gain_pct,
        })

    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--period", required=True, type=int, help="涨幅周期（天数）: 60, 120, 240")
    args = parser.parse_args()

    text = sys.stdin.buffer.read().decode("utf-8", errors="ignore")
    rows = parse_markdown(text, args.period)
    json.dump(rows, sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    main()
