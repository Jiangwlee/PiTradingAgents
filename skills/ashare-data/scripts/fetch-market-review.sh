#!/bin/bash
# fetch-market-review.sh - 获取市场复盘数据
# 用法: ./fetch-market-review.sh <trade_date>
# 示例: ./fetch-market-review.sh 2026-03-21
# API: GET /market-reviews/daily/{trade_date}

set -e

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <trade_date>" >&2
    echo "示例: $0 2026-03-21" >&2
    exit 1
fi

TRADE_DATE="$1"

curl -sf "${API_URL}/market-reviews/daily/${TRADE_DATE}" | jq .
