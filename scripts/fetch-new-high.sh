#!/usr/bin/env bash
# fetch-new-high.sh - 获取历史新高股票
# 用法: ./fetch-new-high.sh <trade_date>
# 示例: ./fetch-new-high.sh 2026-03-24
# API: GET /new-high/daily/{trade_date}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <trade_date>" >&2
    echo "示例: $0 2026-03-24" >&2
    exit 1
fi

TRADE_DATE="$1"

curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/new-high/daily/${TRADE_DATE}" | jq ".stocks"
