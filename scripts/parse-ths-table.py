#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""解析同花顺 data.10jqka.com.cn 排行页面 HTML 表格，输出统一 JSON。

用法:
    curl -s <URL> --compressed | iconv -f gbk -t utf-8 | python3 scripts/parse-ths-table.py --source <source>

source 取值:
    ths_lxsz   — 连续上涨  /rank/lxsz/
    ths_cxfl   — 持续放量  /rank/cxfl/
    ths_ljqs   — 量价齐升  /rank/ljqs/

输出: JSON 数组，每个元素包含:
    code, name, source, industry, 以及 source 特有字段
"""

import json
import re
import sys
import argparse


# 各页面表头 → 字段映射
FIELD_MAPS = {
    "ths_lxsz": {
        "序号": None,
        "股票代码": "code",
        "股票简称": "name",
        "收盘价(元)": "close",
        "最高价(元)": "high",
        "最低价(元)": "low",
        "连涨天数": "consecutive_up_days",
        "连续涨跌幅": "consecutive_change_pct",
        "累计换手率": "turnover_rate",
        "所属行业": "industry",
    },
    "ths_cxfl": {
        "序号": None,
        "股票代码": "code",
        "股票简称": "name",
        "涨跌幅（%）": "change_pct",
        "最新价（元）": "price",
        "成交量（股）": "volume",
        "基准日成交量（股）": "base_volume",
        "放量天数": "volume_up_days",
        "阶段涨跌幅（%）": "period_change_pct",
        "所属行业": "industry",
    },
    "ths_ljqs": {
        "序号": None,
        "股票代码": "code",
        "股票简称": "name",
        "最新价（元）": "price",
        "量价齐升天数": "volume_price_up_days",
        "阶段涨幅（%）": "period_change_pct",
        "累计换手率（%）": "turnover_rate",
        "所属行业": "industry",
    },
}

# 数值字段（去掉 % 后转 float）
NUMERIC_FIELDS = {
    "close", "high", "low", "consecutive_up_days", "consecutive_change_pct",
    "turnover_rate", "change_pct", "price", "volume_up_days",
    "period_change_pct", "volume_price_up_days",
}


def strip_tags(s: str) -> str:
    return re.sub(r"<[^>]+>", "", s).strip()


def parse_numeric(val: str):
    """尝试将字符串转为数值。去掉 % 和逗号。"""
    val = val.replace("%", "").replace(",", "").replace("万", "").strip()
    if not val or val == "--":
        return None
    try:
        f = float(val)
        return int(f) if f == int(f) else f
    except ValueError:
        return None


def parse_table(html: str, source: str) -> list[dict]:
    field_map = FIELD_MAPS[source]

    # 提取 thead 中的表头
    thead_m = re.search(r"<thead>(.*?)</thead>", html, re.DOTALL)
    if not thead_m:
        return []
    raw_headers = re.findall(r"<th[^>]*>(.*?)</th>", thead_m.group(1), re.DOTALL)
    headers = [strip_tags(h) for h in raw_headers]

    # 建立 列索引 → 字段名 映射
    col_map: dict[int, str] = {}
    for i, h in enumerate(headers):
        field = field_map.get(h)
        if field:
            col_map[i] = field

    # 提取 tbody 行
    tbody_m = re.search(r"<tbody>(.*?)</tbody>", html, re.DOTALL)
    if not tbody_m:
        return []
    row_strs = re.findall(r"<tr[^>]*>(.*?)</tr>", tbody_m.group(1), re.DOTALL)

    results = []
    for row_html in row_strs:
        cells = re.findall(r"<td[^>]*>(.*?)</td>", row_html, re.DOTALL)
        cells = [strip_tags(c) for c in cells]

        record: dict = {"source": source}
        for col_idx, field_name in col_map.items():
            if col_idx < len(cells):
                val = cells[col_idx]
                if field_name in NUMERIC_FIELDS:
                    record[field_name] = parse_numeric(val)
                else:
                    record[field_name] = val

        # 跳过无效行
        if not record.get("code") or not record.get("name"):
            continue

        results.append(record)

    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, choices=list(FIELD_MAPS.keys()))
    args = parser.parse_args()

    html = sys.stdin.read()
    rows = parse_table(html, args.source)
    json.dump(rows, sys.stdout, ensure_ascii=False, indent=2)
    print()  # trailing newline


if __name__ == "__main__":
    main()
