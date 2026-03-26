#!/usr/bin/env bash
# run-analysis.sh — Pipeline Conductor 编排脚本
# 用法: run-analysis.sh [--mode text|stream|json] [-s 1,2,3] [-m MODEL] [YYYY-MM-DD]

set -euo pipefail

# ======== 配置和初始化 ========

# 获取项目根目录（脚本所在目录的父目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/bin/lib/pi-runner.sh"

# Python 脚本使用 uv run --script（shebang 驱动，无需 venv）

# markdown-to-anything 转换脚本
CONVERT_PY="$HOME/Projects/oh-my-superpowers/skills/markdown-to-anything/scripts/convert.py"

# 运行时目录（统一放到 ~/.local/share/PiTradingAgents）
PITA_HOME="${PITA_HOME:-$HOME/.local/share/PiTradingAgents}"
PITA_DATA_DIR="${PITA_DATA_DIR:-$PITA_HOME/data}"
PITA_CONFIG_DIR="${PITA_CONFIG_DIR:-$PITA_HOME/config}"
REPORTS_ROOT="$PITA_DATA_DIR/reports"
MEMORY_DIR="$PITA_DATA_DIR/memory"
mkdir -p "$REPORTS_ROOT" "$MEMORY_DIR" "$PITA_CONFIG_DIR"

# API 地址
API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

# 初始化记忆变量（用于阶段 2/3，防止跳过阶段 2 时报错）
BULL_MEMORY=""
BEAR_MEMORY=""
JUDGE_MEMORY=""

# 解析命令行参数
MODE="text"
STAGES=""        # 空 = 全部阶段；否则逗号分隔，如 "2,3"
MODEL_OVERRIDE="" # 空 = 使用 Agent frontmatter 中的模型
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift
            shift
            ;;
        -s|--stages)
            STAGES="${2:-}"
            shift 2
            ;;
        -m|--model)
            MODEL_OVERRIDE="${2:-}"
            shift 2
            ;;
        -*)
            echo "未知选项: $1" >&2
            echo "用法: $0 [--mode text|stream|json|interactive] [-s|--stages 1,2,3] [-m|--model MODEL] [YYYY-MM-DD]" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# 判断某阶段是否需要执行（STAGES 为空表示全部执行）
should_run_stage() {
    [[ -z "$STAGES" ]] && return 0
    echo ",$STAGES," | grep -q ",${1}," && return 0
    return 1
}

# 确定行情日期（TRADE_DATE）
# 规则：所有从 ashare-platform（8000端口）取数的日期必须统一
#   - 用户显式传入日期 → 直接使用
#   - 否则：从 API 取最近交易日列表，若最后一个交易日是今天且当前时间 < 15:30，
#           则用倒数第二个交易日（数据采集在 15:30 之后，未收盘日无完整数据）
resolve_trade_date() {
    local recent latest prev today now_hhmm
    recent=$(curl -sf --connect-timeout 5 --max-time 10 \
        "$API_URL/trade-dates/recent?days=30" 2>/dev/null) || {
        echo "[错误] 无法连接 ashare-platform API: $API_URL" >&2
        echo "[错误] 请确认服务已启动，或手动指定日期: $0 YYYY-MM-DD" >&2
        exit 1
    }
    latest=$(echo "$recent" | jq -r '.trade_dates[-1]')
    prev=$(echo "$recent"   | jq -r '.trade_dates[-2]')
    today=$(date +%Y-%m-%d)
    now_hhmm=$(date +%H%M)

    if [[ "$latest" == "$today" && "$now_hhmm" -lt "1530" ]]; then
        # 今天是交易日但 15:30 前数据未采集完成，使用前一交易日
        echo "$prev"
    else
        echo "$latest"
    fi
}

