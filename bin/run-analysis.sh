#!/usr/bin/env bash
# run-analysis.sh — Pipeline Conductor 编排脚本
# A股题材交易分析 Agent 团队编排脚本

set -euo pipefail

# ======== 配置和初始化 ========

# 获取项目根目录（脚本所在目录的父目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# API 地址
API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

# 解析命令行参数
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -*)
            echo "未知选项: $1" >&2
            echo "用法: $0 [-v|--verbose] [YYYY-MM-DD]" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

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

# 输出目录
REPORT_DIR="$PROJECT_ROOT/data/reports/$TRADE_DATE"
mkdir -p "$REPORT_DIR"

# 创建临时目录（P0-1 修复）
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 从 pi JSON 事件流中提取最终一轮 LLM 文本
# 多轮 agent 对话中取最后一条 message 的完整文本
extract_final_text() {
    python3 -c "
import json, sys
text = ''
for line in open(sys.argv[1]):
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
sys.stdout.write(text)
" "$1"
}

# Agent 执行封装：从 agent .md 解析 frontmatter，正确传递 --system-prompt/--model/--tools
# 用法: run_agent <label> <output_file> <agent_md> [--skill <dir>]... <message|@file>
#
# 参照 chrome-cdp-skill/agents/bin/ 的调用模式：
#   awk 从 agent .md 提取 model、tools、system prompt，通过 pi 参数传入，
#   避免 LLM 误将 agent .md 路径当做消息处理。
#
# 非 verbose 模式: pi --print，只输出最终文本到报告文件
# verbose 模式:    pi --mode json | pi-watch，实时显示 tool calls 和流式文本
run_agent() {
    local label="$1"
    local output_file="$2"
    local agent_md="$3"
    shift 3
    # 剩余 $@ = [--skill <dir>...] <message 或 @file>

    # 从 agent .md frontmatter 解析 model 和 tools
    local model tools system_prompt
    model="$(awk -F': ' '/^model:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$agent_md")"
    tools="$(awk -F': ' '/^tools:/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$agent_md")"
    # 提取 frontmatter 之后的正文作为 system prompt（跳过两个 --- 分隔符）
    system_prompt="$(awk 'BEGIN{n=0} /^---/{n++; next} n>=2{print}' "$agent_md")"

    # 将 frontmatter 中的简短模型名映射到完整 provider/id
    case "$model" in
        kimi-k2-thinking) model="kimi-coding/kimi-k2-thinking" ;;
    esac

    if $VERBOSE; then
        local json_log="$TMP_DIR/$(basename "$output_file" .md).jsonl"
        echo "  [$label] >>>" >&2
        pi --no-session --mode json \
           --model "$model" \
           --tools "$tools" \
           --system-prompt "$system_prompt" \
           "$@" \
            | tee "$json_log" \
            | pi-watch 2> >(sed "s/^/[$label] /" >&2) \
            | sed "s/^/[$label] /"
        echo "" >&2
        echo "  [$label] <<<" >&2
        extract_final_text "$json_log" > "$output_file"
    else
        pi --no-session --print \
           --model "$model" \
           --tools "$tools" \
           --system-prompt "$system_prompt" \
           "$@" \
            > "$output_file" 2>&1
    fi
}

echo "=============================================="
echo "PiTradingAgents — A股题材交易分析 Pipeline"
echo "交易日期: $TRADE_DATE"
echo "输出目录: $REPORT_DIR"
$VERBOSE && echo "模式: verbose（实时输出 Agent 推理过程）"
echo "=============================================="

# Skill 目录
SKILL_DIR="$PROJECT_ROOT/skills/ashare-data"

# Chrome CDP Skill 路径
CHROME_CDP_SKILL="$HOME/.agents/skills/chrome-cdp"

# ======== 阶段 1: 分析团队（并行） ========

echo ""
echo "=== 阶段 1: 分析团队（并行执行） ==="
echo "启动 4 个分析师..."

# 1. 情绪分析师
(
    echo "[分析师] 情绪分析师启动..."
    run_agent "情绪分析师" "$REPORT_DIR/01-emotion-report.md" "$PROJECT_ROOT/agents/analysts/emotion-analyst.md" --skill "$SKILL_DIR" "$TRADE_DATE" && \
    echo "[分析师] 情绪分析师完成 ✓" || \
    echo "[警告] 情绪分析师执行失败，继续执行其他任务"
) &
PID_EMOTION=$!

# 2. 题材分析师
(
    echo "[分析师] 题材分析师启动..."
    run_agent "题材分析师" "$REPORT_DIR/02-theme-report.md" "$PROJECT_ROOT/agents/analysts/theme-analyst.md" --skill "$SKILL_DIR" "$TRADE_DATE" && \
    echo "[分析师] 题材分析师完成 ✓" || \
    echo "[警告] 题材分析师执行失败，继续执行其他任务"
) &
PID_THEME=$!

