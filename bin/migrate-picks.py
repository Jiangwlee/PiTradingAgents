#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""
从旧格式最终报告中提取荐股数据，生成 picks.json。

用法:
  uv run --script bin/migrate-picks.py [--dry-run] [YYYY-MM-DD ...]

不指定日期则自动扫描所有缺少 picks.json 的报告目录。
"""

import json
import re
import sys
from pathlib import Path

DATA_ROOT = Path.home() / ".local/share/PiTradingAgents/reports"

# ── signal 映射 ──────────────────────────────────────────────

SIGNAL_MAP = {
    "买入": "buy",
    "低吸": "buy",
    "重点关注": "watch",
    "关注": "watch",
    "持有": "hold",
    "观望": "observe",
    "回避": "avoid",
}


def normalize_signal(raw: str) -> str:
    """'买入（分批）' → 'buy', '持有/观望' → 'hold'"""
    raw = raw.strip().strip("*")
    # 取斜杠前第一个
    first = raw.split("/")[0].strip()
    # 去掉括号注释
    first = re.sub(r"[（(].*?[)）]", "", first).strip()
    for cn, en in SIGNAL_MAP.items():
        if cn in first:
            return en
    return "observe"  # 兜底


def count_stars(text: str) -> int:
    return text.count("⭐")


def stars_to_confidence(n: int) -> str:
    if n >= 5:
        return "high"
    elif n >= 4:
        return "medium"
    return "low"


# ── 市场概况提取 ─────────────────────────────────────────────

def extract_market_context(content: str, trade_date: str) -> dict:
    ctx: dict = {
        "emotion_stage": None,
        "next_stage_prediction": None,
        "emotion_risk": None,
        "market_env": None,
        "position_cap": None,
        "operation_tone": None,
    }

    # 情绪周期阶段
    m = re.search(r"情绪周期阶段[*]*[:：]\s*[*]*(.+?)(?:\n|$)", content)
    if m:
        ctx["emotion_stage"] = m.group(1).strip().strip("*").strip()

    # 市场环境
    m = re.search(r"市场环境[*]*[:：]\s*[*]*(.+?)(?:\n|$)", content)
    if m:
        ctx["market_env"] = m.group(1).strip().strip("*").strip()

    # 操作基调
    m = re.search(r"操作基调[*]*[:：]\s*[*]*(.+?)(?:\n|$)", content)
    if m:
        ctx["operation_tone"] = m.group(1).strip().strip("*").strip()

    # 建议仓位
    m = re.search(r"建议仓位[*]*[:：]\s*[*]*(\d+%?)", content)
    if m:
        cap = m.group(1).strip()
        if not cap.endswith("%"):
            cap += "%"
        ctx["position_cap"] = cap

    # 推断 emotion_risk
    stage = (ctx.get("emotion_stage") or "").lower()
    if any(w in stage for w in ["退潮", "冰点"]):
        ctx["emotion_risk"] = "🔴高风险"
    elif any(w in stage for w in ["分歧", "高潮"]):
        ctx["emotion_risk"] = "🟡中风险"
    elif any(w in stage for w in ["主升", "发酵", "启动"]):
        ctx["emotion_risk"] = "🟢低风险"

    return ctx


# ── 核心标的池表格解析 ───────────────────────────────────────

TABLE_HEADER_RE = re.compile(
    r"\|\s*代码\s*\|\s*名称\s*\|\s*所属题材\s*\|\s*星级\s*\|\s*交易信号\s*\|\s*关注理由\s*\|"
)


def parse_stock_table(content: str) -> list[dict]:
    """解析 Markdown 表格行"""
    stocks = []
    lines = content.split("\n")
    in_table = False
    for line in lines:
        if TABLE_HEADER_RE.search(line):
            in_table = True
            continue
        if in_table:
            # 跳过分隔行
            if re.match(r"\s*\|[-\s|:]+\|\s*$", line):
                continue
            # 空行或新章节结束表格
            if not line.strip() or (line.startswith("#") and not line.startswith("|")):
                in_table = False
                continue
            if not line.strip().startswith("|"):
                in_table = False
                continue

            cells = [c.strip() for c in line.split("|")]
            # 去除首尾空 cell (因为 | 开头和 | 结尾)
            cells = [c for c in cells if c != ""]
            if len(cells) < 6:
                continue

            code = cells[0].strip()
            name = cells[1].strip()
            themes_raw = cells[2].strip()
            stars_raw = cells[3].strip()
            signal_raw = cells[4].strip()
            reason = cells[5].strip()

            n_stars = count_stars(stars_raw)
            themes = [t.strip() for t in themes_raw.split("/")]

            stocks.append({
                "code": code,
                "name": name,
                "themes": themes,
                "stars": n_stars,
                "signal_raw": signal_raw,
                "signal": normalize_signal(signal_raw),
                "confidence": stars_to_confidence(n_stars),
                "reason": reason,
            })
    return stocks


# ── 标的分类解析（提取 stock_role）────────────────────────────

def extract_stock_roles(content: str, stocks: list[dict] | None = None) -> dict[str, str]:
    """返回 {code: role}。先按代码匹配，再按名称匹配。"""
    roles: dict[str, str] = {}
    # 构建 name→code 映射用于名称回退
    name_to_code: dict[str, str] = {}
    if stocks:
        for s in stocks:
            name_to_code[s["name"]] = s["code"]

    role_map = {
        "龙头博弈": "龙头",
        "补涨挖掘": "补涨",
        "趋势跟踪": "中军",
    }
    for role_cn, role_label in role_map.items():
        pattern = rf"\*\*{role_cn}\*\*[:：]\s*(.+?)(?:\n\s*\n|\n\s*-\s*\*\*|\Z)"
        m = re.search(pattern, content, re.DOTALL)
        if not m:
            continue
        block = m.group(1)
        # 先提取6位代码
        codes = re.findall(r"\b(\d{6})\b", block)
        for c in codes:
            if c not in roles:
                roles[c] = role_label
        # 再按名称匹配（处理只写名称不写代码的情况）
        for name, code in name_to_code.items():
            if code not in roles and name in block:
                roles[code] = role_label
    return roles


# ── 构造 picks.json ──────────────────────────────────────────

def build_picks_json(content: str, trade_date: str) -> dict:
    market_ctx = extract_market_context(content, trade_date)
    stocks = parse_stock_table(content)
    roles = extract_stock_roles(content, stocks)

    picks = []
    for s in stocks:
        pick = {
            "code": s["code"],
            "name": s["name"],
            "signal": s["signal"],
            "confidence": s["confidence"],

            "entry_risk": None,
            "ma5_deviation": None,

            "primary_theme": s["themes"][0] if s["themes"] else None,
            "theme_cycle": None,
            "theme_rank": None,
            "theme_catalyst": None,
            "theme_sustainability": None,

            "stock_role": roles.get(s["code"]),
            "researcher_rating": None,
            "weighted_score": None,
            "dimensions": None,

            "matched_conditions": [],
            "avoided_conditions_check": None,

            "reasons": {
                "market": None,
                "fundamental": None,
                "theme": s["reason"],
                "trend": None,
                "short_term": None,
                "sector": None,
            },

            "risk_factors": [],
            "stop_loss": None,
            "target": None,
        }
        picks.append(pick)

    return {
        "trade_date": trade_date,
        "market_context": market_ctx,
        "picks": picks,
        "_migration": {
            "source": "old_format_report",
            "note": "从旧格式核心标的池表格自动迁移，缺少 entry_risk/ma5_deviation/dimensions/matched_conditions 等字段"
        },
    }


# ── 查找最终报告文件 ─────────────────────────────────────────

def find_final_report(report_dir: Path) -> Path | None:
    # 优先 07-final-report.md
    f = report_dir / "07-final-report.md"
    if f.exists():
        return f
    # 查找 A股题材交易决策-*.md (不包含 _report/_mobile)
    candidates = sorted(
        report_dir.glob("A股题材交易决策-*.md"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for c in candidates:
        if "_report" not in c.name and "_mobile" not in c.name:
            return c
    # 查找 PiTrader复盘-*.md 的旁边是否有 07-final-report.md
    return None


# ── main ─────────────────────────────────────────────────────

def main():
    dry_run = "--dry-run" in sys.argv
    dates = [a for a in sys.argv[1:] if a != "--dry-run"]

    if not dates:
        # 自动扫描缺少 picks.json 的目录
        for d in sorted(DATA_ROOT.iterdir()):
            if not d.is_dir():
                continue
            name = d.name
            # 跳过非日期目录
            if not re.match(r"^\d{4}-\d{2}-\d{2}$", name):
                continue
            picks_file = d / "picks.json"
            if not picks_file.exists():
                dates.append(name)

    if not dates:
        print("所有报告目录都已有 picks.json，无需迁移。")
        return

    print(f"待迁移日期: {', '.join(dates)}")
    if dry_run:
        print("(dry-run 模式，不写入文件)\n")

    for date in sorted(dates):
        report_dir = DATA_ROOT / date
        if not report_dir.exists():
            print(f"  [{date}] ❌ 目录不存在: {report_dir}")
            continue

        final_report = find_final_report(report_dir)
        if not final_report:
            print(f"  [{date}] ❌ 找不到最终报告")
            continue

        content = final_report.read_text(encoding="utf-8")
        picks_data = build_picks_json(content, date)
        n_picks = len(picks_data["picks"])

        if dry_run:
            print(f"  [{date}] 📋 {final_report.name} → {n_picks} 只标的")
            for p in picks_data["picks"]:
                print(f"    {p['code']} {p['name']} | {p['signal']} | {p['confidence']} | {p['primary_theme']} | role={p['stock_role']}")
            if picks_data["market_context"]["emotion_stage"]:
                mc = picks_data["market_context"]
                print(f"    市场: {mc['emotion_stage']} / {mc['market_env']} / {mc['operation_tone']} / 仓位 {mc['position_cap']}")
        else:
            out_file = report_dir / "picks.json"
            out_file.write_text(
                json.dumps(picks_data, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            print(f"  [{date}] ✅ 写入 {out_file} ({n_picks} 只标的)")

    print("\n迁移完成。")


if __name__ == "__main__":
    main()
