#!/usr/bin/env bash
# run-inject.sh — 经验注入编排脚本
# 用法: run-inject.sh [--mode stream|text|json] [-m MODEL] [--role ROLE] "经验文本"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/bin/lib/pi-runner.sh"

PITA_HOME="${PITA_HOME:-$HOME/.local/share/PiTradingAgents}"
PITA_DATA_DIR="${PITA_DATA_DIR:-$PITA_HOME/data}"
MEMORY_DIR="$PITA_DATA_DIR/memory"
mkdir -p "$MEMORY_DIR"

MODE="stream"
MODEL_OVERRIDE=""
ROLE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        -m|--model)
            MODEL_OVERRIDE="${2:-}"
            shift 2
            ;;
        --role)
            ROLE="${2:-}"
            shift 2
            ;;
        -*)
            echo "未知选项：$1" >&2
            echo "用法：$0 [--mode stream|text|json] [-m|--model MODEL] [--role ROLE] \"经验文本\"" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 1 ]] || [[ -z "${1:-}" ]]; then
    echo "错误: 缺少经验文本参数" >&2
    echo "用法: $0 [--mode stream|text|json] [-m|--model MODEL] [--role ROLE] \"经验文本\"" >&2
    exit 1
fi

EXPERIENCE_TEXT="$1"

# 校验 role 白名单
if [[ -n "$ROLE" ]]; then
    case "$ROLE" in
        bull|bear|judge|trader) ;;
        *)
            echo "错误: 无效角色 '$ROLE'，必须为 bull/bear/judge/trader" >&2
            exit 1
            ;;
    esac
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=============================================="
echo "PiTradingAgents — 经验注入"
echo "经验: ${EXPERIENCE_TEXT:0:60}..."
echo "角色: ${ROLE:-AI 自动判定}"
echo "模式: $MODE"
echo "=============================================="

# ── 步骤 1: 构造 prompt ──────────────────────────────────────────────────────

PROMPT_FILE="$TMP_DIR/inject-prompt.txt"
{
    echo "请研究并验证以下交易经验："
    echo ""
    echo '"""'
    echo "$EXPERIENCE_TEXT"
    echo '"""'
    echo ""
    if [[ -n "$ROLE" ]]; then
        echo "请将此经验归类到角色：${ROLE}"
    else
        echo "请根据经验内容自动判定最适合的角色（bull/bear/judge/trader）"
    fi
} > "$PROMPT_FILE"

# ── 步骤 2: 调用 experience-injector Agent ────────────────────────────────────

INJECTOR_AGENT="$PROJECT_ROOT/agents/reflection/experience-injector.md"
if [[ ! -f "$INJECTOR_AGENT" ]]; then
    echo "✗ Agent 文件不存在: $INJECTOR_AGENT" >&2
    exit 1
fi

OUTPUT_FILE="$TMP_DIR/inject-output.md"
export MODEL_OVERRIDE
export EXTRA_SKILLS="$HOME/.agents/skills/web-operator"

echo ""
echo "=== 正在研究验证经验... ==="
echo ""

run_agent_node "$MODE" "ExperienceInjector" "$OUTPUT_FILE" "$INJECTOR_AGENT" "@$PROMPT_FILE"

# ── 步骤 3: 提取 JSON ────────────────────────────────────────────────────────

RESULT_FILE="$TMP_DIR/result.json"

python3 - "$OUTPUT_FILE" <<'PY' > "$RESULT_FILE"
import json
import re
import sys
from pathlib import Path

input_file = sys.argv[1]
content = Path(input_file).read_text(encoding='utf-8')
data = None

# 尝试 1: 从 ```json ``` 代码块提取
match = re.search(r'```json\s*(.*?)\s*```', content, re.DOTALL)
if match:
    try:
        data = json.loads(match.group(1))
    except json.JSONDecodeError:
        data = None

# 尝试 2: 直接解析整个内容
if data is None:
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        data = None

# 尝试 3: 正则匹配最外层 JSON 对象
if data is None:
    match = re.search(r'\{.*\}', content, re.DOTALL)
    if match:
        try:
            data = json.loads(match.group(0))
        except json.JSONDecodeError:
            data = None

print(json.dumps(data, ensure_ascii=False, indent=2) if data else "null")
PY

# 检查 JSON 提取结果
if [[ "$(cat "$RESULT_FILE")" == "null" ]]; then
    echo "" >&2
    echo "✗ 无法从 Agent 输出中提取 JSON" >&2
    echo "原始输出:" >&2
    head -50 "$OUTPUT_FILE" >&2
    exit 1
fi

# ── 步骤 4: 检查 verdict ─────────────────────────────────────────────────────

VERDICT=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('verdict',''))" "$RESULT_FILE")

if [[ "$VERDICT" == "reject" ]]; then
    echo ""
    echo "=============================================="
    echo "✗ 经验注入被拒绝"
    echo "=============================================="
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print()
print('拒绝理由:', d.get('reason', '未知'))
print()
print('研究摘要:', d.get('research_summary', '无'))
" "$RESULT_FILE"
    exit 1
fi

if [[ "$VERDICT" != "accept" ]]; then
    echo "✗ 未知 verdict: '$VERDICT'" >&2
    exit 1
fi

# ── 步骤 5: 校验 role 并写入记忆 ─────────────────────────────────────────────

RESULT_ROLE=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('role',''))" "$RESULT_FILE")

case "$RESULT_ROLE" in
    bull|bear|judge|trader) ;;
    *)
        echo "✗ Agent 返回了无效角色: '$RESULT_ROLE'" >&2
        echo "  请使用 --role 参数手动指定角色（bull/bear/judge/trader）" >&2
        exit 1
        ;;
esac

TODAY=$(date +%Y-%m-%d)

python3 - "$RESULT_FILE" "$TODAY" "$EXPERIENCE_TEXT" <<'PY' | "$PROJECT_ROOT/bin/memory.py" --data-dir "$MEMORY_DIR" store-batch
import json
import sys

result = json.load(open(sys.argv[1]))

record = {
    "role": result["role"],
    "date": sys.argv[2],
    "situation": result.get("situation", sys.argv[3]),
    "recommendation": result.get("recommendation", ""),
    "market_situation": result.get("market_situation", ""),
    "improvements": result.get("improvements", []),
    "summary": result.get("summary", ""),
    "query": result.get("query", ""),
    "research_summary": result.get("research_summary", ""),
    "source": "manual"
}

print(json.dumps([record], ensure_ascii=False))
PY

echo ""
echo "=============================================="
echo "✓ 经验已注入记忆库"
echo "  角色: $RESULT_ROLE"
echo "  日期: $TODAY"
echo "  记忆文件: $MEMORY_DIR/${RESULT_ROLE}.jsonl"
echo "=============================================="
