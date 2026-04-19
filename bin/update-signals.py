#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
update-signals.py — 信号库评分更新、条件轮换、选股原则生成

用法:
  # 仅生成选股原则 Markdown（不更新库）
  bin/update-signals.py --library <path> --generate-only

  # 复盘后更新（评分 + 轮换 + 新信号）
  bin/update-signals.py --library <path> \\
      --picks <picks.json> \\
      --signal-scores <score_updates.json> \\
      --eval-date <YYYY-MM-DD> \\
      --decision-date <YYYY-MM-DD> \\
      [--api-url http://127.0.0.1:8000]

输出:
  --generate-only: 打印 selection-criteria.md 内容到 stdout
  更新模式: 更新 library.json 原地，打印变更摘要到 stdout
"""

import argparse
import json
import sys
import urllib.request
from pathlib import Path
from datetime import datetime


# ── 评分区间 ──────────────────────────────────────────────────────────────────

def gain_to_delta(gain_pct: float) -> int:
    """根据多日收益率计算信号分数变化（基于 D+1 开盘价的收益）"""
    if gain_pct >= 10:
        return 3
    elif gain_pct >= 5:
        return 2
    elif gain_pct >= 0:
        return 1
    elif gain_pct >= -5:
        return -1
    elif gain_pct >= -10:
        return -2
    else:
        return -3


# ── API 辅助 ──────────────────────────────────────────────────────────────────

def api_get(base_url: str, endpoint: str):
    try:
        url = f"{base_url}{endpoint}"
        req = urllib.request.Request(url, method="GET")
        req.add_header("Accept", "application/json")
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"[warn] API 请求失败 {endpoint}: {e}", file=sys.stderr)
        return None


def fetch_multi_day_gain(api_url: str, code: str, decision_date: str) -> float | None:
    """
    获取荐股的多日收益（以 D+1 开盘价为基准）。
    优先取 D+5 收益，回退到 D+3、D+1。
    """
    data = api_get(api_url, f"/kline/daily/{code}?days=15")
    if not data or not isinstance(data, list):
        return None

    bars = sorted(data, key=lambda b: b.get('date', ''))
    future_bars = [b for b in bars if b.get('date', '') > decision_date]
    if not future_bars:
        return None

    buy_price = future_bars[0].get('open')
    if not buy_price or buy_price <= 0:
        return None

    # 优先取 D+5，回退 D+3，再回退 D+1
    for idx in (4, 2, 0):
        if idx < len(future_bars):
            close = future_bars[idx].get('close')
            if close is not None and close > 0:
                return round((close / buy_price - 1) * 100, 2)

    return None


# ── 生成 Markdown ─────────────────────────────────────────────────────────────

def generate_criteria_markdown(library: dict) -> str:
    lines = []
    updated = library.get("last_update", {}).get("date") or "尚未更新"
    lines.append(f"# 选股原则 — 最后更新: {updated}\n")

    for kind, label in [("positive", "正向条件（买入信号）"), ("avoid", "回避条件（排除信号）")]:
        signals = library.get(kind, [])
        active = [s for s in signals if s.get("active")]
        inactive = [s for s in signals if not s.get("active")]
        active.sort(key=lambda s: s["score"], reverse=True)

        lines.append(f"## {label}（激活 {len(active)} 条 / 库中共 {len(signals)} 条）\n")
        lines.append("| ID | 条件 | 描述 | 得分 |")
        lines.append("|----|------|------|------|")
        for s in active:
            lines.append(f"| {s['id']} | {s['condition']} | {s['description']} | {s['score']:.1f} |")
        lines.append("")

        if inactive:
            lines.append(f"<details><summary>备用信号（{len(inactive)} 条，未激活）</summary>\n")
            lines.append("| ID | 条件 | 描述 | 得分 |")
            lines.append("|----|------|------|------|")
            for s in sorted(inactive, key=lambda s: s["score"], reverse=True):
                lines.append(f"| {s['id']} | {s['condition']} | {s['description']} | {s['score']:.1f} |")
            lines.append("\n</details>\n")

    # 最近一次更新摘要
    lu = library.get("last_update", {})
    if lu.get("date"):
        lines.append(f"## 最近更新摘要（{lu['date']}）\n")

        score_changes = lu.get("score_changes", [])
        if score_changes:
            lines.append("**评分变化**:")
            for c in score_changes:
                sign = "+" if c["delta"] >= 0 else ""
                lines.append(f"- {c['id']} ({c['condition']}): {sign}{c['delta']} → {c['new_score']:.1f}（{c['reason']}）")
            lines.append("")

        rotations = lu.get("rotations", [])
        if rotations:
            lines.append("**条件轮换**:")
            for r in rotations:
                lines.append(f"- [{r['kind']}] 移除: {r['removed_id']} ({r['removed_condition']}, 得分{r['removed_score']:.1f}) → 补入: {r['added_id']} ({r['added_condition']}, 得分{r['added_score']:.1f})")
            lines.append("")
        else:
            lines.append("**条件轮换**: 无（当前激活集合已最优）\n")

        new_sigs = lu.get("new_signals", [])
        if new_sigs:
            lines.append("**新发现信号**:")
            for ns in new_sigs:
                lines.append(f"- [{ns['type']}] {ns['id']} 「{ns['condition']}」（初始得分5.0，加入备用库）")
            lines.append("")
        else:
            lines.append("**新发现信号**: 无\n")

    return "\n".join(lines)


# ── 轮换逻辑 ──────────────────────────────────────────────────────────────────

MIN_ACTIVE = 10
MAX_ACTIVE = 15


def rotate_if_needed(signals: list[dict], kind: str) -> list[dict]:
    """
    检查并执行一次轮换：
    若最低分激活信号 < 最高分非激活信号，则交换。
    返回 rotation 记录列表（可能为空）。
    """
    active = [s for s in signals if s.get("active")]
    inactive = [s for s in signals if not s.get("active")]

    rotations = []

    if not active or not inactive:
        return rotations

    # 按分数排序
    worst_active = min(active, key=lambda s: s["score"])
    best_inactive = max(inactive, key=lambda s: s["score"])

    if worst_active["score"] < best_inactive["score"] and len(active) <= MAX_ACTIVE:
        worst_active["active"] = False
        best_inactive["active"] = True
        rotations.append({
            "kind": kind,
            "removed_id": worst_active["id"],
            "removed_condition": worst_active["condition"],
            "removed_score": worst_active["score"],
            "added_id": best_inactive["id"],
            "added_condition": best_inactive["condition"],
            "added_score": best_inactive["score"],
        })

    return rotations


# ── 主逻辑 ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", required=True, help="library.json 路径")
    parser.add_argument("--generate-only", action="store_true", help="仅生成 selection-criteria.md，不更新库")
    parser.add_argument("--picks", help="picks.json 路径（用于自动评分正向条件）")
    parser.add_argument("--signal-scores", help="reflector 输出的 score_updates.json 路径")
    parser.add_argument("--eval-date", help="次日交易日（用于查询涨跌幅）")
    parser.add_argument("--decision-date", help="决策日期（用于记录）")
    parser.add_argument("--api-url", default="http://127.0.0.1:8000")
    args = parser.parse_args()

    library_path = Path(args.library)
    if not library_path.exists():
        print(f"[error] library.json 不存在: {library_path}", file=sys.stderr)
        sys.exit(1)

    library = json.loads(library_path.read_text(encoding="utf-8"))

    # ── 仅生成模式 ────────────────────────────────────────────────────────────
    if args.generate_only:
        print(generate_criteria_markdown(library))
        return

    # ── 更新模式 ──────────────────────────────────────────────────────────────
    today = args.decision_date or datetime.now().strftime("%Y-%m-%d")
    all_score_changes = []
    all_rotations = []
    all_new_signals = []

    # 构建 id → signal 索引
    def build_index(kind):
        return {s["id"]: s for s in library.get(kind, [])}

    pos_idx = build_index("positive")
    avd_idx = build_index("avoid")

    # ── 1. 自动评分：正向条件（基于 picks + 多日收益）────────────────────────
    if args.picks and args.decision_date:
        picks_path = Path(args.picks)
        if picks_path.exists():
            picks_data = json.loads(picks_path.read_text(encoding="utf-8"))
            for pick in picks_data.get("picks", []):
                code = pick.get("code", "")
                name = pick.get("name", "")
                gain_pct = fetch_multi_day_gain(args.api_url, code, args.decision_date)
                if gain_pct is None:
                    print(f"[warn] 无法获取 {code} {name} 的多日收益，跳过自动评分", file=sys.stderr)
                    continue
                delta = gain_to_delta(gain_pct)
                reason = f"{name}({code}) 多日收益{'+' if gain_pct>=0 else ''}{gain_pct:.1f}%"
                for cid in pick.get("matched_conditions", []):
                    if cid in pos_idx:
                        sig = pos_idx[cid]
                        old_score = sig["score"]
                        sig["score"] = round(old_score + delta, 1)
                        all_score_changes.append({
                            "id": cid,
                            "condition": sig["condition"],
                            "delta": delta,
                            "new_score": sig["score"],
                            "reason": reason,
                        })

    # ── 2. 应用 reflector 打分（主要用于回避条件）────────────────────────────
    if args.signal_scores:
        scores_path = Path(args.signal_scores)
        if scores_path.exists():
            updates = json.loads(scores_path.read_text(encoding="utf-8"))
            for kind_key, idx in [("positive", pos_idx), ("avoid", avd_idx)]:
                for cid, delta in updates.get(kind_key, {}).items():
                    if cid in idx:
                        sig = idx[cid]
                        old_score = sig["score"]
                        sig["score"] = round(old_score + delta, 1)
                        all_score_changes.append({
                            "id": cid,
                            "condition": sig["condition"],
                            "delta": delta,
                            "new_score": sig["score"],
                            "reason": "reflector评分",
                        })

            # 新发现信号
            for ns in updates.get("new_signals", []):
                kind_key = ns.get("type", "positive")
                signals_list = library.get(kind_key, [])
                kind_ids = {s["id"] for s in signals_list}
                # 生成新 ID
                prefix = "p" if kind_key == "positive" else "a"
                existing_nums = [
                    int(s["id"][1:]) for s in signals_list
                    if s["id"].startswith(prefix) and s["id"][1:].isdigit()
                ]
                new_num = max(existing_nums, default=0) + 1
                new_id = f"{prefix}{new_num:03d}"
                new_sig = {
                    "id": new_id,
                    "condition": ns["condition"],
                    "description": ns.get("description", ns["condition"]),
                    "score": 5.0,
                    "active": False,  # 新信号先进备用库
                    "added_date": today,
                }
                signals_list.append(new_sig)
                all_new_signals.append({
                    "type": kind_key,
                    "id": new_id,
                    "condition": ns["condition"],
                })

    # ── 3. 检查并执行轮换 ─────────────────────────────────────────────────────
    for kind in ["positive", "avoid"]:
        rotations = rotate_if_needed(library.get(kind, []), kind)
        all_rotations.extend(rotations)

    # ── 4. 更新 last_update ───────────────────────────────────────────────────
    library["last_update"] = {
        "date": today,
        "score_changes": all_score_changes,
        "rotations": all_rotations,
        "new_signals": all_new_signals,
    }

    # ── 5. 保存 ───────────────────────────────────────────────────────────────
    library_path.write_text(json.dumps(library, ensure_ascii=False, indent=2), encoding="utf-8")

    # ── 6. 打印变更摘要 ───────────────────────────────────────────────────────
    summary = {
        "date": today,
        "score_changes_count": len(all_score_changes),
        "rotations": all_rotations,
        "new_signals": all_new_signals,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
