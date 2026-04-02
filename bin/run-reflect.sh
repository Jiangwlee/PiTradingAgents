#!/usr/bin/env bash
# run-reflect.sh — 复盘编排脚本
# 用法: run-reflect.sh [--mode text|stream|json] [-m MODEL] [YYYY-MM-DD]
#
# DATE 为复盘日（即"今天"）。脚本自动将前一个交易日作为 DECISION_DATE，
# 复盘日本身作为 EVAL_DATE（评估日）。
# 省略 DATE 时：16:00 后默认今天，之前默认前一交易日。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/bin/lib/pi-runner.sh"
# Python 脚本使用 uv run --script（shebang 驱动，无需 venv）
API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"
PITA_HOME="${PITA_HOME:-$HOME/.local/share/PiTradingAgents}"
PITA_DATA_DIR="${PITA_DATA_DIR:-$PITA_HOME/data}"
PITA_CONFIG_DIR="${PITA_CONFIG_DIR:-$PITA_HOME/config}"
REPORTS_ROOT="$PITA_DATA_DIR/reports"
MEMORY_DIR="$PITA_DATA_DIR/memory"
mkdir -p "$REPORTS_ROOT" "$MEMORY_DIR" "$PITA_CONFIG_DIR"

MODE="text"
MODEL_OVERRIDE=""  # 空 = 使用 Reflector Agent frontmatter 中的模型

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift
            shift
            ;;
        -m|--model)
            MODEL_OVERRIDE="${2:-}"
            shift 2
            ;;
        -*)
            echo "未知选项：$1" >&2
            echo "用法：$0 [--mode text|stream|json] [-m|--model MODEL] [YYYY-MM-DD]" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# ── 解析复盘日期 ──────────────────────────────────────────────────────────────
# REFLECT_DATE: 用户传入的复盘日（即"今天"），省略时自动确定
# DECISION_DATE: 前一个交易日（通过 API 推算），对应 run 生成的报告目录
# EVAL_DATE: 评估日 = REFLECT_DATE（用于拉取实际市场数据）

# 通过 API 查询最近交易日列表（最多 10 天），带降级回退
_get_recent_trade_dates() {
    local n="${1:-10}"
    curl -sf --connect-timeout 3 --max-time 5 "$API_URL/trade-dates/recent?days=$n" 2>/dev/null \
        || echo '{"trade_dates":[]}'
}

# 给定参考日期，返回其前一个交易日
_prev_trading_day() {
    local ref="$1"
    python3 - "$ref" <<PY
import sys, json, urllib.request
ref = sys.argv[1]
try:
    url = "${API_URL}/trade-dates/recent?days=10"
    with urllib.request.urlopen(url, timeout=5) as r:
        dates = json.loads(r.read())["trade_dates"]
    prev = [d for d in dates if d < ref]
    if prev:
        print(prev[-1]); sys.exit(0)
except Exception:
    pass
from datetime import datetime, timedelta
d = datetime.strptime(ref, "%Y-%m-%d") - timedelta(days=1)
while d.weekday() >= 5:
    d -= timedelta(days=1)
print(d.strftime("%Y-%m-%d"))
PY
}

# 自动确定复盘日：16:00 后用今天（若今天是交易日），否则用前一个交易日
_resolve_reflect_date() {
    local today now_hhmm latest_trade
    today=$(date +%Y-%m-%d)
    now_hhmm=$(date +%H%M)
    latest_trade=$(_get_recent_trade_dates 3 | python3 -c \
        "import json,sys; d=json.load(sys.stdin); print(d.get('trade_dates',[''])[-1])" 2>/dev/null || echo "")

    if [[ "$latest_trade" == "$today" && "$now_hhmm" > "1559" ]]; then
        echo "$today"
    else
        _prev_trading_day "$today"
    fi
}

