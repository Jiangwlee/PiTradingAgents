#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
review-picks.py — 荐股复盘分析

从最终报告中提取核心标的池，获取次日开盘价买入后持有 1/3/5 日的收益，
同时以 5 星趋势股 Top N 作为基准对比。

用法:
  bin/review-picks.py                              # 自动选取最近 10 期
  bin/review-picks.py --last 5                     # 最近 5 期
  bin/review-picks.py --from 2026-04-01 --to 2026-04-13  # 指定区间
  bin/review-picks.py --baseline-top 10            # 基准取 Top 10（默认）
  bin/review-picks.py --output docs/review/report.md     # 输出 Markdown 报告

需要 ashare-platform API 在本地运行 (默认 http://127.0.0.1:8000)。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import TextIO

# ── 配置 ─────────────────────────────────────────────────────────────────

API_BASE = os.environ.get("ASHARE_API_URL", "http://127.0.0.1:8000")
DATA_HOME = Path(
    os.environ.get(
        "PITA_DATA_DIR",
        Path.home() / ".local/share/PiTradingAgents",
    )
)
REPORTS_DIR = DATA_HOME / "reports"

# ── 数据结构 ─────────────────────────────────────────────────────────────


@dataclass
class StockPick:
    """一条荐股记录"""

    report_date: str
    code: str
    name: str
    signal: str
    buy_price: float | None = None
    h1: float | None = None  # 持有 1 日收益 %
    h3: float | None = None  # 持有 3 日收益 %
    h5: float | None = None  # 持有 5 日收益 %
    dd3: float | None = None  # 3 日最大回撤 %
    dd5: float | None = None  # 5 日最大回撤 %


@dataclass
class TrendStock:
    """一条趋势股记录"""

    report_date: str
    code: str
    name: str
    rank: int
    score: float
    star: int
    emotion_level: int
    buy_price: float | None = None
    h1: float | None = None
    h3: float | None = None
    h5: float | None = None
    dd3: float | None = None
    dd5: float | None = None


@dataclass
class Stats:
    """统计汇总"""

    n: int = 0
    up: int = 0
    avg: float = 0.0
    med: float = 0.0
    mx: float = 0.0
    mn: float = 0.0

    @property
    def wr(self) -> float:
        return self.up / self.n * 100 if self.n else 0.0


# ── API 工具 ─────────────────────────────────────────────────────────────


def api_get(endpoint: str, params: dict | None = None) -> list | dict:
    """调用 ashare-platform API"""
    url = f"{API_BASE}{endpoint}"
    if params:
        from urllib.parse import urlencode

        url += "?" + urlencode(params)
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return []


def fetch_kline(code: str, start_date: str) -> list[dict]:
    """获取个股日线数据"""
    return api_get(
        f"/kline/daily/{code}",
        {"start_date": start_date.replace("-", ""), "end_date": "20991231"},
    )


def fetch_trend_pool(date: str, limit: int = 10) -> list[dict]:
    """获取趋势池 5 星股"""
    return api_get(
        "/trend-pool/daily",
        {"trade_date": date, "limit": str(limit), "min_star": "5"},
    )


def fetch_trade_dates() -> list[str]:
    """获取最近交易日列表"""
    data = api_get("/trade-dates/recent", {"n": "60"})
    if isinstance(data, list):
        return sorted(data)
    if isinstance(data, dict) and "trade_dates" in data:
        return sorted(data["trade_dates"])
    return []


# ── 报告解析 ─────────────────────────────────────────────────────────────

# 匹配核心标的池表格行: | 代码 | 名称 | ... | 信号 | ...
_TABLE_ROW_RE = re.compile(
    r"\|\s*(\d{6})\s*\|\s*([^\|]+?)\s*\|.*?\|\s*"
    r"(买入|持有|重点关注|关注|观望|观察|持有/观察|回避)\s*\|"
)


def extract_picks_from_report(report_path: Path) -> list[tuple[str, str, str]]:
    """从最终报告提取 (code, name, signal) 列表，排除回避信号"""
    if not report_path.exists():
        return []
    content = report_path.read_text(encoding="utf-8")
    seen = set()
    picks = []
    for m in _TABLE_ROW_RE.finditer(content):
        code, name, signal = m.group(1), m.group(2).strip(), m.group(3).strip()
        if signal == "回避":
            continue
        if code not in seen:
            seen.add(code)
            picks.append((code, name, signal))
    return picks


# ── 收益计算 ─────────────────────────────────────────────────────────────


def next_trade_date(date: str, trade_dates: list[str]) -> str | None:
    """返回给定日期的下一个交易日"""
    for td in trade_dates:
        if td > date:
            return td
    return None


def compute_returns(
    code: str,
    report_date: str,
    buy_date: str,
) -> dict:
    """计算以 buy_date 开盘价买入后的持有收益"""
    kline = fetch_kline(code, report_date)
    future: list[dict] = []
    found = False
    for d in kline:
        if d["date"] == buy_date:
            found = True
        if found:
            future.append(d)

    result: dict = {
        "buy_price": None,
        "h1": None,
        "h3": None,
        "h5": None,
        "dd3": None,
        "dd5": None,
    }
    if not future or not future[0].get("open"):
        return result

    bp = future[0]["open"]
    result["buy_price"] = bp
    if len(future) >= 1:
        result["h1"] = (future[0]["close"] / bp - 1) * 100
    if len(future) >= 3:
        result["h3"] = (future[2]["close"] / bp - 1) * 100
        result["dd3"] = (min(d["low"] for d in future[:3]) / bp - 1) * 100
    if len(future) >= 5:
        result["h5"] = (future[4]["close"] / bp - 1) * 100
        result["dd5"] = (min(d["low"] for d in future[:5]) / bp - 1) * 100
    return result


# ── 统计工具 ─────────────────────────────────────────────────────────────


def calc_stats(values: list[float]) -> Stats | None:
    if not values:
        return None
    n = len(values)
    up = sum(1 for v in values if v > 0)
    avg = sum(values) / n
    s = sorted(values)
    med = s[n // 2]
    return Stats(n=n, up=up, avg=avg, med=med, mx=max(values), mn=min(values))


def fmt_pct(v: float | None) -> str:
    return f"{v:+.2f}%" if v is not None else "N/A"


# ── 输出 ─────────────────────────────────────────────────────────────────


def print_section(title: str, out: TextIO) -> None:
    out.write(f"\n{'=' * 90}\n")
    out.write(f"  {title}\n")
    out.write(f"{'=' * 90}\n")


def print_stats_table(
    groups: list[tuple[str, list]],
    key_map: list[tuple[str, str]],
    out: TextIO,
) -> None:
    """打印分组统计表"""
    hdr = f"{'类别':<22} {'周期':<5} {'样本':>4} {'胜率':>7} {'均值':>8} {'中位数':>8} {'最大':>8} {'最小':>8}"
    out.write(f"{hdr}\n")
    out.write(f"{'-' * 78}\n")
    for label, picks in groups:
        for period_name, key in key_map:
            vals = [getattr(p, key) for p in picks if getattr(p, key) is not None]
            s = calc_stats(vals)
            if s:
                out.write(
                    f"{label:<22} {period_name:<5} {s.n:>4} "
                    f"{s.wr:>6.1f}% {s.avg:>+7.2f}% {s.med:>+7.2f}% "
                    f"{s.mx:>+7.2f}% {s.mn:>+7.2f}%\n"
                )
        out.write("\n")


def print_detail_table(picks: list[StockPick], out: TextIO) -> None:
    """打印荐股明细"""
    out.write(
        f"{'报告日':<12} {'代码':<8} {'名称':<10} {'信号':<10} "
        f"{'买入价':>8} {'持有1日':>9} {'持有3日':>9} {'持有5日':>9} "
        f"{'3日回撤':>9}\n"
    )
    out.write(f"{'─' * 100}\n")
    prev_date = ""
    for p in picks:
        if prev_date and prev_date != p.report_date:
            out.write(f"{'─' * 100}\n")
        prev_date = p.report_date
        bp = f"{p.buy_price:.2f}" if p.buy_price else "N/A"
        out.write(
            f"{p.report_date:<12} {p.code:<8} {p.name:<10} {p.signal:<10} "
            f"{bp:>8} {fmt_pct(p.h1):>9} {fmt_pct(p.h3):>9} {fmt_pct(p.h5):>9} "
            f"{fmt_pct(p.dd3):>9}\n"
        )


def print_trend_detail(stocks: list[TrendStock], out: TextIO) -> None:
    """打印趋势股明细"""
    out.write(
        f"{'日期':<12} {'Rank':>4} {'代码':<8} {'名称':<10} "
        f"{'得分':>6} {'情绪':>3} {'买入价':>8} {'持有1日':>9} "
        f"{'持有3日':>9} {'持有5日':>9}\n"
    )
    out.write(f"{'─' * 100}\n")
    prev_date = ""
    for s in stocks:
        if prev_date and prev_date != s.report_date:
            out.write(f"{'─' * 100}\n")
        prev_date = s.report_date
        bp = f"{s.buy_price:.2f}" if s.buy_price else "N/A"
        out.write(
            f"{s.report_date:<12} {s.rank:>4} {s.code:<8} {s.name:<10} "
            f"{s.score:>6.1f} {s.emotion_level:>3} {bp:>8} "
            f"{fmt_pct(s.h1):>9} {fmt_pct(s.h3):>9} {fmt_pct(s.h5):>9}\n"
        )


def print_portfolio_sim(
    picks: list,
    dates: list[str],
    key: str,
    label: str,
    out: TextIO,
) -> None:
    """等权组合模拟"""
    cum = 1.0
    out.write(f"\n  策略: {label}\n")
    for d in dates:
        rp = [p for p in picks if p.report_date == d and getattr(p, key) is not None]
        if not rp:
            continue
        avg_ret = sum(getattr(p, key) for p in rp) / len(rp)
        cum *= 1 + avg_ret / 100
        out.write(
            f"    {d}: 当期 {avg_ret:+.2f}% | "
            f"累计 {cum:.4f} ({(cum - 1) * 100:+.2f}%)\n"
        )
    out.write(f"  ── 最终累计: {(cum - 1) * 100:+.2f}%\n")


def print_comparison(
    pick_list: list[StockPick],
    trend_list: list[TrendStock],
    report_dates: list[str],
    out: TextIO,
) -> None:
    """PiTrader vs 基准对比表"""
    out.write(
        f"{'指标':<20} {'PiTrader':>12} {'趋势股基准':>12} {'差异':>10}\n"
    )
    out.write(f"{'─' * 58}\n")
    for period, key in [("1日", "h1"), ("3日", "h3"), ("5日", "h5")]:
        pv = [getattr(p, key) for p in pick_list if getattr(p, key) is not None]
        tv = [getattr(t, key) for t in trend_list if getattr(t, key) is not None]
        ps = calc_stats(pv)
        ts = calc_stats(tv)
        if ps and ts:
            diff = ps.avg - ts.avg
            out.write(
                f"持有{period}均值         {ps.avg:>+11.2f}% {ts.avg:>+11.2f}% "
                f"{diff:>+9.2f}%\n"
            )
    # 累计
    for period, key, label in [
        ("1日", "h1", "1日累计"),
        ("3日", "h3", "3日累计"),
        ("5日", "h5", "5日累计"),
    ]:
        for src, name in [(pick_list, "PiTrader"), (trend_list, "趋势股")]:
            pass  # 简化：累计在组合模拟中已展示

    # 回撤
    for period, key in [("3日", "dd3"), ("5日", "dd5")]:
        pv = [getattr(p, key) for p in pick_list if getattr(p, key) is not None]
        tv = [getattr(t, key) for t in trend_list if getattr(t, key) is not None]
        ps = calc_stats(pv)
        ts = calc_stats(tv)
        if ps and ts:
            diff = ps.avg - ts.avg
            out.write(
                f"{period}最大回撤均值       {ps.avg:>+11.2f}% {ts.avg:>+11.2f}% "
                f"{diff:>+9.2f}%\n"
            )


# ── 主流程 ─────────────────────────────────────────────────────────────


def eprint(*args: object, **kwargs: object) -> None:
    print(*args, file=sys.stderr, **kwargs)


def find_report_dates(
    last_n: int = 10,
    from_date: str | None = None,
    to_date: str | None = None,
) -> list[str]:
    """找到有最终报告的日期列表"""
    if not REPORTS_DIR.exists():
        eprint(f"报告目录不存在: {REPORTS_DIR}")
        return []

    dates: list[str] = []
    for d in sorted(REPORTS_DIR.iterdir()):
        if not d.is_dir():
            continue
        name = d.name
        # 跳过无效目录名
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", name):
            continue
        final = d / "07-final-report.md"
        if not final.exists():
            continue
        if from_date and name < from_date:
            continue
        if to_date and name > to_date:
            continue
        dates.append(name)

    if not from_date and not to_date:
        dates = dates[-last_n:]
    return dates


def run(
    last_n: int,
    from_date: str | None,
    to_date: str | None,
    baseline_top: int,
    output_path: str | None,
) -> None:
    # ── 1. 确定报告日期 ──
    report_dates = find_report_dates(last_n, from_date, to_date)
    if not report_dates:
        eprint("未找到有效报告，退出")
        sys.exit(1)

    eprint(f"[info] 评估区间: {report_dates[0]} ~ {report_dates[-1]}（{len(report_dates)} 期）")

    # ── 2. 获取交易日历 ──
    trade_dates = fetch_trade_dates()
    if not trade_dates:
        eprint("[error] 无法获取交易日历，请检查 ashare-platform 是否运行")
        sys.exit(1)

    # ── 3. 提取荐股并计算收益 ──
    eprint("[info] 提取荐股并计算收益...")
    all_picks: list[StockPick] = []
    for rd in report_dates:
        report_path = REPORTS_DIR / rd / "07-final-report.md"
        picks = extract_picks_from_report(report_path)
        buy_date = next_trade_date(rd, trade_dates)
        if not buy_date:
            eprint(f"  {rd}: 找不到次日交易日，跳过")
            continue
        eprint(f"  {rd}: {len(picks)} 只推荐, 买入日 {buy_date}")
        for code, name, signal in picks:
            ret = compute_returns(code, rd, buy_date)
            sp = StockPick(
                report_date=rd,
                code=code,
                name=name,
                signal=signal,
                **ret,
            )
            all_picks.append(sp)

    # ── 4. 趋势股基准 ──
    eprint(f"[info] 获取 5 星趋势股 Top {baseline_top} 基准...")
    all_trend: list[TrendStock] = []
    for rd in report_dates:
        pool = fetch_trend_pool(rd, limit=baseline_top)
        buy_date = next_trade_date(rd, trade_dates)
        if not buy_date or not pool:
            continue
        eprint(f"  {rd}: {len(pool)} 只趋势股")
        for s in pool:
            ret = compute_returns(s["code"], rd, buy_date)
            ts = TrendStock(
                report_date=rd,
                code=s["code"],
                name=s["name"],
                rank=s.get("rank", 0),
                score=s.get("score_total", 0),
                star=s.get("star_rating", 0),
                emotion_level=s.get("emotion_level", 0),
                **ret,
            )
            all_trend.append(ts)

    # ── 5. 输出 ──
    out: TextIO
    if output_path:
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        out = open(output_path, "w", encoding="utf-8")
    else:
        out = sys.stdout

    today = datetime.now().strftime("%Y-%m-%d")
    period_key_map = [("1日", "h1"), ("3日", "h3"), ("5日", "h5")]

    out.write(f"PiTrader 荐股复盘分析\n")
    out.write(f"评估区间: {report_dates[0]} ~ {report_dates[-1]}（{len(report_dates)} 期）\n")
    out.write(f"生成日期: {today}\n")
    out.write(f"买入方式: 次日开盘价买入\n")

    # ── 荐股明细 ──
    print_section("PiTrader 荐股明细", out)
    print_detail_table(all_picks, out)

    # ── 荐股统计 ──
    print_section("PiTrader 荐股统计", out)

    strong_sigs = {"买入", "持有", "重点关注"}
    medium_sigs = {"关注"}
    weak_sigs = {"观望", "观察", "持有/观察"}

    out.write("\n【按信号强度】\n")
    print_stats_table(
        [
            ("全部推荐", all_picks),
            ("强信号(买入/持有/重点)", [p for p in all_picks if p.signal in strong_sigs]),
            ("中信号(关注)", [p for p in all_picks if p.signal in medium_sigs]),
            ("弱信号(观望/观察)", [p for p in all_picks if p.signal in weak_sigs]),
        ],
        period_key_map,
        out,
    )

    out.write("【按单个信号】\n")
    for sig in ["买入", "持有", "重点关注", "关注", "观望"]:
        picks = [p for p in all_picks if p.signal == sig]
        if picks:
            print_stats_table([(sig, picks)], period_key_map, out)

    out.write("【按报告日期】\n")
    out.write(
        f"{'日期':<12} {'1日均值':>8} {'1日胜率':>8} "
        f"{'3日均值':>8} {'3日胜率':>8} "
        f"{'5日均值':>8} {'5日胜率':>8}\n"
    )
    out.write(f"{'─' * 68}\n")
    for rd in report_dates:
        rp = [p for p in all_picks if p.report_date == rd]
        cols = [rd]
        for key in ["h1", "h3", "h5"]:
            vals = [getattr(p, key) for p in rp if getattr(p, key) is not None]
            s = calc_stats(vals)
            if s:
                cols.append(f"{s.avg:+.2f}%")
                cols.append(f"{s.wr:.0f}%")
            else:
                cols.extend(["N/A", "N/A"])
        out.write(
            f"{cols[0]:<12} {cols[1]:>8} {cols[2]:>8} "
            f"{cols[3]:>8} {cols[4]:>8} "
            f"{cols[5]:>8} {cols[6]:>8}\n"
        )

    # ── 等权组合模拟 ──
    print_section("等权组合模拟", out)

    out.write("\n--- PiTrader 荐股 ---\n")
    for period, key in period_key_map:
        print_portfolio_sim(all_picks, report_dates, key, f"荐股持有{period}", out)

    out.write("\n--- 5星趋势股基准 ---\n")
    for period, key in period_key_map:
        print_portfolio_sim(all_trend, report_dates, key, f"趋势股持有{period}", out)

    # ── 趋势股明细 ──
    print_section(f"5星趋势股 Top {baseline_top} 明细", out)
    print_trend_detail(all_trend, out)

    # ── 趋势股统计 ──
    print_section("趋势股基准统计", out)

    out.write("\n【总体】\n")
    print_stats_table([("全部5星趋势股", all_trend)], period_key_map, out)

    # 按情绪等级
    out.write("【按情绪等级】\n")
    emo_levels = sorted(set(t.emotion_level for t in all_trend))
    for emo in emo_levels:
        picks = [t for t in all_trend if t.emotion_level == emo]
        print_stats_table([(f"情绪等级 {emo}", picks)], period_key_map, out)

    # ── 对比 ──
    print_section("PiTrader vs 趋势股基准", out)
    out.write("\n")
    print_comparison(all_picks, all_trend, report_dates, out)

    # ── 回撤 ──
    print_section("回撤分析", out)
    for label, data in [("PiTrader 荐股", all_picks), ("趋势股基准", all_trend)]:
        out.write(f"\n  {label}:\n")
        for period, key in [("3日", "dd3"), ("5日", "dd5")]:
            vals = [getattr(p, key) for p in data if getattr(p, key) is not None]
            s = calc_stats(vals)
            if s:
                out.write(f"    {period}最大回撤均值: {s.avg:.2f}% (样本 {s.n})\n")
                lt10 = sum(1 for v in vals if v < -10)
                lt5 = sum(1 for v in vals if -10 <= v < -5)
                out.write(
                    f"    回撤 >10%: {lt10} 只 ({lt10/s.n*100:.0f}%)  "
                    f"5~10%: {lt5} 只 ({lt5/s.n*100:.0f}%)\n"
                )

    if output_path:
        out.close()
        eprint(f"\n[done] 报告已写入: {output_path}")
    else:
        out.write("\n")


# ── CLI ──────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        description="PiTrader 荐股复盘分析",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--last",
        type=int,
        default=10,
        help="分析最近 N 期报告（默认 10）",
    )
    parser.add_argument(
        "--from",
        dest="from_date",
        help="起始日期 (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--to",
        dest="to_date",
        help="截止日期 (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--baseline-top",
        type=int,
        default=10,
        help="趋势股基准取 Top N（默认 10）",
    )
    parser.add_argument(
        "--output", "-o",
        help="输出到文件（默认 stdout）",
    )
    args = parser.parse_args()

    # 前置检查
    health = api_get("/health")
    if not health:
        eprint("[error] ashare-platform API 不可用，请确认服务在运行")
        sys.exit(1)

    run(
        last_n=args.last,
        from_date=args.from_date,
        to_date=args.to_date,
        baseline_top=args.baseline_top,
        output_path=args.output,
    )


if __name__ == "__main__":
    main()