# 3. 趋势分析师
(
    echo "[分析师] 趋势分析师启动..."
    run_agent "趋势分析师" "$REPORT_DIR/03-trend-report.md" "$PROJECT_ROOT/agents/analysts/trend-analyst.md" --skill "$SKILL_DIR" "$TRADE_DATE" && \
    echo "[分析师] 趋势分析师完成 ✓" || \
    echo "[警告] 趋势分析师执行失败，继续执行其他任务"
) &
PID_TREND=$!

# 4. 催化剂分析师（检查 Chrome 可用性）
(
    echo "[分析师] 催化剂分析师启动..."
    if [[ -d "$CHROME_CDP_SKILL" && -f "$CHROME_CDP_SKILL/scripts/sites/google/search.sh" ]]; then
        echo "  Chrome CDP Skill 可用，启动深度研究..."
        run_agent "催化剂分析师" "$REPORT_DIR/04-catalyst-report.md" "$PROJECT_ROOT/agents/analysts/catalyst-analyst.md" --skill "$SKILL_DIR" --skill "$CHROME_CDP_SKILL" "$TRADE_DATE" && \
        echo "[分析师] 催化剂分析师完成 ✓" || \
        echo "[警告] 催化剂分析师执行失败，继续执行其他任务"
    else
        echo "  Chrome CDP Skill 不可用，生成降级提示..."
        cat > "$REPORT_DIR/04-catalyst-report.md" << 'EOF'
## 催化剂深度研究报告

### 降级模式

**状态**: Chrome CDP Skill 不可用，深度研究跳过

**原因**: 
- Chrome 浏览器未运行，或
- chrome-cdp skill 未安装 ($HOME/.agents/skills/chrome-cdp)

**影响**:
- 无法进行 Google/淘股吧/雪球的深度搜索和研究
- 辩论团队将仅基于量化数据进行分析

**建议**:
- 如需深度研究，请启动 Chrome 并确保 chrome-cdp skill 已正确安装
- 或继续使用现有量化分析报告进行后续分析

### 可用数据源

在降级模式下，其他分析师的报告仍提供以下量化数据：
- 情绪分析师：市场情绪周期阶段、关键指标快照
- 题材分析师：主流题材排名、题材周期阶段
- 趋势分析师：核心标的池、个股评级
EOF
        echo "[分析师] 催化剂分析师降级模式完成（Chrome 不可用）"
    fi
) &
PID_CATALYST=$!

# 等待所有分析师完成
echo "等待所有分析师完成..."
wait $PID_EMOTION || true
wait $PID_THEME || true
wait $PID_TREND || true
wait $PID_CATALYST || true
echo "阶段 1 完成"

# ======== 阶段 2: 市场环境辩论（顺序） ========

echo ""
echo "=== 阶段 2: 市场环境辩论（顺序执行） ==="

# 拼接 4 份报告到临时文件（P0-1 修复）
REPORTS_CTX="$TMP_DIR/reports-context.txt"
> "$REPORTS_CTX"
for report in "$REPORT_DIR"/0{1,2,3,4}-*-report.md; do
    if [[ -f "$report" ]]; then
        printf '\n\n=== %s ===\n' "$(basename "$report")" >> "$REPORTS_CTX"
        cat "$report" >> "$REPORTS_CTX"
    fi
done

# 1. 看多辩手（P0-1 修复：使用临时 prompt 文件）
echo "[辩论] 看多辩手构建论据..."
BULL_PROMPT="$TMP_DIR/bull-prompt.txt"
{
    echo "市场环境辩论模式"
    echo ""
    echo "分析报告汇总:"
    cat "$REPORTS_CTX"
} > "$BULL_PROMPT"

run_agent "看多辩手" "$REPORT_DIR/05a-bull-argument.md" "$PROJECT_ROOT/agents/debaters/bull-debater.md" "@$BULL_PROMPT" || {
    echo "[警告] 看多辩手执行失败"
}

# 2. 看空辩手（P0-1 修复：使用临时 prompt 文件）
echo "[辩论] 看空辩手构建论据..."
BEAR_PROMPT="$TMP_DIR/bear-prompt.txt"
{
    echo "市场环境辩论模式"
    echo ""
    echo "分析报告汇总:"
    cat "$REPORTS_CTX"
    echo ""
    echo "看多辩手论述:"
    cat "$REPORT_DIR/05a-bull-argument.md" 2>/dev/null || echo "无"
} > "$BEAR_PROMPT"

run_agent "看空辩手" "$REPORT_DIR/05b-bear-argument.md" "$PROJECT_ROOT/agents/debaters/bear-debater.md" "@$BEAR_PROMPT" || {
    echo "[警告] 看空辩手执行失败"
}