if [[ $# -ge 1 ]]; then
    REFLECT_DATE="$1"
    if ! [[ "$REFLECT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "错误: 日期格式无效，应为 YYYY-MM-DD" >&2
        exit 1
    fi
else
    REFLECT_DATE=$(_resolve_reflect_date)
fi

DECISION_DATE=$(_prev_trading_day "$REFLECT_DATE")
EVAL_DATE="$REFLECT_DATE"

if [[ "$MODE" == "interactive" ]]; then
    echo "[错误] reflect 命令暂不支持 interactive 模式：多角色反思流程无法映射到单一 Pi TUI 会话" >&2
    exit 1
fi

REPORT_DIR="$REPORTS_ROOT/$DECISION_DATE"
STATE_FILE="$REPORT_DIR/state.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=============================================="
echo "PiTradingAgents — 复盘反思 Pipeline"
echo "复盘日期: $REFLECT_DATE"
echo "决策日期: $DECISION_DATE  (前一交易日)"
echo "评估日期: $EVAL_DATE"
echo "报告目录: $REPORT_DIR"
echo "模式: $MODE"
echo "=============================================="

run_reflector() {
    local role="$1"
    local prompt_file="$2"
    local output_file="$3"
    echo "  正在运行 Reflector Agent ($role, mode=$MODE)..."
    export MODEL_OVERRIDE
    PI_JSON_LOG="$TMP_DIR/.reflect-${role}.jsonl" run_agent_node "$MODE" "Reflector:${role}" "$output_file" "$REFLECTOR_AGENT" "@$prompt_file"
}

parse_reflection_json() {
    local input_file="$1"
    local output_file="$2"
    python3 - "$input_file" <<'PY' > "$output_file"
import json
import re
import sys
from pathlib import Path

input_file = sys.argv[1]
content = Path(input_file).read_text(encoding='utf-8')
data = None

match = re.search(r'```json\s*(.*?)\s*```', content, re.DOTALL)
if match:
    try:
        data = json.loads(match.group(1))
    except json.JSONDecodeError:
        data = None

if data is None:
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        data = None

if data is None:
    match = re.search(r'\{.*\}', content, re.DOTALL)
    if match:
        try:
            data = json.loads(match.group(0))
        except json.JSONDecodeError:
            data = None

print(json.dumps(data, ensure_ascii=False, indent=2) if data else "null")
PY
}

build_market_situation() {
    python3 - <<PY
import json
import re
from pathlib import Path

state = json.loads(Path("$STATE_FILE").read_text(encoding='utf-8'))
emotion_report = state.get("reports", {}).get("01-emotion-report.md", "")
theme = (state.get("top_themes") or [{}])[0]
theme_name = theme.get("name", "无主线题材")
theme_stage = theme.get("stage", "")
stocks = theme.get("key_stocks", [])

def pick(pattern, default=""):
    m = re.search(pattern, emotion_report)
    return m.group(1) if m else default

limit_up = pick(r"涨停家数\s*\|\s*([0-9]+)")
limit_down = pick(r"跌停家数\s*\|\s*([0-9]+)")
seal_rate = pick(r"封板率\s*\|\s*([0-9]+%?)")
blowup_rate = pick(r"炸板率\s*\|\s*([0-9]+%?)")
adv_rate = pick(r"晋级率\(2→3\)\s*\|\s*([0-9]+%?(?:\s*\([^)]+\))?)")
score = pick(r"情绪得分仅\s*([0-9.]+)")

stock_part = " ".join(stocks[:2])
parts = [
    state.get("emotion_stage", ""),
    f"涨停{limit_up}家" if limit_up else "",
    f"封板率{seal_rate}" if seal_rate else "",
    f"炸板率{blowup_rate}" if blowup_rate else "",
    f"{theme_name}题材{theme_stage}" if theme_name and theme_stage else "",
    stock_part,
    f"跌停{limit_down}家" if limit_down else "",
    f"情绪得分{score}" if score else "",
    f"二进三晋级率{adv_rate}" if adv_rate else "",
]
print(" ".join(p for p in parts if p).strip())
PY
}

build_role_context() {
    local role="$1"
    python3 - <<PY
import json
from pathlib import Path

state = json.loads(Path("$STATE_FILE").read_text(encoding='utf-8'))
role = "$role"

if role == "bull":
    points = state.get("bull_key_points", [])[:2]
    print("基于" + "；".join(points) + "，主张偏多并预判反弹或主线延续。")
elif role == "bear":
    points = state.get("bear_key_points", [])[:2]
    print("基于" + "；".join(points) + "，主张防守或回避并强调风险释放尚未结束。")
elif role == "judge":
    themes = "、".join(t.get("name", "") for t in state.get("top_themes", [])[:3] if t.get("name"))
    print(f"在{state.get('emotion_stage', '')}和{state.get('market_env', '')}判断下，给出{state.get('position', '')}仓位建议，并筛选Top题材为{themes}。")
elif role == "trader":
    stocks = [f"{item.get('name', '')}:{item.get('signal', '')}" for item in state.get("recommended_stocks", [])[:4]]
    print(f"在{state.get('market_env', '')}基调下制定交易计划，建议仓位{state.get('position', '')}，核心标的与信号为" + "；".join(stocks) + "。")
PY
}

build_role_input() {
    local role="$1"
    local output_file="$2"
    case "$role" in
        bull)
            cp "$REPORT_DIR/05a-bull-argument.md" "$output_file"
            ;;
        bear)
            cp "$REPORT_DIR/05b-bear-argument.md" "$output_file"
            ;;
        judge)
            cp "$REPORT_DIR/05-market-debate.md" "$output_file"
            ;;
        trader)
            # 优先查找重命名后的最终报告，回退到旧文件名
            local final_report
            final_report=$(ls -t "$REPORT_DIR"/PiTrader复盘-*.md 2>/dev/null | head -1 || true)
            if [[ -n "$final_report" ]]; then
                cp "$final_report" "$output_file"
            else
                cp "$REPORT_DIR/07-final-report.md" "$output_file"
            fi
            ;;
    esac
}

