#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
extract-picks.py — 从最终报告提取结构化荐股数据

用法:
  bin/extract-picks.py <final_report.md> > picks.json

从报告的 "八、今日荐股" 章节中提取 ```json 代码块，输出 picks.json。
若未找到 JSON 块，输出 {"picks": []}。
"""

import json
import re
import sys
from pathlib import Path


def extract_picks(report_path: str) -> dict:
    content = Path(report_path).read_text(encoding="utf-8")

    # 定位 "八、今日荐股" 章节
    section_match = re.search(
        r'##\s*[八8][\s、.。]*今日荐股.*?(?=\n##\s|\Z)',
        content,
        re.DOTALL | re.IGNORECASE,
    )
    if not section_match:
        return {"picks": []}

    section = section_match.group(0)

    # 提取 ```json ... ``` 代码块（机器可读部分）
    json_match = re.search(r'```json\s*(.*?)\s*```', section, re.DOTALL)
    if not json_match:
        return {"picks": []}

    try:
        data = json.loads(json_match.group(1))
        # 兼容两种结构：{"picks": [...]} 或直接 [...]
        if isinstance(data, list):
            return {"picks": data}
        if isinstance(data, dict) and "picks" in data:
            return data
        return {"picks": []}
    except json.JSONDecodeError as e:
        print(f"[warn] JSON 解析失败: {e}", file=sys.stderr)
        return {"picks": []}


def main():
    if len(sys.argv) < 2:
        print("用法: extract-picks.py <final_report.md>", file=sys.stderr)
        sys.exit(1)

    result = extract_picks(sys.argv[1])
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
