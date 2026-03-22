#!/bin/bash
# fetch-trend-pool.sh - 获取单日趋势池排行
# 用法: ./fetch-trend-pool.sh <trade_date> [limit] [sort]
# 示例: ./fetch-trend-pool.sh 2026-03-21 100 rank
# API: GET /trend-pool/daily?trade_date={trade_date}&limit={limit}&sort={sort}

set -e

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <trade_date> [limit] [sort]" >&2
    echo "示例: $0 2026-03-21 100 rank" >&2
    exit 1
fi

TRADE_DATE="$1"
LIMIT="${2:-100}"
SORT="${3:-rank}"

curl -sf "${API_URL}/trend-pool/daily?trade_date=${TRADE_DATE}&limit=${LIMIT}&sort=${SORT}" | jq .
