#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["aiohttp"]
# ///
"""多源强势股合并 + 概念聚合 + 精选输出。

汇聚 5 个数据源的强势股数据，批量查询概念，计算板块/概念分布，输出精选候选池。

用法:
    python3 scripts/merge-stock-candidates.py <trade_date> [--top N] [--no-iwencai]

输入（自动调用各采集脚本）:
    1. ashare-platform candidates (连阳+新高)
    2. THS 连续上涨 (lxsz)
    3. THS 持续放量 (cxfl)
    4. THS 量价齐升 (ljqs)
    5. 问财涨幅榜 (60d/120d/240d)

输出: JSON 对象:
{
    "summary": { ... },
    "concept_distribution": [ ... ],
    "selected_stocks": [ ... ]
}
"""

import asyncio
import json
import os
import subprocess
import sys
import argparse
from collections import defaultdict
from pathlib import Path

import aiohttp


SCRIPT_DIR = Path(__file__).parent
API_URL = os.environ.get("ASHARE_API_URL", "http://127.0.0.1:8000")

# 噪音概念黑名单：几乎所有股票都有，无区分度
NOISE_CONCEPTS = {
    "融资融券", "沪股通", "深股通", "转融券标的", "富时罗素概念",
    "MSCI概念", "标普道琼斯A股", "机构重仓",
}


def run_script(script: str, *args: str, timeout: int = 30) -> str:
    """运行采集脚本，返回 stdout。失败返回 '[]'。"""
    cmd = ["bash", str(SCRIPT_DIR / script)] + list(args)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout if r.returncode == 0 else "[]"
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return "[]"


def load_json(text: str) -> list | dict:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return []


def collect_sources(trade_date: str, skip_iwencai: bool = False) -> dict[str, list[dict]]:
    """收集所有数据源，返回 {source_name: [records]}。"""
    sources = {}

    # 1. ashare-platform candidates
    out = run_script("fetch-stock-candidates.sh", trade_date, "5", "10")
    data = load_json(out)
    if isinstance(data, dict):
        candidates = data.get("candidates", [])
    else:
        candidates = data
    # 统一格式
    for c in candidates:
        c["source"] = f"ashare_{c.get('source', 'unknown')}"
    sources["ashare"] = candidates

    # 2-4. THS 三个排行
    for script, name in [
        ("fetch-ths-lxsz.sh", "ths_lxsz"),
        ("fetch-ths-cxfl.sh", "ths_cxfl"),
        ("fetch-ths-ljqs.sh", "ths_ljqs"),
    ]:
        sources[name] = load_json(run_script(script))

    # 5. 问财涨幅榜（耗时较长）
    if not skip_iwencai:
        sources["iwencai"] = load_json(run_script("fetch-iwencai-topgain.sh", timeout=200))
    else:
        sources["iwencai"] = []

    return sources


def merge_stocks(sources: dict[str, list[dict]]) -> dict[str, dict]:
    """按股票代码合并所有数据源，返回 {code: merged_record}。"""
    stocks: dict[str, dict] = {}

    for source_name, records in sources.items():
        for rec in records:
            code = rec.get("code", "")
            if not code:
                continue
            if code not in stocks:
                stocks[code] = {
                    "code": code,
                    "name": rec.get("name", ""),
                    "sources": [],
                    "hit_count": 0,
                    "industry": rec.get("industry"),
                    # 涨幅数据
                    "gain_60d": None,
                    "gain_120d": None,
                    "gain_240d": None,
                    # 连涨/放量/量价齐升
                    "consecutive_up_days": None,
                    "volume_up_days": None,
                    "volume_price_up_days": None,
                    # 来自 ashare 的字段
                    "primary_theme": None,
                    "theme_resonance": None,
                    "ashare_source": None,
                    # 概念（后续填充）
                    "concepts": [],
                }

            s = stocks[code]
            source_tag = rec.get("source", source_name)
            if source_tag not in s["sources"]:
                s["sources"].append(source_tag)

            # 更新名称（优先用中文名）
            if rec.get("name") and not s["name"]:
                s["name"] = rec["name"]

            # 行业
            if rec.get("industry") and not s["industry"]:
                s["industry"] = rec["industry"]

            # 涨幅数据
            if source_tag == "iwencai_60d":
                s["gain_60d"] = rec.get("period_gain_pct")
            elif source_tag == "iwencai_120d":
                s["gain_120d"] = rec.get("period_gain_pct")
            elif source_tag == "iwencai_240d":
                s["gain_240d"] = rec.get("period_gain_pct")

            # 连涨天数
            if rec.get("consecutive_up_days"):
                s["consecutive_up_days"] = rec["consecutive_up_days"]

            # 放量天数
            if rec.get("volume_up_days"):
                s["volume_up_days"] = rec["volume_up_days"]

            # 量价齐升天数
            if rec.get("volume_price_up_days"):
                s["volume_price_up_days"] = rec["volume_price_up_days"]

            # ashare 特有字段
            if source_name == "ashare":
                s["primary_theme"] = rec.get("primary_theme")
                s["theme_resonance"] = rec.get("theme_resonance")
                s["ashare_source"] = rec.get("source")

    # 计算 hit_count
    for s in stocks.values():
        s["hit_count"] = len(s["sources"])

    return stocks


