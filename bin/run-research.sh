#!/usr/bin/env bash
# run-research.sh — 个股深度研究编排脚本
# 用法: run-research.sh [--mode text|stream|json|interactive] [-m MODEL] [--stocks CODE1,CODE2]

set -euo pipefail

# ======== 配置和初始化 ========

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/bin/lib/pi-runner.sh"

PITA_HOME="${PITA_HOME:-$HOME/.local/share/PiTradingAgents}"

# markdown-to-anything 转换脚本
CONVERT_PY="$HOME/Projects/oh-my-superpowers/skills/markdown-to-anything/scripts/convert.py"
PITA_DATA_DIR="${PITA_DATA_DIR:-$PITA_HOME/data}"
REPORTS_ROOT="$PITA_DATA_DIR/reports"
API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

mkdir -p "$REPORTS_ROOT"

# 解析命令行参数
MODE="text"
MODEL_OVERRIDE=""
STOCKS=""

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
        --stocks)
            STOCKS="${2:-}"
            shift 2
            ;;
        -*)
            echo "未知选项: $1" >&2
            echo "用法: $0 [--mode text|stream|json|interactive] [-m MODEL] [--stocks CODE1,CODE2]" >&2
            exit 1
            ;;
        *)
            echo "未知参数: $1（run-research 不接受日期参数，自动取最近交易日）" >&2
            exit 1
            ;;
    esac
done

# ======== 确定交易日期 ========
# resolve_trade_date 来自 bin/lib/pi-runner.sh

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

if [[ ! -f "$AGENT_MD" ]]; then
    echo "[错误] Agent 文件不存在: $AGENT_MD" >&2
    exit 1
fi

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
    # 默认模式：通过 C5 候选池接口一次获取（已含题材交叉、一字板过滤）
    echo "正在获取候选股票数据..."

    CANDIDATES_JSON=$(bash "$PROJECT_ROOT/scripts/fetch-stock-candidates.sh" "$TRADE_DATE" 5 10 2>/dev/null || echo '{"total":0,"candidates":[]}')

    TOTAL=$(echo "$CANDIDATES_JSON" | jq '.total // 0' 2>/dev/null || echo 0)
    CR_COUNT=$(echo "$CANDIDATES_JSON" | jq '.consecutive_red_count // 0' 2>/dev/null || echo 0)
    NH_COUNT=$(echo "$CANDIDATES_JSON" | jq '.new_high_count // 0' 2>/dev/null || echo 0)
    RESONANT_COUNT=$(echo "$CANDIDATES_JSON" | jq '[.candidates[] | select(.theme_resonance==true)] | length' 2>/dev/null || echo 0)
    echo "  候选总数: ${TOTAL} 只（连阳${CR_COUNT} + 新高${NH_COUNT}）"
    echo "  题材共振: ${RESONANT_COUNT} 只（已过滤一字板）"

    CANDIDATES=$(echo "$CANDIDATES_JSON" | jq '.candidates' 2>/dev/null || echo "[]")

    cat > "$PROMPT_FILE" << EOF
模式：默认研究
交易日期：$TRADE_DATE

候选池已由 ashare-platform 完成以下处理：
- 合并连阳（≥5天）和历史新高两个来源
- 过滤上一交易日为一字板的股票
- 交叉主流题材 Top 10，标注 theme_resonance

字段说明：
- source: consecutive_red=连阳来源, new_high=历史新高, both=同时命中
- consecutive_up_days/period_gain_pct/bars: 连阳结构（连阳股）
- prev_high/prev_high_date/change_pct_today: 历史新高信息（新高股）
- primary_theme/primary_theme_rank/primary_theme_cycle_hint: 关联主流题材
- theme_resonance: true=主题材在 Top 10 中（题材共振）
- prev_day_yizi: true=上一交易日为一字板（已默认过滤）

## 候选池（共 ${TOTAL} 只）

$CANDIDATES

请按照 5 轮分层淘汰研究框架，对以上候选股票进行系统研究，输出完整分析报告。
优先关注 theme_resonance=true 的股票（共振票优先进入深度研究）。
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
    echo "研究模式: 默认（5连阳+历史新高，题材共振优先）"
fi
echo "输出文件: $OUTPUT_FILE"
echo "输出模式: $MODE"
echo "=============================================="
echo ""

export MODEL_OVERRIDE
PI_JSON_LOG="$TMP_DIR/research.jsonl" run_agent_node "$MODE" "个股研究" "$OUTPUT_FILE" "$AGENT_MD" "@$PROMPT_FILE"

if [[ "$MODE" != "interactive" && ! -s "$OUTPUT_FILE" ]]; then
    echo "[错误] Agent 未生成报告文件: $OUTPUT_FILE" >&2
    exit 1
fi

echo ""
echo "=============================================="
echo "研究完成 ✓"
if [[ "$MODE" == "interactive" ]]; then
    echo "interactive 模式未自动生成 Markdown 报告"
else
    echo "Markdown: $OUTPUT_FILE"
fi

# 生成 PDF（桌面版 + 手机版）
if [[ "$MODE" != "interactive" && -f "$OUTPUT_FILE" && -f "$CONVERT_PY" ]]; then
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
