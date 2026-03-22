#!/usr/bin/env bash
# run-analysis.sh — Pipeline Conductor 编排脚本
# A股题材交易分析 Agent 团队编排脚本

set -euo pipefail

# ======== 配置和初始化 ========

# 获取项目根目录（脚本所在目录的父目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 交易日期，默认今天
TRADE_DATE="${1:-$(date +%Y-%m-%d)}"

# 输出目录
REPORT_DIR="$PROJECT_ROOT/data/reports/$TRADE_DATE"
mkdir -p "$REPORT_DIR"

echo "=============================================="
echo "PiTradingAgents — A股题材交易分析 Pipeline"
echo "交易日期: $TRADE_DATE"
echo "输出目录: $REPORT_DIR"
echo "=============================================="

# Pi CLI 基础调用参数
PI_CMD="pi -p --model kimi-coding/kimi-k2-thinking --no-session"

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
    $PI_CMD --skill "$SKILL_DIR" "$PROJECT_ROOT/agents/analysts/emotion-analyst.md" "$TRADE_DATE" > "$REPORT_DIR/01-emotion-report.md" 2>&1 && \
    echo "[分析师] 情绪分析师完成 ✓" || \
    echo "[警告] 情绪分析师执行失败，继续执行其他任务"
) &
PID_EMOTION=$!

# 2. 题材分析师
(
    echo "[分析师] 题材分析师启动..."
    $PI_CMD --skill "$SKILL_DIR" "$PROJECT_ROOT/agents/analysts/theme-analyst.md" "$TRADE_DATE" > "$REPORT_DIR/02-theme-report.md" 2>&1 && \
    echo "[分析师] 题材分析师完成 ✓" || \
    echo "[警告] 题材分析师执行失败，继续执行其他任务"
) &
PID_THEME=$!

# 3. 趋势分析师
(
    echo "[分析师] 趋势分析师启动..."
    $PI_CMD --skill "$SKILL_DIR" "$PROJECT_ROOT/agents/analysts/trend-analyst.md" "$TRADE_DATE" > "$REPORT_DIR/03-trend-report.md" 2>&1 && \
    echo "[分析师] 趋势分析师完成 ✓" || \
    echo "[警告] 趋势分析师执行失败，继续执行其他任务"
) &
PID_TREND=$!

