#!/usr/bin/env bash
# fetch-consecutive-red.sh - 获取连阳窗口股票
# 用法: ./fetch-consecutive-red.sh <trade_date> [days] [min_red]
# 示例: ./fetch-consecutive-red.sh 2026-03-24 5 5
# API: GET /red-window/daily/{trade_date}?days=N&min_red=M

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <trade_date> [days] [min_red]" >&2
    echo "示例: $0 2026-03-24 5 5" >&2
    exit 1
fi

TRADE_DATE="$1"
DAYS="${2:-}"
MIN_RED="${3:-}"

# 构造查询字符串
QUERY=""
if [[ -n "$DAYS" ]]; then
    QUERY="?days=${DAYS}"
fi
if [[ -n "$MIN_RED" ]]; then
    if [[ -n "$QUERY" ]]; then
        QUERY="${QUERY}&min_red=${MIN_RED}"
    else
        QUERY="?min_red=${MIN_RED}"
    fi
fi

curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/red-window/daily/${TRADE_DATE}${QUERY}" | jq .