build_validation_input() {
    local role="$1"
    local output_file="$2"
    python3 - <<PY > "$output_file"
import json
from pathlib import Path

role = "$role"
state = json.loads(Path("$STATE_FILE").read_text(encoding='utf-8'))
signals = json.loads(Path("$SIGNALS_FILE").read_text(encoding='utf-8'))
actual = json.loads(Path("$ACTUAL_DATA_FILE").read_text(encoding='utf-8'))

result = {
    "signals": signals,
    "actual_data": actual,
}

if role == "bull":
    result["counterpoints"] = {
        "bear_key_points": state.get("bear_key_points", [])[:5]
    }
elif role == "bear":
    result["counterpoints"] = {
        "bull_key_points": state.get("bull_key_points", [])[:5]
    }
elif role == "judge":
    result["judge_context"] = {
        "judge_verdict": state.get("judge_verdict", ""),
        "position": state.get("position", ""),
        "top_themes": state.get("top_themes", [])
    }
elif role == "trader":
    result["trader_context"] = {
        "recommended_stocks": state.get("recommended_stocks", []),
        "position": state.get("position", "")
    }

print(json.dumps(result, ensure_ascii=False, indent=2))
PY
}

echo ""
echo "=== 步骤 1: 验证前置条件 ==="

if [[ ! -f "$STATE_FILE" ]]; then
    echo "  state.json 不存在，尝试自动生成..."
    if "$PROJECT_ROOT/bin/save-state.py" "$REPORT_DIR" "$DECISION_DATE" > "$STATE_FILE" 2>/dev/null; then
        echo "  ✓ 已自动生成 state.json"
    else
        echo "  ✗ 无法生成 state.json，请确保 pipeline 已完整运行" >&2
        exit 1
    fi
