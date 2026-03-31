#!/usr/bin/env bash
# filter-yiziboard.sh — 过滤一字板股票
# 用法: echo "$STOCKS_JSON" | ./filter-yiziboard.sh <trade_date>
# 输入: stdin 为股票 JSON 数组（含 code、name 字段）
# 输出: stdout 为过滤后的 JSON 数组（一字板已剔除）
# 副作用: 被剔除的股票打印到 stderr

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [[ $# -lt 1 ]]; then
    echo "用法: echo \$STOCKS_JSON | $0 <trade_date>" >&2
    exit 1
fi

TRADE_DATE="$1"
STOCKS_JSON=$(cat)

# 快速检查：候选池为空时直接返回
if [[ "$STOCKS_JSON" == "[]" ]] || [[ -z "$STOCKS_JSON" ]]; then
    echo "[]"
    exit 0
fi

RESULT="[]"

# 只对最后一天 change_pct >= 9.9% 的股票才调用 kline API 验证
# 其余股票不可能是涨停板，直接保留
while IFS= read -r stock; do
    code=$(echo "$stock" | jq -r '.code')
    name=$(echo "$stock" | jq -r '.name')

    # 取 bars 最后一天的涨跌幅（consecutive-red 格式）
    # new-high 格式没有 bars，默认保留
    last_change=$(echo "$stock" | jq -r 'if .bars then (.bars | last | .change_pct) else 0 end' 2>/dev/null || echo "0")

    # 非涨停日，直接保留
    if (( $(echo "$last_change < 9.9" | bc -l 2>/dev/null || echo 1) )); then
        RESULT=$(echo "$RESULT" | jq ". + [$stock]")
        continue
    fi

    # 涨停日：调用 kline API 验证是否一字板（open == high == low == close）
    kline=$(curl -sf --connect-timeout 3 --max-time 10 "${API_URL}/kline/daily/${code}" 2>/dev/null || echo "[]")
    today=$(echo "$kline" | jq --arg d "$TRADE_DATE" '.[] | select(.date == $d)' 2>/dev/null || echo "")

    if [[ -z "$today" ]]; then
        # 没有当天 kline 数据，保留
        RESULT=$(echo "$RESULT" | jq ". + [$stock]")
        continue
    fi

    open=$(echo "$today"  | jq '.open')
    high=$(echo "$today"  | jq '.high')
    low=$(echo "$today"   | jq '.low')
    close=$(echo "$today" | jq '.close')

    if [[ "$open" == "$high" && "$high" == "$low" && "$low" == "$close" ]]; then
        echo "  [一字板剔除] ${name}(${code}) open=high=low=close=${close}" >&2
    else
        RESULT=$(echo "$RESULT" | jq ". + [$stock]")
    fi

done < <(echo "$STOCKS_JSON" | jq -c '.[]')

echo "$RESULT"
