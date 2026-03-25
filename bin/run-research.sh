#!/usr/bin/env bash
# run-research.sh — 个股深度研究编排脚本
# 用法: run-research.sh [-v] [-m MODEL] [--stocks CODE1,CODE2]

set -euo pipefail

# ======== 配置和初始化 ========

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PITA_HOME="${PITA_HOME:-$HOME/.local/share/PiTradingAgents}"

# markdown-to-anything 转换脚本
CONVERT_PY="$HOME/Projects/oh-my-superpowers/skills/markdown-to-anything/scripts/convert.py"
PITA_DATA_DIR="${PITA_DATA_DIR:-$PITA_HOME/data}"
REPORTS_ROOT="$PITA_DATA_DIR/reports"
API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

mkdir -p "$REPORTS_ROOT"

# 解析命令行参数
VERBOSE=false
MODEL_OVERRIDE=""
STOCKS=""

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
        --stocks)
            STOCKS="${2:-}"
            shift 2
            ;;
        -*)
            echo "未知选项: $1" >&2
            echo "用法: $0 [-v] [-m MODEL] [--stocks CODE1,CODE2]" >&2
            exit 1
            ;;
        *)
            echo "未知参数: $1（run-research 不接受日期参数，自动取最近交易日）" >&2
            exit 1
            ;;
    esac
done

# ======== 确定交易日期 ========

# 规则：若最后一个交易日是今天且当前时间 < 15:30，使用前一交易日
resolve_trade_date() {
    local recent latest prev today now_hhmm
    recent=$(curl -sf --connect-timeout 5 --max-time 10 \
        "$API_URL/trade-dates/recent?days=30" 2>/dev/null) || {
        echo "[错误] 无法连接 ashare-platform API: $API_URL" >&2
        echo "[错误] 请确认服务已启动" >&2
        exit 1
    }
    latest=$(echo "$recent" | jq -r '.trade_dates[-1]')
    prev=$(echo "$recent"   | jq -r '.trade_dates[-2]')
    today=$(date +%Y-%m-%d)
    now_hhmm=$(date +%H%M)

    if [[ "$latest" == "$today" && "$now_hhmm" -lt "1530" ]]; then
        echo "$prev"
    else
        echo "$latest"
    fi
}

TRADE_DATE=$(resolve_trade_date)
REPORT_DIR="$REPORTS_ROOT/$TRADE_DATE"
mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +%H%M%S)
if [[ -n "$STOCKS" ]]; then
    REPORT_NAME="个股深度研究-${TRADE_DATE}-${TIMESTAMP}"
else
    REPORT_NAME="强势股研究-${TRADE_DATE}-${TIMESTAMP}"
fi
OUTPUT_FILE="$REPORT_DIR/${REPORT_NAME}.md"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ======== 选择 Agent ========
# 默认模式（7连阳+新高候选池）使用筛选模式 Agent
# 指定股票模式使用深度研究 Agent（跳过筛选，全面深挖）

if [[ -n "$STOCKS" ]]; then
    AGENT_MD="$PROJECT_ROOT/agents/researchers/stock-deep-researcher.md"
else
    AGENT_MD="$PROJECT_ROOT/agents/researchers/stock-researcher.md"
fi

# ======== 读取 Agent 配置 ========

if [[ ! -f "$AGENT_MD" ]]; then
    echo "[错误] Agent 文件不存在: $AGENT_MD" >&2
    exit 1
fi

MODEL="$(awk -F': ' '/^model:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$AGENT_MD")"
TOOLS="$(awk -F': ' '/^tools:/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$AGENT_MD")"
SYSTEM_PROMPT="$(awk 'BEGIN{n=0} /^---/{n++; next} n>=2{print}' "$AGENT_MD")"

# 命令行 --model 覆盖 frontmatter
[[ -n "$MODEL_OVERRIDE" ]] && MODEL="$MODEL_OVERRIDE"

# 简短模型名 → 完整 provider/id
case "$MODEL" in
    kimi-k2-thinking) MODEL="kimi-coding/kimi-k2-thinking" ;;
    kimi-k2p5)        MODEL="kimi-coding/kimi-k2p5" ;;
    qwen3.5-35b)      MODEL="litellm-local/qwen3.5-35b" ;;
    qwen3.5-27b)      MODEL="litellm-local/qwen3.5-27b" ;;
esac

# ======== 构建研究提示词 ========

PROMPT_FILE="$TMP_DIR/prompt.txt"

if [[ -n "$STOCKS" ]]; then
    # 指定股票模式：跳过前3轮淘汰，直接进入 Round 4 深度研究
    cat > "$PROMPT_FILE" << EOF