else
    echo "  ✓ state.json 存在"
fi

echo "  检查 API 健康状态..."
if curl -sf --connect-timeout 3 --max-time 5 "$API_URL/health" > /dev/null 2>&1; then
    echo "  ✓ API 服务可用"
else
    echo "  ⚠ 警告: API 服务不可用 ($API_URL)，信号计算可能失败"
fi

echo ""
echo "=== 步骤 2: 确认日期链 ==="

echo "  决策日期: $DECISION_DATE"
echo "  评估日期: $EVAL_DATE"

echo ""
echo "=== 步骤 3: 计算结果信号 ==="

SIGNALS_FILE="$REPORT_DIR/signals.json"
if "$PROJECT_ROOT/bin/calc-signals.py" --state "$STATE_FILE" --eval-date "$EVAL_DATE" > "$SIGNALS_FILE" 2>/dev/null; then
    echo "  ✓ 信号计算完成: $SIGNALS_FILE"
else
    echo "  ✗ 信号计算失败" >&2
    exit 1
fi

echo ""
echo "=== 步骤 4: 获取次日实际市场数据 ==="

ACTUAL_DATA_FILE="$REPORT_DIR/actual-data.json"
python3 - <<PY > "$ACTUAL_DATA_FILE" 2>/dev/null || echo "{}" > "$ACTUAL_DATA_FILE"
import urllib.request
import json
import sys

API_BASE = "$API_URL"
EVAL_DATE = "$EVAL_DATE"

def api_get(endpoint):
    try:
        url = f"{API_BASE}{endpoint}"
        req = urllib.request.Request(url, method="GET")
        req.add_header("Accept", "application/json")
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return None

result = {}
emotion = api_get(f"/market-emotion/daily/{EVAL_DATE}")
if emotion:
    result["market_emotion"] = {
        "stage": emotion.get("emotion_stage", ""),
        "limit_up_count": emotion.get("limit_up_count", 0),
        "limit_down_count": emotion.get("limit_down_count", 0),
        "seal_rate": emotion.get("seal_rate", 0),
        "blowup_rate": emotion.get("blowup_rate", 0),
        "emotion_score": emotion.get("emotion_score", 0)
    }

themes = api_get(f"/theme-emotion/daily?trade_date={EVAL_DATE}&limit=20")
if themes and isinstance(themes, list):
    result["theme_ranking"] = [
        {
            "name": t.get("theme_name", ""),
            "stage": t.get("stage", ""),
            "leader": t.get("leader_stock", ""),
            "emotion_score": t.get("emotion_score", 0)
        }
        for t in themes[:10]
    ]

limit_up_stocks = api_get(f"/stocks/limit-up?trade_date={EVAL_DATE}")
if limit_up_stocks and isinstance(limit_up_stocks, list):
    result["limit_up_stocks"] = [
        {
            "code": s.get("code", ""),
            "name": s.get("name", ""),
            "limit_up_days": s.get("limit_up_days", 1)
        }
        for s in limit_up_stocks[:15]
    ]

print(json.dumps(result, ensure_ascii=False, indent=2))
PY

echo "  ✓ 实际数据已保存: $ACTUAL_DATA_FILE"

echo ""
echo "=== 步骤 5: 调用 Reflector Agent 生成反思 ==="

REFLECTOR_AGENT="$PROJECT_ROOT/agents/reflection/reflector.md"
if [[ ! -f "$REFLECTOR_AGENT" ]]; then
    echo "  ✗ Reflector Agent 不存在: $REFLECTOR_AGENT" >&2
    exit 1
fi

MARKET_SITUATION="$(build_market_situation)"
REFLECTION_DIR="$REPORT_DIR/reflections"
mkdir -p "$REFLECTION_DIR"