async def fetch_concepts_batch(
    codes: list[str], api_url: str, concurrency: int = 20
) -> dict[str, list[str]]:
    """批量查询股票概念，返回 {code: [concept_name, ...]}。"""
    result: dict[str, list[str]] = {}
    sem = asyncio.Semaphore(concurrency)

    async def fetch_one(session: aiohttp.ClientSession, code: str):
        async with sem:
            try:
                async with session.get(
                    f"{api_url}/stocks/concepts",
                    params={"code": code},
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        matched = data.get("matched_stocks", [])
                        if matched:
                            concepts = [
                                c["concept_name"]
                                for c in matched[0].get("concepts", [])
                                if c["concept_name"] not in NOISE_CONCEPTS
                            ]
                            result[code] = concepts
            except (aiohttp.ClientError, asyncio.TimeoutError):
                pass

    async with aiohttp.ClientSession() as session:
        tasks = [fetch_one(session, code) for code in codes]
        await asyncio.gather(*tasks)

    return result


def compute_concept_distribution(
    stocks: dict[str, dict], min_count: int = 2, max_pct: float = 20.0
) -> list[dict]:
    """按概念聚合，统计每个概念有多少只上榜股票。

    过滤掉出现频率超过 max_pct% 的泛概念（区分度太低）。
    """
    concept_stocks: dict[str, list[dict]] = defaultdict(list)

    for s in stocks.values():
        for concept in s.get("concepts", []):
            concept_stocks[concept].append(s)

    total = len(stocks)
    distribution = []
    for concept, members in concept_stocks.items():
        if len(members) < min_count:
            continue
        # 过滤出现率过高的泛概念
        if len(members) / total * 100 > max_pct:
            continue
        gains_60 = [m["gain_60d"] for m in members if m["gain_60d"] is not None]
        gains_120 = [m["gain_120d"] for m in members if m["gain_120d"] is not None]
        distribution.append({
            "concept": concept,
            "stock_count": len(members),
            "concentration_pct": round(len(members) / total * 100, 1),
            "stocks": [{"code": m["code"], "name": m["name"]} for m in members],
            "avg_gain_60d": round(sum(gains_60) / len(gains_60), 1) if gains_60 else None,
            "avg_gain_120d": round(sum(gains_120) / len(gains_120), 1) if gains_120 else None,
        })

    distribution.sort(key=lambda x: x["stock_count"], reverse=True)
    return distribution


def select_top_stocks(stocks: dict[str, dict], top_n: int = 30) -> list[dict]:
    """按 hit_count 和涨幅综合排序，选出 Top N。"""
    candidates = list(stocks.values())

    def sort_key(s):
        hit = s["hit_count"]
        # 综合涨幅：取可用的最长周期涨幅
        gain = s["gain_240d"] or s["gain_120d"] or s["gain_60d"] or 0
        return (hit, gain)

    candidates.sort(key=sort_key, reverse=True)

    selected = []
    for s in candidates[:top_n]:
        # 只保留出现频率高的概念（在 concept_distribution 中 count >= 2 的）
        top_concepts = s.get("concepts", [])[:5]
        selected.append({
            "code": s["code"],
            "name": s["name"],
            "hit_count": s["hit_count"],
            "sources": s["sources"],
            "industry": s["industry"],
            "gain_60d": s["gain_60d"],
            "gain_120d": s["gain_120d"],
            "gain_240d": s["gain_240d"],
            "consecutive_up_days": s["consecutive_up_days"],
            "volume_up_days": s["volume_up_days"],
            "volume_price_up_days": s["volume_price_up_days"],
            "primary_theme": s["primary_theme"],
            "top_concepts": top_concepts,
        })

    return selected


async def main_async(trade_date: str, top_n: int, skip_iwencai: bool):
    # 1. 采集
    print("正在采集各数据源...", file=sys.stderr)
    sources = collect_sources(trade_date, skip_iwencai)

    source_counts = {k: len(v) for k, v in sources.items()}
    print(f"  采集完成: {source_counts}", file=sys.stderr)

    # 2. 合并去重
    stocks = merge_stocks(sources)
    print(f"  合并去重: {len(stocks)} 只股票", file=sys.stderr)

    # 3. 批量查概念
    codes = list(stocks.keys())
    print(f"  正在查询 {len(codes)} 只股票的概念...", file=sys.stderr)
    concepts_map = await fetch_concepts_batch(codes, API_URL)
    for code, concepts in concepts_map.items():
        if code in stocks:
            stocks[code]["concepts"] = concepts
    print(f"  概念查询完成: {len(concepts_map)} 只有结果", file=sys.stderr)

    # 4. 概念分布
    distribution = compute_concept_distribution(stocks)

    # 收集有效概念集合（出现在 distribution 中的概念）
    valid_concepts = {d["concept"] for d in distribution}

    # 过滤每只股票的概念，只保留有聚集效应的
    for s in stocks.values():
        s["concepts"] = [c for c in s["concepts"] if c in valid_concepts]

    # 5. 精选输出
    selected = select_top_stocks(stocks, top_n)

    # 6. 汇总
    output = {
        "trade_date": trade_date,
        "summary": {
            "total_unique_stocks": len(stocks),
            "source_counts": source_counts,
            "concept_query_success": len(concepts_map),
        },
        "concept_distribution": distribution[:20],  # Top 20 概念
        "selected_stocks": selected,
    }

    json.dump(output, sys.stdout, ensure_ascii=False, indent=2)
    print()


def main():
    parser = argparse.ArgumentParser(description="多源强势股合并 + 概念聚合")
    parser.add_argument("trade_date", help="交易日期 YYYY-MM-DD")
    parser.add_argument("--top", type=int, default=30, help="精选 Top N 股票（默认 30）")
    parser.add_argument("--no-iwencai", action="store_true", help="跳过问财涨幅榜（加速测试）")
    args = parser.parse_args()

    asyncio.run(main_async(args.trade_date, args.top, args.no_iwencai))


if __name__ == "__main__":
    main()