if [[ $# -gt 0 ]]; then
    TRADE_DATE="$1"
else
    TRADE_DATE=$(resolve_trade_date)
fi

if [[ "$MODE" == "interactive" ]]; then
    echo "[错误] run 命令暂不支持 interactive 模式：多 Agent workflow 无法映射到单一 Pi TUI 会话" >&2
    exit 1
fi

# 输出目录
REPORT_DIR="$REPORTS_ROOT/$TRADE_DATE"
mkdir -p "$REPORT_DIR"

# 创建临时目录（P0-1 修复）
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

run_agent() {
    local label="$1"
    local output_file="$2"
    local agent_md="$3"
    shift 3
    export MODEL_OVERRIDE
    run_agent_node "$MODE" "$label" "$output_file" "$agent_md" "$@"
}

parallel_json_log_path() {
    local output_file="$1"
    echo "$TMP_DIR/$(basename "$output_file" .md).jsonl"
}

start_parallel_stream_renderer() {
    local pid="$1"
    local label="$2"
    local output_file="$3"
    local json_log
    json_log="$(parallel_json_log_path "$output_file")"
    python3 "$PROJECT_ROOT/bin/lib/pi-stream.py" render-follow \
        --label "$label" \
        --file "$json_log" \
        --pid "$pid" &
    RENDERER_PID=$!
}

run_parallel_agent() {
    local label="$1"
    local output_file="$2"
    local agent_md="$3"
    shift 3

    if [[ "$MODE" == "stream" || "$MODE" == "json" ]]; then
        local json_log
        json_log="$(parallel_json_log_path "$output_file")"
        export MODEL_OVERRIDE
        PI_JSON_LOG="$json_log" run_agent_node "capture" "$label" "$output_file" "$agent_md" "$@"
        if [[ "${PI_DEFER_RENDER:-0}" == "1" ]]; then
            :
        elif [[ "$MODE" == "stream" ]]; then
            render_completed_stream_block "$label" "$agent_md" "$json_log"
        else
            cat "$json_log"
        fi
    else
        export MODEL_OVERRIDE
        run_agent_node "$MODE" "$label" "$output_file" "$agent_md" "$@"
    fi
}

finish_parallel_agent() {
    local pid="$1"
    local label="$2"
    local output_file="$3"
    local agent_md="$4"
    local status_file="$5"
    local renderer_pid="${6:-}"

    wait "$pid" || true
    if [[ "$MODE" == "stream" && -n "$renderer_pid" ]]; then
        wait "$renderer_pid" || true
    elif [[ "$MODE" == "json" ]]; then
        local json_log
        json_log="$(parallel_json_log_path "$output_file")"
        if [[ -f "$json_log" ]]; then
            cat "$json_log"
        fi
    fi

    if [[ -f "$status_file" && "$(cat "$status_file")" == "ok" ]]; then
        echo "[分析师] ${label}完成 ✓"
    else
        echo "[警告] ${label}执行失败，继续执行其他任务"
    fi
}

echo "=============================================="
echo "PiTradingAgents — A股题材交易分析 Pipeline"
echo "交易日期: $TRADE_DATE"
echo "输出目录: $REPORT_DIR"
echo "模式: $MODE"
[[ -n "$STAGES" ]]        && echo "执行阶段: $STAGES"
[[ -n "$MODEL_OVERRIDE" ]] && echo "模型覆盖: $MODEL_OVERRIDE"
echo "=============================================="

# web-operator CLI 可用性检查
OMP_WEB_OPERATOR_BIN="omp-web-operator"

# ======== 阶段 1: 分析团队（并行） ========

if should_run_stage 1; then

echo ""
echo "=== 阶段 1: 分析团队（并行执行） ==="
echo "启动 4 个分析师..."

# 1. 情绪分析师
(
    PI_DEFER_RENDER=1 run_parallel_agent "情绪分析师" "$REPORT_DIR/01-emotion-report.md" "$PROJECT_ROOT/agents/analysts/emotion-analyst.md" "/skill:ashare-data ${TRADE_DATE}" \
        && echo ok > "$TMP_DIR/emotion.status" || echo fail > "$TMP_DIR/emotion.status"
) &
PID_EMOTION=$!
RENDER_PID_EMOTION=""
if [[ "$MODE" == "stream" ]]; then
    start_parallel_stream_renderer "$PID_EMOTION" "情绪分析师" "$REPORT_DIR/01-emotion-report.md"
    RENDER_PID_EMOTION="$RENDERER_PID"
fi
echo "[分析师] 情绪分析师启动..."

# 2. 题材分析师
(
    PI_DEFER_RENDER=1 run_parallel_agent "题材分析师" "$REPORT_DIR/02-theme-report.md" "$PROJECT_ROOT/agents/analysts/theme-analyst.md" "/skill:ashare-data ${TRADE_DATE}" \
        && echo ok > "$TMP_DIR/theme.status" || echo fail > "$TMP_DIR/theme.status"
) &
PID_THEME=$!
RENDER_PID_THEME=""
if [[ "$MODE" == "stream" ]]; then
    start_parallel_stream_renderer "$PID_THEME" "题材分析师" "$REPORT_DIR/02-theme-report.md"
    RENDER_PID_THEME="$RENDERER_PID"
fi
echo "[分析师] 题材分析师启动..."

# 3. 趋势分析师
(
    PI_DEFER_RENDER=1 run_parallel_agent "趋势分析师" "$REPORT_DIR/03-trend-report.md" "$PROJECT_ROOT/agents/analysts/trend-analyst.md" "/skill:ashare-data ${TRADE_DATE}" \
        && echo ok > "$TMP_DIR/trend.status" || echo fail > "$TMP_DIR/trend.status"
) &
PID_TREND=$!
RENDER_PID_TREND=""
if [[ "$MODE" == "stream" ]]; then
    start_parallel_stream_renderer "$PID_TREND" "趋势分析师" "$REPORT_DIR/03-trend-report.md"
    RENDER_PID_TREND="$RENDERER_PID"
fi
echo "[分析师] 趋势分析师启动..."

# 4. 催化剂分析师（检查 web-operator 可用性）
(
    if command -v "$OMP_WEB_OPERATOR_BIN" >/dev/null 2>&1; then
        PI_DEFER_RENDER=1 run_parallel_agent "催化剂分析师" "$REPORT_DIR/04-catalyst-report.md" "$PROJECT_ROOT/agents/analysts/catalyst-analyst.md" "/skill:ashare-data ${TRADE_DATE}" \
            && echo ok > "$TMP_DIR/catalyst.status" || echo fail > "$TMP_DIR/catalyst.status"
    else
        cat > "$REPORT_DIR/04-catalyst-report.md" << 'EOF'
## 催化剂深度研究报告

### 降级模式

**状态**: `omp-web-operator` 不可用，深度研究跳过

**原因**: 
- `omp-web-operator` 命令不可用，或
- 本地浏览器调试环境未就绪

**影响**:
- 无法进行 Google/淘股吧/雪球的深度搜索和研究
- 辩论团队将仅基于量化数据进行分析

**建议**:
- 如需深度研究，请确保 `omp-web-operator` 可执行且浏览器调试环境可用
- 或继续使用现有量化分析报告进行后续分析

### 可用数据源

在降级模式下，其他分析师的报告仍提供以下量化数据：
- 情绪分析师：市场情绪周期阶段、关键指标快照
- 题材分析师：主流题材排名、题材周期阶段
- 趋势分析师：核心标的池、个股评级
EOF
        echo ok > "$TMP_DIR/catalyst.status"
    fi
) &
PID_CATALYST=$!
RENDER_PID_CATALYST=""
if [[ "$MODE" == "stream" ]]; then
    start_parallel_stream_renderer "$PID_CATALYST" "催化剂分析师" "$REPORT_DIR/04-catalyst-report.md"
    RENDER_PID_CATALYST="$RENDERER_PID"
fi
echo "[分析师] 催化剂分析师启动..."
if ! command -v "$OMP_WEB_OPERATOR_BIN" >/dev/null 2>&1; then
    echo "  omp-web-operator 不可用，催化剂分析师将输出降级报告"
fi

# 等待所有分析师完成
echo "等待所有分析师完成..."
finish_parallel_agent "$PID_EMOTION" "情绪分析师" "$REPORT_DIR/01-emotion-report.md" "$PROJECT_ROOT/agents/analysts/emotion-analyst.md" "$TMP_DIR/emotion.status" "$RENDER_PID_EMOTION"
finish_parallel_agent "$PID_THEME" "题材分析师" "$REPORT_DIR/02-theme-report.md" "$PROJECT_ROOT/agents/analysts/theme-analyst.md" "$TMP_DIR/theme.status" "$RENDER_PID_THEME"
finish_parallel_agent "$PID_TREND" "趋势分析师" "$REPORT_DIR/03-trend-report.md" "$PROJECT_ROOT/agents/analysts/trend-analyst.md" "$TMP_DIR/trend.status" "$RENDER_PID_TREND"
finish_parallel_agent "$PID_CATALYST" "催化剂分析师" "$REPORT_DIR/04-catalyst-report.md" "$PROJECT_ROOT/agents/analysts/catalyst-analyst.md" "$TMP_DIR/catalyst.status" "$RENDER_PID_CATALYST"
echo "阶段 1 完成"

fi  # end should_run_stage 1

# 拼接 4 份报告到临时文件（阶段 2/3 共用；无论是否跳过阶段 1 都从已有文件读取）
REPORTS_CTX="$TMP_DIR/reports-context.txt"
> "$REPORTS_CTX"
for report in "$REPORT_DIR"/0{1,2,3,4}-*-report.md; do
    if [[ -f "$report" ]]; then
        printf '\n\n=== %s ===\n' "$(basename "$report")" >> "$REPORTS_CTX"
        cat "$report" >> "$REPORTS_CTX"
    fi
done

# 构建市场情景摘要用于记忆检索（关键词密度高，利于 BM25 匹配）
SITUATION_SUMMARY=""
if [[ -f "$REPORT_DIR/01-emotion-report.md" ]]; then
    # 提取情绪阶段、涨停/跌停数等关键指标作为检索 query
    SITUATION_SUMMARY=$(python3 -c "
import sys, re
text = open(sys.argv[1], encoding='utf-8').read()
# 提取关键行（含数字指标的行）
lines = []
for line in text.split('\n'):
    if re.search(r'(涨停|跌停|封板|炸板|晋级|情绪|冰点|启动|高潮|退潮|主升|分歧)', line):
        lines.append(line.strip())
# 截取前 500 字符
print(' '.join(lines)[:500])
" "$REPORT_DIR/01-emotion-report.md" 2>/dev/null || echo "")
fi

# ======== 阶段 2: 市场环境辩论（顺序） ========

if should_run_stage 2; then

echo ""
echo "=== 阶段 2: 市场环境辩论（顺序执行） ==="

# 1. 看多辩手（P0-1 修复：使用临时 prompt 文件）
echo "[辩论] 看多辩手构建论据..."
BULL_MEMORY=$(bin/memory.py --data-dir "$MEMORY_DIR" query --role bull --n 3 \
    --situation "$SITUATION_SUMMARY" 2>/dev/null || echo "")

BULL_PROMPT="$TMP_DIR/bull-prompt.txt"
{
    echo "市场环境辩论模式"
    echo ""
    if [[ -n "$BULL_MEMORY" ]]; then
        echo "=== 历史经验教训（从类似市场环境中检索） ==="
        echo "$BULL_MEMORY"
        echo "请优先吸收其中的改进规则、复盘结论和检索语句，避免重复同类错误。"
        echo ""
    fi
    echo "分析报告汇总:"
    cat "$REPORTS_CTX"
} > "$BULL_PROMPT"

run_agent "看多辩手" "$REPORT_DIR/05a-bull-argument.md" "$PROJECT_ROOT/agents/debaters/bull-debater.md" "@$BULL_PROMPT" || echo "[警告] 看多辩手执行失败"

# 2. 看空辩手（P0-1 修复：使用临时 prompt 文件）
echo "[辩论] 看空辩手构建论据..."
BEAR_MEMORY=$(bin/memory.py --data-dir "$MEMORY_DIR" query --role bear --n 3 \
    --situation "$SITUATION_SUMMARY" 2>/dev/null || echo "")

BEAR_PROMPT="$TMP_DIR/bear-prompt.txt"
{
    echo "市场环境辩论模式"
    echo ""
    if [[ -n "$BEAR_MEMORY" ]]; then
        echo "=== 历史经验教训（从类似市场环境中检索） ==="
        echo "$BEAR_MEMORY"
        echo "请优先吸收其中的改进规则、复盘结论和检索语句，避免重复同类错误。"
        echo ""
    fi
    echo "分析报告汇总:"
    cat "$REPORTS_CTX"
    echo ""
    echo "看多辩手论述:"
    cat "$REPORT_DIR/05a-bull-argument.md" 2>/dev/null || echo "无"
} > "$BEAR_PROMPT"

run_agent "看空辩手" "$REPORT_DIR/05b-bear-argument.md" "$PROJECT_ROOT/agents/debaters/bear-debater.md" "@$BEAR_PROMPT" || echo "[警告] 看空辩手执行失败"

# 3. 市场裁判（P0-1 修复：使用临时 prompt 文件）
echo "[裁判] 市场环境裁判综合判定..."
JUDGE_MEMORY=$(bin/memory.py --data-dir "$MEMORY_DIR" query --role judge --n 3 \
    --situation "$SITUATION_SUMMARY" 2>/dev/null || echo "")

JUDGE_PROMPT="$TMP_DIR/judge-prompt.txt"
{
    if [[ -n "$JUDGE_MEMORY" ]]; then
        echo "=== 历史经验教训（从类似市场环境中检索） ==="
        echo "$JUDGE_MEMORY"
        echo "请优先吸收其中的改进规则、复盘结论和检索语句，避免重复同类错误。"
        echo ""
    fi
    echo "分析报告汇总:"
    cat "$REPORTS_CTX"
    echo ""
    echo "看多辩手论述:"
    cat "$REPORT_DIR/05a-bull-argument.md" 2>/dev/null || echo "无"
    echo ""
    echo "看空辩手论述:"
    cat "$REPORT_DIR/05b-bear-argument.md" 2>/dev/null || echo "无"
} > "$JUDGE_PROMPT"

run_agent "市场裁判" "$REPORT_DIR/05-market-debate.md" "$PROJECT_ROOT/agents/judges/market-judge.md" "@$JUDGE_PROMPT" || {
    echo "[警告] 市场裁判执行失败"
}

echo "阶段 2 完成"

fi  # end should_run_stage 2

# 从市场辩论结果中提取 TOP_THEMES（阶段 3 共用；无论是否跳过阶段 2 都从已有文件读取）
TOP_THEMES=""
if [[ -f "$REPORT_DIR/05-market-debate.md" ]]; then
    # 放宽匹配：支持前导空格、中英文冒号
    TOP_THEMES_LINE=$(grep -a -iE '^\s*TOP_THEMES\s*[:：]' "$REPORT_DIR/05-market-debate.md" 2>/dev/null | head -1 || true)
    if [[ -n "$TOP_THEMES_LINE" ]]; then
        # 支持中英文冒号和中英文逗号；用 sed 按字符分割（tr 按字节处理会破坏 UTF-8 多字节序列）
        TOP_THEMES=$(echo "$TOP_THEMES_LINE" | sed -E 's/^[^:：]*[:：]//' | sed 's/[，,]/\n/g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -a -v '^$')
    fi
fi

# 如果未提取到，尝试从文件内容识别题材列表
if [[ -z "$TOP_THEMES" ]]; then
    echo "  未在 05-market-debate.md 中找到 TOP_THEMES 标记，尝试解析主流题材..."
    # 这里可以添加更多的解析逻辑
    # 暂时使用空列表，让后续处理生成提示
fi

# ======== 阶段 3: 题材辩论（顺序） ========

if should_run_stage 3; then

echo ""
echo "=== 阶段 3: 题材辩论（顺序执行） ==="

# 题材辩论计数器
THEME_IDX=0

# 对每个题材进行辩论
# 注意：用 fd 3 传入题材列表，避免循环内部 pi 命令读取 stdin 时把剩余题材"吃掉"
while IFS= read -r theme <&3; do
    [[ -z "$theme" ]] && continue
    
    THEME_IDX=$((THEME_IDX + 1))
    echo "[辩论] 题材 $THEME_IDX: $theme"
    
    # 题材看多辩论（P0-1 修复：使用临时 prompt 文件）
    echo "  ├─ 看多辩手..."
    THEME_BULL_PROMPT="$TMP_DIR/theme-${THEME_IDX}-bull-prompt.txt"
    {
        echo "题材辩论模式"
        echo "题材名称: $theme"
        echo ""
        if [[ -n "$BULL_MEMORY" ]]; then
            echo "=== 历史经验教训（从类似市场环境中检索） ==="
            echo "$BULL_MEMORY"
            echo "请优先吸收其中的改进规则、复盘结论和检索语句，避免重复同类错误。"
            echo ""
        fi
        echo "分析报告汇总:"
        cat "$REPORTS_CTX"
        echo ""
        echo "市场环境判定:"
        cat "$REPORT_DIR/05-market-debate.md" 2>/dev/null || echo "无"
    } > "$THEME_BULL_PROMPT"
    
    run_agent "题材${THEME_IDX}看多" "$REPORT_DIR/06a-bull-${THEME_IDX}.md" "$PROJECT_ROOT/agents/debaters/bull-debater.md" "@$THEME_BULL_PROMPT" || echo "  [警告] 题材 $theme 看多辩手执行失败"
    
    # 题材看空辩论（P0-1 修复：使用临时 prompt 文件）
    echo "  ├─ 看空辩手..."
    THEME_BEAR_PROMPT="$TMP_DIR/theme-${THEME_IDX}-bear-prompt.txt"
    {
        echo "题材辩论模式"
        echo "题材名称: $theme"
        echo ""
        if [[ -n "$BEAR_MEMORY" ]]; then
            echo "=== 历史经验教训（从类似市场环境中检索） ==="
            echo "$BEAR_MEMORY"
            echo "请优先吸收其中的改进规则、复盘结论和检索语句，避免重复同类错误。"
            echo ""
        fi
        echo "分析报告汇总:"
        cat "$REPORTS_CTX"
        echo ""
        echo "市场环境判定:"
        cat "$REPORT_DIR/05-market-debate.md" 2>/dev/null || echo "无"
        echo ""
        echo "看多论述:"
        cat "$REPORT_DIR/06a-bull-${THEME_IDX}.md" 2>/dev/null || echo "无"
    } > "$THEME_BEAR_PROMPT"
    
    run_agent "题材${THEME_IDX}看空" "$REPORT_DIR/06b-bear-${THEME_IDX}.md" "$PROJECT_ROOT/agents/debaters/bear-debater.md" "@$THEME_BEAR_PROMPT" || echo "  [警告] 题材 $theme 看空辩手执行失败"
done 3<<< "$TOP_THEMES"

# 如果没有任何题材被处理，生成提示
if [[ $THEME_IDX -eq 0 ]]; then
    echo "  未识别到具体题材，生成提示文件..."
    cat > "$REPORT_DIR/06-theme-debate.md" << 'EOF'
## 题材机会辩论总结

### 状态
未从市场辩论结果中提取到具体题材列表。

### 可能原因
1. 市场裁判输出格式未包含 TOP_THEMES 标记行
2. 当前市场环境下无明确主流题材
3. 解析逻辑需要调整

### 建议
请查看 05-market-debate.md 中的市场环境判定，手动识别需要深度分析的题材。
EOF
else
    # 题材裁判汇总（P0-1 修复：使用临时 prompt 文件）
    echo "[裁判] 题材机会裁判综合判定..."
    
    THEME_JUDGE_PROMPT="$TMP_DIR/theme-judge-prompt.txt"
    {
        if [[ -n "$JUDGE_MEMORY" ]]; then
            echo "=== 历史经验教训（从类似市场环境中检索） ==="
            echo "$JUDGE_MEMORY"
            echo "请优先吸收其中的改进规则、复盘结论和检索语句，避免重复同类错误。"
            echo ""
        fi
        echo "市场环境辩论结果:"
        cat "$REPORT_DIR/05-market-debate.md" 2>/dev/null || echo "无"
        echo ""
        echo "各题材辩论汇总:"
        for i in $(seq 1 $THEME_IDX); do
            if [[ -f "$REPORT_DIR/06a-bull-${i}.md" ]]; then
                echo ""
                echo "=== 题材 $i 看多论述 ==="
                cat "$REPORT_DIR/06a-bull-${i}.md"
            fi
            if [[ -f "$REPORT_DIR/06b-bear-${i}.md" ]]; then
                echo ""
                echo "=== 题材 $i 看空论述 ==="
                cat "$REPORT_DIR/06b-bear-${i}.md"
            fi
        done
        echo ""
        echo "分析报告汇总:"
        cat "$REPORTS_CTX"
    } > "$THEME_JUDGE_PROMPT"
    
    run_agent "题材裁判" "$REPORT_DIR/06-theme-debate.md" "$PROJECT_ROOT/agents/judges/theme-judge.md" "@$THEME_JUDGE_PROMPT" || {
        echo "[警告] 题材裁判执行失败"
    }
fi

echo "阶段 3 完成"

fi  # end should_run_stage 3

# ======== 阶段 4: 最终决策 ========

if should_run_stage 4; then

echo ""
echo "=== 阶段 4: 最终决策 ==="
echo "[决策] 投资经理生成最终报告..."

# 构建所有报告上下文（P0-1 修复：使用临时文件）
ALL_REPORTS_CTX="$TMP_DIR/all-reports-context.txt"
> "$ALL_REPORTS_CTX"
for report in "$REPORT_DIR"/*.md; do
    if [[ -f "$report" && "$(basename "$report")" != "07-final-report.md" ]]; then
        printf '\n\n=== %s ===\n' "$(basename "$report")" >> "$ALL_REPORTS_CTX"
        cat "$report" >> "$ALL_REPORTS_CTX"
    fi
done

# 读取历史记忆（使用 memory.py 语义检索）
TRADER_MEMORY=$(bin/memory.py --data-dir "$MEMORY_DIR" query --role trader --n 5 \
    --situation "$SITUATION_SUMMARY" 2>/dev/null || echo "")

LESSONS_FILE="$TMP_DIR/lessons.md"
{
    if [[ -n "$TRADER_MEMORY" ]]; then
        echo "=== 历史经验教训（BM25 语义检索） ==="
        echo "$TRADER_MEMORY"
    else
        echo "无历史记忆"
    fi
} > "$LESSONS_FILE"

# 投资经理 prompt 文件（P0-1 修复）
FINAL_PROMPT="$TMP_DIR/final-prompt.txt"
{
    echo "所有分析报告:"
    cat "$ALL_REPORTS_CTX"
    echo ""
    echo "历史记忆:"
    cat "$LESSONS_FILE"
} > "$FINAL_PROMPT"

run_agent "投资经理" "$REPORT_DIR/07-final-report.md" "$PROJECT_ROOT/agents/decision/investment-manager.md" "@$FINAL_PROMPT" || {
    echo "[警告] 投资经理执行失败"
}

# 重命名最终报告并生成 PDF
if [[ -f "$REPORT_DIR/07-final-report.md" ]]; then
    TIMESTAMP=$(date +%H%M%S)
    FINAL_NAME="A股题材交易决策-${TRADE_DATE}-${TIMESTAMP}"
    cp "$REPORT_DIR/07-final-report.md" "$REPORT_DIR/${FINAL_NAME}.md"
    echo "最终报告已复制: ${FINAL_NAME}.md"

    if [[ -f "$CONVERT_PY" ]]; then
        echo "正在生成 PDF（桌面版）..."
        python3 "$CONVERT_PY" "$REPORT_DIR/${FINAL_NAME}.md" \
            --mode report --format pdf --same-dir --stdout-manifest 2>/dev/null \
            | python3 -c "import json,sys; m=json.load(sys.stdin); print('桌面版 PDF:', m['files'][0] if m.get('ok') and m.get('files') else '失败')" \
            || echo "[警告] 桌面版 PDF 生成失败"

        echo "正在生成 PDF（手机版）..."
        python3 "$CONVERT_PY" "$REPORT_DIR/${FINAL_NAME}.md" \
            --mode report --format pdf --layout mobile \
            --output "$REPORT_DIR/${FINAL_NAME}_mobile" --stdout-manifest 2>/dev/null \
            | python3 -c "import json,sys; m=json.load(sys.stdin); print('手机版 PDF:', m['files'][0] if m.get('ok') and m.get('files') else '失败')" \
            || echo "[警告] 手机版 PDF 生成失败"
    else
        echo "[警告] markdown-to-anything 不可用，跳过 PDF 生成"
    fi
fi

echo "阶段 4 完成"

fi  # end should_run_stage 4

# ======== 阶段 5: 状态保存（用于次日复盘） ========
echo ""
echo "=== 阶段 5: 保存 Pipeline 状态 ==="
if bin/save-state.py "$REPORT_DIR" "$TRADE_DATE" > "$REPORT_DIR/state.json" 2>/dev/null; then
    echo "状态已保存: $REPORT_DIR/state.json"
else
    echo "[警告] 状态保存失败，复盘功能将不可用"
fi

# ======== 完成 ========

echo ""
echo "=============================================="
echo "Pipeline 执行完成！"
echo "=============================================="
echo "报告目录: $REPORT_DIR"
echo ""
echo "生成的所有报告："
ls -la "$REPORT_DIR"/*.md "$REPORT_DIR"/*.pdf 2>/dev/null || ls -la "$REPORT_DIR"/*.md 2>/dev/null