ROLE_OUTPUTS=()
for role in bull bear judge trader; do
    echo ""
    echo "  [角色] $role"

    ROLE_CONTEXT_FILE="$TMP_DIR/${role}-context.txt"
    ROLE_INPUT_FILE="$TMP_DIR/${role}-input.md"
    VALIDATION_FILE="$TMP_DIR/${role}-validation.json"
    PROMPT_FILE="$REFLECTION_DIR/${role}-prompt.txt"
    OUTPUT_FILE="$REFLECTION_DIR/${role}.json"

    build_role_context "$role" > "$ROLE_CONTEXT_FILE"
    build_role_input "$role" "$ROLE_INPUT_FILE"
    build_validation_input "$role" "$VALIDATION_FILE"

    {
        echo "ROLE: $role"
        echo ""
        echo "MARKET_SITUATION:"
        echo "$MARKET_SITUATION"
        echo ""
        echo "ROLE_CONTEXT:"
        cat "$ROLE_CONTEXT_FILE"
        echo ""
        echo "ROLE_INPUT:"
        cat "$ROLE_INPUT_FILE"
        echo ""
        echo "VALIDATION_INPUT:"
        echo '```json'
        cat "$VALIDATION_FILE"
        echo '```'
    } > "$PROMPT_FILE"

    run_reflector "$role" "$PROMPT_FILE" "$OUTPUT_FILE"
    parse_reflection_json "$OUTPUT_FILE" "$OUTPUT_FILE.normalized"
    mv "$OUTPUT_FILE.normalized" "$OUTPUT_FILE"

    if [[ ! -s "$OUTPUT_FILE" ]]; then
        echo "  ✗ $role 反思生成失败" >&2
        exit 1
    fi

    ROLE_OUTPUTS+=("$role:$OUTPUT_FILE")
    echo "  ✓ 已生成: $OUTPUT_FILE"
done

echo ""
echo "=== 步骤 6: 提取反思结果并存储到记忆 ==="

BATCH_FILE="$TMP_DIR/reflection-batch.json"
echo '[]' > "$BATCH_FILE"

for item in "${ROLE_OUTPUTS[@]}"; do
    role="${item%%:*}"
    file="${item#*:}"
    extract_file="$TMP_DIR/extract-${role}.json"
    "$PROJECT_ROOT/bin/extract-reflections.py" "$file" "$DECISION_DATE" "$role" > "$extract_file"
    python3 - <<PY
import json
from pathlib import Path
batch_path = Path("$BATCH_FILE")
extract_path = Path("$extract_file")
batch = json.loads(batch_path.read_text(encoding='utf-8'))
if extract_path.exists() and extract_path.read_text(encoding='utf-8').strip():
    batch.extend(json.loads(extract_path.read_text(encoding='utf-8')))
batch_path.write_text(json.dumps(batch, ensure_ascii=False, indent=2), encoding='utf-8')
PY
done

REFLECTION_OUTPUT="$REPORT_DIR/08-reflection.md"
python3 - <<PY > "$REFLECTION_OUTPUT"
import json
from pathlib import Path

result = {"reflections": []}
for role in ["bull", "bear", "judge", "trader"]:
    payload = json.loads(Path("$REFLECTION_DIR").joinpath(f"{role}.json").read_text(encoding='utf-8'))
    payload["role"] = role
    result["reflections"].append(payload)

print(json.dumps(result, ensure_ascii=False, indent=2))
PY

if "$PROJECT_ROOT/bin/memory.py" --data-dir "$MEMORY_DIR" store-batch < "$BATCH_FILE" 2>&1; then
    echo "  ✓ 反思记忆已存储"
else
    echo "  ⚠ 警告: 记忆存储可能失败，但继续完成报告"
fi

echo ""
echo "=== 步骤 7: 更新信号库评分和条件轮换 ==="

SIGNALS_DIR="$PITA_DATA_DIR/signals"
LIBRARY_FILE="$SIGNALS_DIR/library.json"

