#!/usr/bin/env bash
# fetch-consecutive-red.sh - 获取连阳股票
# 用法: ./fetch-consecutive-red.sh <trade_date> [min_days]
# 示例: ./fetch-consecutive-red.sh 2026-03-24 7
# API: GET /consecutive-red/daily/{trade_date}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <trade_date> [min_days]" >&2
    echo "示例: $0 2026-03-24 7" >&2
    exit 1
fi

TRADE_DATE="$1"
MIN_DAYS="${2:-7}"

curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/consecutive-red/daily/${TRADE_DATE}" | jq "[.stocks[] | select(.consecutive_days >= ${MIN_DAYS})]"