# 3. 市场裁判（P0-1 修复：使用临时 prompt 文件）
echo "[裁判] 市场环境裁判综合判定..."
JUDGE_PROMPT="$TMP_DIR/judge-prompt.txt"
{
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

# ======== 阶段 3: 题材辩论（顺序） ========

echo ""
echo "=== 阶段 3: 题材辩论（顺序执行） ==="

# 从市场辩论结果中提取 TOP_THEMES（P0-3 修复：更健壮的匹配）
TOP_THEMES=""
if [[ -f "$REPORT_DIR/05-market-debate.md" ]]; then
    # 放宽匹配：支持前导空格、中英文冒号
    TOP_THEMES_LINE=$(grep -iE '^\s*TOP_THEMES\s*[:：]' "$REPORT_DIR/05-market-debate.md" 2>/dev/null | head -1 || true)
    if [[ -n "$TOP_THEMES_LINE" ]]; then
        # 支持中英文冒号和中英文逗号
        TOP_THEMES=$(echo "$TOP_THEMES_LINE" | sed -E 's/^[^:：]*[:：]//' | tr '，,' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
    fi
fi

# 如果未提取到，尝试从文件内容识别题材列表
if [[ -z "$TOP_THEMES" ]]; then
    echo "  未在 05-market-debate.md 中找到 TOP_THEMES 标记，尝试解析主流题材..."
    # 这里可以添加更多的解析逻辑
    # 暂时使用空列表，让后续处理生成提示
fi

# 题材辩论计数器
THEME_IDX=0

# 对每个题材进行辩论
while IFS= read -r theme; do
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
        echo "分析报告汇总:"
        cat "$REPORTS_CTX"
        echo ""
        echo "市场环境判定:"
        cat "$REPORT_DIR/05-market-debate.md" 2>/dev/null || echo "无"
    } > "$THEME_BULL_PROMPT"
    
    run_agent "题材${THEME_IDX}看多" "$REPORT_DIR/06a-bull-${THEME_IDX}.md" "$PROJECT_ROOT/agents/debaters/bull-debater.md" "@$THEME_BULL_PROMPT" || {
        echo "  [警告] 题材 $theme 看多辩手执行失败"
    }
    
    # 题材看空辩论（P0-1 修复：使用临时 prompt 文件）
    echo "  ├─ 看空辩手..."
    THEME_BEAR_PROMPT="$TMP_DIR/theme-${THEME_IDX}-bear-prompt.txt"
    {
        echo "题材辩论模式"
        echo "题材名称: $theme"
        echo ""
        echo "分析报告汇总:"
        cat "$REPORTS_CTX"
        echo ""
        echo "市场环境判定:"
        cat "$REPORT_DIR/05-market-debate.md" 2>/dev/null || echo "无"
        echo ""
        echo "看多论述:"
        cat "$REPORT_DIR/06a-bull-${THEME_IDX}.md" 2>/dev/null || echo "无"
    } > "$THEME_BEAR_PROMPT"
    
    run_agent "题材${THEME_IDX}看空" "$REPORT_DIR/06b-bear-${THEME_IDX}.md" "$PROJECT_ROOT/agents/debaters/bear-debater.md" "@$THEME_BEAR_PROMPT" || {
        echo "  [警告] 题材 $theme 看空辩手执行失败"
    }
done <<< "$TOP_THEMES"

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

# ======== 阶段 4: 最终决策 ========

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

# 读取历史记忆
LESSONS_FILE="$TMP_DIR/lessons.md"
{
    echo "历史记忆（最近20条）:"
    if [[ -f "$PROJECT_ROOT/data/memory/lessons.jsonl" ]]; then
        tail -20 "$PROJECT_ROOT/data/memory/lessons.jsonl" 2>/dev/null || echo "无历史记忆"
    else
        echo "无历史记忆文件"
    fi
} > "$LESSONS_FILE"

# 投资经理 prompt 文件（P0-1 修复）
FINAL_PROMPT="$TMP_DIR/final-prompt.txt"
{
    echo "所有分析报告:"
    cat "$ALL_REPORTS_CTX"
    echo ""
    echo "历史记忆（最近20条）:"
    cat "$LESSONS_FILE"
} > "$FINAL_PROMPT"

run_agent "投资经理" "$REPORT_DIR/07-final-report.md" "$PROJECT_ROOT/agents/decision/investment-manager.md" "@$FINAL_PROMPT" || {
    echo "[警告] 投资经理执行失败"
}

echo "阶段 4 完成"

# ======== 完成 ========

echo ""
echo "=============================================="
echo "Pipeline 执行完成！"
echo "=============================================="
echo "最终报告路径: $REPORT_DIR/07-final-report.md"
echo ""
echo "生成的所有报告："
ls -la "$REPORT_DIR"/*.md
echo ""
echo "查看最终报告:"
echo "  cat $REPORT_DIR/07-final-report.md"