# 初始化信号库（首次运行）
mkdir -p "$SIGNALS_DIR"
if [[ ! -f "$LIBRARY_FILE" ]]; then
    if [[ -f "$PROJECT_ROOT/data/signals/library.json" ]]; then
        cp "$PROJECT_ROOT/data/signals/library.json" "$LIBRARY_FILE"
        echo "  ✓ 已初始化信号库"
    else
        echo "  ⚠ 未找到信号库 seed 文件，跳过信号更新"
        LIBRARY_FILE=""
    fi
fi

if [[ -n "$LIBRARY_FILE" && -f "$LIBRARY_FILE" ]]; then
    # 从 trader 反思中提取信号评分和新信号
    TRADER_REFLECTION="$REFLECTION_DIR/trader.json"
    SCORE_UPDATES_FILE="$REPORT_DIR/score-updates.json"

    python3 - <<PY > "$SCORE_UPDATES_FILE" 2>/dev/null || echo '{"positive":{},"avoid":{},"new_signals":[]}' > "$SCORE_UPDATES_FILE"
import json
from pathlib import Path

trader_path = Path("$TRADER_REFLECTION")
if not trader_path.exists():
    print('{"positive":{},"avoid":{},"new_signals":[]}')
    exit()

data = json.loads(trader_path.read_text(encoding='utf-8'))
result = {
    "positive": data.get("signal_scores", {}).get("positive", {}),
    "avoid":    data.get("signal_scores", {}).get("avoid", {}),
    "new_signals": data.get("new_signals", []),
}
print(json.dumps(result, ensure_ascii=False, indent=2))
PY

    # 获取 picks.json 路径
    PICKS_FILE="$REPORT_DIR/picks.json"

    UPDATE_SUMMARY_FILE="$REPORT_DIR/signal-update-summary.json"
    UPDATE_ARGS=(
        --library "$LIBRARY_FILE"
        --signal-scores "$SCORE_UPDATES_FILE"
        --decision-date "$DECISION_DATE"
        --eval-date "$EVAL_DATE"
        --api-url "$API_URL"
    )
    if [[ -f "$PICKS_FILE" ]]; then
        UPDATE_ARGS+=(--picks "$PICKS_FILE")
    fi

    if "$PROJECT_ROOT/bin/update-signals.py" "${UPDATE_ARGS[@]}" > "$UPDATE_SUMMARY_FILE" 2>/dev/null; then
        ROTATIONS=$(python3 -c "import json; d=json.load(open('$UPDATE_SUMMARY_FILE')); print(len(d.get('rotations',[])))" 2>/dev/null || echo "?")
        NEW_SIGS=$(python3 -c "import json; d=json.load(open('$UPDATE_SUMMARY_FILE')); print(len(d.get('new_signals',[])))" 2>/dev/null || echo "?")
        echo "  ✓ 信号库已更新: 轮换=${ROTATIONS}条，新信号=${NEW_SIGS}条"
    else
        echo "  ⚠ 信号库更新失败，但不影响记忆存储"
    fi
else
    echo "  ⚠ 信号库不存在，跳过更新"
fi

echo ""
echo "=============================================="
echo "复盘反思 Pipeline 执行完成！"
echo "=============================================="
echo ""
echo "输出文件:"
echo "  信号报告:    $SIGNALS_FILE"
echo "  实际数据:    $ACTUAL_DATA_FILE"
echo "  汇总反思:    $REFLECTION_OUTPUT"
echo "  角色反思:    $REFLECTION_DIR/{bull,bear,judge,trader}.json
  反思提示词:  $REFLECTION_DIR/{bull,bear,judge,trader}-prompt.txt"
echo "  记忆存储:    $MEMORY_DIR/{bull,bear,judge,trader}.jsonl"
echo "  信号库:      $LIBRARY_FILE"
[[ -f "${UPDATE_SUMMARY_FILE:-}" ]] && echo "  更新摘要:    $UPDATE_SUMMARY_FILE"