# 4. 催化剂分析师（检查 Chrome 可用性）
(
    echo "[分析师] 催化剂分析师启动..."
    if [[ -d "$CHROME_CDP_SKILL" && -f "$CHROME_CDP_SKILL/scripts/sites/google/search.sh" ]]; then
        echo "  Chrome CDP Skill 可用，启动深度研究..."
        $PI_CMD --skill "$SKILL_DIR" --skill "$CHROME_CDP_SKILL" "$PROJECT_ROOT/agents/analysts/catalyst-analyst.md" "$TRADE_DATE" > "$REPORT_DIR/04-catalyst-report.md" 2>&1 && \
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

# 拼接 4 份报告作为上下文
REPORTS_CONTENT=""
for report in "$REPORT_DIR"/0{1,2,3,4}-*-report.md; do
    if [[ -f "$report" ]]; then
        REPORTS_CONTENT+="\n\n=== $(basename "$report") ===\n"
        REPORTS_CONTENT+=$(cat "$report")
    fi
done

# 1. 看多辩手
echo "[辩论] 看多辩手构建论据..."
$PI_CMD "$PROJECT_ROOT/agents/debaters/bull-debater.md" "市场环境辩论模式\n\n分析报告汇总:$REPORTS_CONTENT" > "$REPORT_DIR/05a-bull-argument.md" 2>&1 || {
    echo "[警告] 看多辩手执行失败"
}

BULL_CONTENT=""
if [[ -f "$REPORT_DIR/05a-bull-argument.md" ]]; then
    BULL_CONTENT=$(cat "$REPORT_DIR/05a-bull-argument.md")
fi

# 2. 看空辩手
echo "[辩论] 看空辩手构建论据..."
$PI_CMD "$PROJECT_ROOT/agents/debaters/bear-debater.md" "市场环境辩论模式\n\n分析报告汇总:$REPORTS_CONTENT\n\n看多辩手论述:\n$BULL_CONTENT" > "$REPORT_DIR/05b-bear-argument.md" 2>&1 || {
    echo "[警告] 看空辩手执行失败"
}

BEAR_CONTENT=""
if [[ -f "$REPORT_DIR/05b-bear-argument.md" ]]; then
    BEAR_CONTENT=$(cat "$REPORT_DIR/05b-bear-argument.md")
fi

# 3. 市场裁判
echo "[裁判] 市场环境裁判综合判定..."
$PI_CMD "$PROJECT_ROOT/agents/judges/market-judge.md" "\n分析报告汇总:$REPORTS_CONTENT\n\n看多辩手论述:\n$BULL_CONTENT\n\n看空辩手论述:\n$BEAR_CONTENT" > "$REPORT_DIR/05-market-debate.md" 2>&1 || {
    echo "[警告] 市场裁判执行失败"
}

echo "阶段 2 完成"

# ======== 阶段 3: 题材辩论（顺序） ========

echo ""
echo "=== 阶段 3: 题材辩论（顺序执行） ==="

# 从市场辩论结果中提取 TOP_THEMES
TOP_THEMES=""
if [[ -f "$REPORT_DIR/05-market-debate.md" ]]; then
    # 提取 TOP_THEMES: 行，格式为 TOP_THEMES: 题材1,题材2,题材3
    TOP_THEMES_LINE=$(grep -E "^TOP_THEMES:" "$REPORT_DIR/05-market-debate.md" 2>/dev/null || true)
    if [[ -n "$TOP_THEMES_LINE" ]]; then
        TOP_THEMES=$(echo "$TOP_THEMES_LINE" | sed 's/^TOP_THEMES://' | tr ',' '\n' | tr -d ' ')
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
    
    # 题材看多辩论
    echo "  ├─ 看多辩手..."
    $PI_CMD "$PROJECT_ROOT/agents/debaters/bull-debater.md" "题材辩论模式\n题材名称:$theme\n\n分析报告汇总:$REPORTS_CONTENT\n\n市场环境判定:\n$(cat "$REPORT_DIR/05-market-debate.md" 2>/dev/null || echo '无')" > "$REPORT_DIR/06a-bull-${THEME_IDX}.md" 2>&1 || {
        echo "  [警告] 题材 $theme 看多辩手执行失败"
    }
    
    THEME_BULL=$(cat "$REPORT_DIR/06a-bull-${THEME_IDX}.md" 2>/dev/null || echo "")
    
    # 题材看空辩论
    echo "  ├─ 看空辩手..."
    $PI_CMD "$PROJECT_ROOT/agents/debaters/bear-debater.md" "题材辩论模式\n题材名称:$theme\n\n分析报告汇总:$REPORTS_CONTENT\n\n市场环境判定:\n$(cat "$REPORT_DIR/05-market-debate.md" 2>/dev/null || echo '无')\n\n看多论述:\n$THEME_BULL" > "$REPORT_DIR/06b-bear-${THEME_IDX}.md" 2>&1 || {
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
    # 题材裁判汇总
    echo "[裁判] 题材机会裁判综合判定..."
    
    THEME_DEBATES=""
    for i in $(seq 1 $THEME_IDX); do
        if [[ -f "$REPORT_DIR/06a-bull-${i}.md" ]]; then
            THEME_DEBATES+="\n\n=== 题材 $i 看多论述 ===\n"
            THEME_DEBATES+=$(cat "$REPORT_DIR/06a-bull-${i}.md")
        fi
        if [[ -f "$REPORT_DIR/06b-bear-${i}.md" ]]; then
            THEME_DEBATES+="\n\n=== 题材 $i 看空论述 ===\n"
            THEME_DEBATES+=$(cat "$REPORT_DIR/06b-bear-${i}.md")
        fi
    done
    
    $PI_CMD "$PROJECT_ROOT/agents/judges/theme-judge.md" "\n市场环境辩论结果:\n$(cat "$REPORT_DIR/05-market-debate.md" 2>/dev/null || echo '无')\n\n各题材辩论汇总:$THEME_DEBATES\n\n分析报告汇总:$REPORTS_CONTENT" > "$REPORT_DIR/06-theme-debate.md" 2>&1 || {
        echo "[警告] 题材裁判执行失败"
    }
fi

echo "阶段 3 完成"

# ======== 阶段 4: 最终决策 ========

echo ""
echo "=== 阶段 4: 最终决策 ==="
echo "[决策] 投资经理生成最终报告..."

# 收集所有报告内容
ALL_REPORTS=""
for report in "$REPORT_DIR"/*.md; do
    if [[ -f "$report" && "$report" != "$REPORT_DIR/07-final-report.md" ]]; then
        ALL_REPORTS+="\n\n=== $(basename "$report") ===\n"
        ALL_REPORTS+=$(cat "$report")
    fi
done

# 读取历史记忆
LESSONS=""
if [[ -f "$PROJECT_ROOT/data/memory/lessons.jsonl" ]]; then
    LESSONS=$(tail -20 "$PROJECT_ROOT/data/memory/lessons.jsonl" 2>/dev/null || echo "无历史记忆")
else
    LESSONS="无历史记忆文件"
fi

# 投资经理生成最终报告
$PI_CMD "$PROJECT_ROOT/agents/decision/investment-manager.md" "\n所有分析报告:$ALL_REPORTS\n\n历史记忆（最近20条）:\n$LESSONS" > "$REPORT_DIR/07-final-report.md" 2>&1 || {
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
ls -la "$REPORT_DIR"/
echo ""
echo "查看最终报告:"
echo "  cat $REPORT_DIR/07-final-report.md"
