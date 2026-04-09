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
    # 默认模式：多源合并（ashare 候选池 + THS 排行 + 问财涨幅榜）
    echo "正在采集多源强势股数据..."

    MERGE_JSON=$(uv run --script "$PROJECT_ROOT/scripts/merge-stock-candidates.py" "$TRADE_DATE" --top 30 2>"$TMP_DIR/merge.log" || echo '{}')

    TOTAL=$(echo "$MERGE_JSON" | jq '.summary.total_unique_stocks // 0' 2>/dev/null || echo 0)
    SELECTED=$(echo "$MERGE_JSON" | jq '.selected_stocks | length' 2>/dev/null || echo 0)
    CONCEPT_TOP=$(echo "$MERGE_JSON" | jq -r '[.concept_distribution[:3][] | .concept] | join(", ")' 2>/dev/null || echo "")

    # 打印采集日志
    if [[ -f "$TMP_DIR/merge.log" ]]; then
        cat "$TMP_DIR/merge.log"
    fi
    echo "  精选候选: ${SELECTED} 只（从 ${TOTAL} 只中筛出）"
    echo "  热门概念: ${CONCEPT_TOP}"

    # 精简概念分布：只保留概念名/数量/占比/平均涨幅，去掉完整 stocks 列表（节省 token）
    CONCEPT_DIST=$(echo "$MERGE_JSON" | jq '[.concept_distribution[] | {concept, stock_count, concentration_pct, avg_gain_60d, avg_gain_120d, top3: [.stocks[:3][] | .name]}]' 2>/dev/null || echo "[]")
    SELECTED_STOCKS=$(echo "$MERGE_JSON" | jq '.selected_stocks' 2>/dev/null || echo "[]")

    cat > "$PROMPT_FILE" << EOF
模式：默认研究
交易日期：$TRADE_DATE

## 数据来源

候选池由程序从 5 个数据源自动合并、去重、交叉评分后精选：
- ashare-platform：连阳（≥5天）+ 历史新高（已过滤一字板、交叉主流题材）
- 同花顺排行：连续上涨、持续放量、量价齐升
- 问财涨幅榜：60日/120日/240日 Top 50

## 概念/板块强度分布（程序从 ${TOTAL} 只上榜股中聚合）

以下概念在多个强势股中集中出现，代表板块级走强信号：

$CONCEPT_DIST

## 精选候选池（共 ${SELECTED} 只，按多源命中数+涨幅排序）

字段说明：
- hit_count: 命中数据源个数（越高越强）
- sources: 命中的数据源列表
- gain_60d/gain_120d/gain_240d: 问财涨幅榜数据（%）
- consecutive_up_days: THS 连续上涨天数
- volume_up_days: THS 持续放量天数
- volume_price_up_days: THS 量价齐升天数
- primary_theme: ashare-platform 关联主流题材
- top_concepts: 该股关联的热门概念（已过滤噪音，仅保留在上榜股中有聚集效应的）

$SELECTED_STOCKS

## 研究要求

1. 按照 5 轮分层淘汰研究框架进行系统研究
2. 优先关注 hit_count ≥ 3 的多源共振股
3. 结合概念分布判断板块趋势：个股走强是板块共振还是个股独立行情
4. 对多周期涨幅榜同时上榜的股票（60d+120d+240d），重点评估当前位置（主升 vs 高潮）
5. 报告保存路径：$OUTPUT_FILE
EOF
fi

# ======== 执行研究 ========

echo "=============================================="
echo "PiTradingAgents — 个股深度研究"
echo "交易日期: $TRADE_DATE"
if [[ -n "$STOCKS" ]]; then
    echo "研究模式: 指定股票（$STOCKS）"
else
    echo "研究模式: 默认（多源合并：ashare+THS+问财，概念聚合）"
fi
echo "输出文件: $OUTPUT_FILE"
echo "输出模式: $MODE"
echo "=============================================="
echo ""

export MODEL_OVERRIDE
EXTRA_SKILLS="$HOME/.agents/skills/web-operator" PI_JSON_LOG="$TMP_DIR/research.jsonl" run_agent_node "$MODE" "个股研究" "$OUTPUT_FILE" "$AGENT_MD" "@$PROMPT_FILE"

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
