#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""
为已有 picks.json 补充缺失的 market_context 和 trade_date 字段。
从 07-final-report.md 提取市场概况信息。

用法:
  uv run --script bin/enrich-picks.py [--dry-run] [YYYY-MM-DD ...]

不指定日期则自动扫描所有有 picks.json 但缺少 market_context 的目录。
"""

import json
import re
import sys
from pathlib import Path

DATA_ROOT = Path.home() / ".local/share/PiTradingAgents/reports"


def extract_market_context(content: str) -> dict:
    ctx: dict = {
        "emotion_stage": None,
        "next_stage_prediction": None,
        "emotion_risk": None,
        "market_env": None,
        "position_cap": None,
        "operation_tone": None,
    }

    m = re.search(r"情绪周期阶段[*]*[:：]\s*[*]*(.+?)(?:\n|$)", content)
    if m:
        ctx["emotion_stage"] = m.group(1).strip().strip("*").strip()

    m = re.search(r"市场环境[*]*[:：]\s*[*]*(.+?)(?:\n|$)", content)
    if m:
        ctx["market_env"] = m.group(1).strip().strip("*").strip()

    m = re.search(r"操作基调[*]*[:：]\s*[*]*(.+?)(?:\n|$)", content)
    if m:
        ctx["operation_tone"] = m.group(1).strip().strip("*").strip()

    m = re.search(r"建议仓位[*]*[:：]\s*[*]*(\d+%?)", content)
    if m:
        cap = m.group(1).strip()
        if not cap.endswith("%"):
            cap += "%"
        ctx["position_cap"] = cap

    stage = (ctx.get("emotion_stage") or "").lower()
    if any(w in stage for w in ["退潮", "冰点"]):
        ctx["emotion_risk"] = "🔴高风险"
    elif any(w in stage for w in ["分歧", "高潮"]):
        ctx["emotion_risk"] = "🟡中风险"
    elif any(w in stage for w in ["主升", "发酵", "启动"]):
        ctx["emotion_risk"] = "🟢低风险"

    return ctx


def find_final_report(report_dir: Path) -> Path | None:
    f = report_dir / "07-final-report.md"
    if f.exists():
        return f
    candidates = sorted(
        report_dir.glob("A股题材交易决策-*.md"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for c in candidates:
        if "_report" not in c.name and "_mobile" not in c.name:
            return c
    return None


def main():
    dry_run = "--dry-run" in sys.argv
    dates = [a for a in sys.argv[1:] if a != "--dry-run"]

    if not dates:
        for d in sorted(DATA_ROOT.iterdir()):
            if not d.is_dir():
                continue
            name = d.name
            if not re.match(r"^\d{4}-\d{2}-\d{2}$", name):
                continue
            picks_file = d / "picks.json"
            if not picks_file.exists():
                continue
            try:
                data = json.loads(picks_file.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                dates.append(name)
                continue
            if "market_context" not in data or "trade_date" not in data:
                dates.append(name)

    if not dates:
        print("所有 picks.json 已包含完整元数据，无需补充。")
        return

    print(f"待补充日期: {', '.join(sorted(dates))}")
    if dry_run:
        print("(dry-run 模式)\n")

    for date in sorted(dates):
        report_dir = DATA_ROOT / date
        picks_file = report_dir / "picks.json"

        if not picks_file.exists():
            print(f"  [{date}] ⏭  无 picks.json")
            continue

        final_report = find_final_report(report_dir)
        if not final_report:
            print(f"  [{date}] ❌ 找不到最终报告")
            continue

        content = final_report.read_text(encoding="utf-8")
        market_ctx = extract_market_context(content)
        data = json.loads(picks_file.read_text(encoding="utf-8"))

        changed = False
        if "trade_date" not in data:
            data["trade_date"] = date
            changed = True
        if "market_context" not in data:
            data["market_context"] = market_ctx
            changed = True
        elif not data["market_context"].get("emotion_stage"):
            data["market_context"] = market_ctx
            changed = True

        # 为已有 picks 补充缺失的标准字段
        standard_pick_fields = {
            "entry_risk": None,
            "ma5_deviation": None,
            "primary_theme": None,
            "theme_cycle": None,
            "theme_rank": None,
            "theme_catalyst": None,
            "theme_sustainability": None,
            "stock_role": None,
            "researcher_rating": None,
            "weighted_score": None,
            "dimensions": None,
            "avoided_conditions_check": None,
            "risk_factors": [],
            "stop_loss": None,
            "target": None,
        }
        for pick in data.get("picks", []):
            for k, default in standard_pick_fields.items():
                if k not in pick:
                    pick[k] = default
                    changed = True

        if not changed:
            print(f"  [{date}] ⏭  已是最新")
            continue

        n_picks = len(data.get("picks", []))
        stage = market_ctx.get("emotion_stage", "?")

        if dry_run:
            print(f"  [{date}] 📋 补充 market_context: {stage}, {n_picks} picks")
        else:
            # 重新排序 key：trade_date, market_context, picks 在前
            ordered = {"trade_date": data["trade_date"], "market_context": data["market_context"]}
            ordered["picks"] = data.get("picks", [])
            for k, v in data.items():
                if k not in ordered:
                    ordered[k] = v
            picks_file.write_text(
                json.dumps(ordered, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            print(f"  [{date}] ✅ 已补充 (stage={stage}, picks={n_picks})")

    print("\n补充完成。")


if __name__ == "__main__":
    main()