模式：指定股票研究
交易日期：$TRADE_DATE

研究目标（跳过前3轮筛选，直接进行 Round 4~5 深度研究）：
$STOCKS

请对以上股票进行深度研究，挖掘走强的核心驱动力，输出完整分析报告。
报告保存路径：$OUTPUT_FILE
EOF
else
    # 默认模式：从 ashare-platform 获取候选池
    echo "正在获取候选股票数据..."

    CONSECUTIVE_RED=$(bash "$PROJECT_ROOT/scripts/fetch-consecutive-red.sh" "$TRADE_DATE" 7 2>/dev/null || echo "[]")
    NEW_HIGH=$(bash "$PROJECT_ROOT/scripts/fetch-new-high.sh" "$TRADE_DATE" 2>/dev/null || echo "[]")

    CR_COUNT=$(echo "$CONSECUTIVE_RED" | jq 'length' 2>/dev/null || echo 0)
    NH_COUNT=$(echo "$NEW_HIGH" | jq 'length' 2>/dev/null || echo 0)
    echo "  7连阳以上: ${CR_COUNT} 只"
    echo "  历史新高:  ${NH_COUNT} 只"

    cat > "$PROMPT_FILE" << EOF
模式：默认研究
交易日期：$TRADE_DATE

## 候选池一：7连阳以上股票（consecutive_days >= 7）

字段说明：code=股票代码, name=名称, consecutive_days=连阳天数, gain_pct=区间涨幅%, bars=逐日涨跌幅

$CONSECUTIVE_RED

## 候选池二：历史新高股票

字段说明：code=股票代码, name=名称, price=当前价, change_pct=当日涨幅%, prev_high=前高价, prev_high_date=前高日期

$NEW_HIGH

请按照 5 轮分层淘汰研究框架，对以上候选股票进行系统研究，输出完整分析报告。
报告保存路径：$OUTPUT_FILE
EOF
fi

# ======== 执行研究 ========

echo "=============================================="
echo "PiTradingAgents — 个股深度研究"
echo "交易日期: $TRADE_DATE"
if [[ -n "$STOCKS" ]]; then
    echo "研究模式: 指定股票（$STOCKS）"
else
    echo "研究模式: 默认（7连阳+历史新高）"
fi
echo "输出文件: $OUTPUT_FILE"
$VERBOSE && echo "输出模式: verbose（实时显示推理过程）"
echo "=============================================="
echo ""

PI_ARGS=(
    --no-session
    --mode text
    --model "$MODEL"
    --system-prompt "$SYSTEM_PROMPT"
    --skill "$PROJECT_ROOT/skills/ashare-data"
    "@$PROMPT_FILE"
)

if $VERBOSE; then
    pi "${PI_ARGS[@]}" 2>/dev/null | tee "$OUTPUT_FILE"
else
    pi "${PI_ARGS[@]}" > "$OUTPUT_FILE" 2>/dev/null
fi

if [[ ! -s "$OUTPUT_FILE" ]]; then
    echo "[错误] Agent 未生成报告文件: $OUTPUT_FILE" >&2
    exit 1
fi

echo ""
echo "=============================================="
echo "研究完成 ✓"
echo "Markdown: $OUTPUT_FILE"

# 生成 PDF（桌面版 + 手机版）
if [[ -f "$OUTPUT_FILE" && -f "$CONVERT_PY" ]]; then
    echo "正在生成 PDF（桌面版）..."
    python3 "$CONVERT_PY" "$OUTPUT_FILE" \
        --mode report --format pdf --same-dir --stdout-manifest 2>/dev/null \
        | python3 -c "import json,sys; m=json.load(sys.stdin); print('桌面版 PDF:', m['files'][0] if m.get('ok') and m.get('files') else '生成失败')" \
        || echo "[警告] 桌面版 PDF 生成失败"

    echo "正在生成 PDF（手机版）..."
    OUTPUT_BASE="${OUTPUT_FILE%.md}"
    python3 "$CONVERT_PY" "$OUTPUT_FILE" \
        --mode report --format pdf --layout mobile \
        --output "${OUTPUT_BASE}_mobile" --stdout-manifest 2>/dev/null \
        | python3 -c "import json,sys; m=json.load(sys.stdin); print('手机版 PDF:', m['files'][0] if m.get('ok') and m.get('files') else '生成失败')" \
        || echo "[警告] 手机版 PDF 生成失败"
elif [[ ! -f "$CONVERT_PY" ]]; then
    echo "[警告] markdown-to-anything 不可用，跳过 PDF 生成"
fi

echo "=============================================="
