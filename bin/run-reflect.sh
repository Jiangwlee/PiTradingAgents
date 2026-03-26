#!/usr/bin/env bash
# run-reflect.sh — 复盘编排脚本
# 对比决策日预测与次日实际结果，按角色独立生成结构化反思并存储到记忆

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Python 脚本使用 uv run --script（shebang 驱动，无需 venv）
API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"
PITA_HOME="${PITA_HOME:-$HOME/.local/share/PiTradingAgents}"
PITA_DATA_DIR="${PITA_DATA_DIR:-$PITA_HOME/data}"
PITA_CONFIG_DIR="${PITA_CONFIG_DIR:-$PITA_HOME/config}"
REPORTS_ROOT="$PITA_DATA_DIR/reports"
MEMORY_DIR="$PITA_DATA_DIR/memory"
mkdir -p "$REPORTS_ROOT" "$MEMORY_DIR" "$PITA_CONFIG_DIR"

VERBOSE=false
MODEL_OVERRIDE=""  # 空 = 使用 Reflector Agent frontmatter 中的模型

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -m|--model)
            MODEL_OVERRIDE="${2:-}"
            shift 2
            ;;
        -*)
            echo "未知选项：$1" >&2
            echo "用法：$0 [-v|--verbose] [-m|--model MODEL] YYYY-MM-DD" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 1 ]]; then
    echo "错误: 缺少决策日期参数" >&2
    echo "用法: $0 [-v|--verbose] YYYY-MM-DD" >&2
    exit 1
fi

DECISION_DATE="$1"
if ! [[ "$DECISION_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "错误: 日期格式无效，应为 YYYY-MM-DD" >&2
    exit 1
fi

REPORT_DIR="$REPORTS_ROOT/$DECISION_DATE"
STATE_FILE="$REPORT_DIR/state.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=============================================="
echo "PiTradingAgents — 复盘反思 Pipeline"
echo "决策日期: $DECISION_DATE"
echo "报告目录: $REPORT_DIR"
$VERBOSE && echo "模式: verbose"
echo "=============================================="

extract_text_from_pi_jsonl() {
    local jsonl_file="$1"
    local output_file="$2"
    python3 - <<PY > "$output_file"
import json
text = ''
for line in open("$jsonl_file", encoding='utf-8'):
    try:
        ev = json.loads(line.strip())
        tp = ev.get('type', '')
        if tp in ('message_update', 'message_end'):
            parts = ev.get('message', {}).get('content', [])
            t = ''.join(p.get('text', '') for p in parts if p.get('type') == 'text')
            if t:
                text = t
    except Exception:
        pass
print(text, end='')
PY
}

run_reflector() {
    local role="$1"
    local prompt_file="$2"
    local output_file="$3"

    if $VERBOSE; then
        local tmp_jsonl="$TMP_DIR/.reflect-${role}.jsonl"
        echo "  正在运行 Reflector Agent ($role, verbose 模式)..."
        pi --no-session --mode json \
           --model "$MODEL" \
           --tools "$TOOLS" \
           --system-prompt "$SYSTEM_PROMPT" \
           --skill "$PROJECT_ROOT/skills/ashare-data" \
           "@$prompt_file" \
            | tee "$tmp_jsonl" \
            | pi-watch 2>&1 \
            | sed "s/^/[Reflector:${role}] /"
        extract_text_from_pi_jsonl "$tmp_jsonl" "$output_file"
    else
        echo "  正在运行 Reflector Agent ($role)..."
        pi --no-session --print \
           --model "$MODEL" \
           --tools "$TOOLS" \
           --system-prompt "$SYSTEM_PROMPT" \
           --skill "$PROJECT_ROOT/skills/ashare-data" \
           "@$prompt_file" \
            > "$output_file" 2>/dev/null
    fi
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
            final_report=$(ls -t "$REPORT_DIR"/A股题材交易决策-*.md 2>/dev/null | head -1)
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
echo "=== 步骤 2: 计算评估日期 ==="

EVAL_DATE=$(python3 - <<PY
from datetime import datetime, timedelta
decision_date = datetime.strptime("$DECISION_DATE", "%Y-%m-%d")
next_date = decision_date + timedelta(days=1)
while next_date.weekday() >= 5:
    next_date += timedelta(days=1)
print(next_date.strftime("%Y-%m-%d"))
PY
)

echo "  决策日期: $DECISION_DATE"
echo "  评估日期: $EVAL_DATE (下一个交易日)"

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

if [[ -n "$MODEL_OVERRIDE" ]]; then
    MODEL="$MODEL_OVERRIDE"
else
    MODEL="$(awk -F': ' '/^model:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$REFLECTOR_AGENT")"
fi
TOOLS="$(awk -F': ' '/^tools:/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$REFLECTOR_AGENT")"
SYSTEM_PROMPT="$(awk 'BEGIN{n=0} /^---/{n++; next} n>=2{print}' "$REFLECTOR_AGENT")"
case "$MODEL" in
    kimi-k2-thinking) MODEL="kimi-coding/kimi-k2-thinking" ;;
esac

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
    PROMPT_FILE="$TMP_DIR/${role}-reflect-prompt.txt"
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
echo "=============================================="
echo "复盘反思 Pipeline 执行完成！"
echo "=============================================="
echo ""
echo "输出文件:"
echo "  信号报告:    $SIGNALS_FILE"
echo "  实际数据:    $ACTUAL_DATA_FILE"
echo "  汇总反思:    $REFLECTION_OUTPUT"
echo "  角色反思:    $REFLECTION_DIR/{bull,bear,judge,trader}.json"
echo "  记忆存储:    $MEMORY_DIR/{bull,bear,judge,trader}.jsonl"
