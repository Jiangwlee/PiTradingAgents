#!/usr/bin/env bash
# fetch-trend-pool.sh - 获取趋势池排行
# 用法: ./fetch-trend-pool.sh <trade_date> [limit] [sort]
# 示例: ./fetch-trend-pool.sh 2026-03-21 100 trend_score
# API: GET /trend-pool/daily?trade_date={trade_date}&limit={limit}&sort={sort}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <trade_date> [limit] [sort]" >&2
    echo "示例: $0 2026-03-21 100 trend_score" >&2
    exit 1
fi

TRADE_DATE="$1"
LIMIT="${2:-100}"
SORT="${3:-trend_score}"
ENRICH="${4:-true}"

curl -sf --connect-timeout 5 --max-time 60 "${API_URL}/trend-pool/daily?trade_date=${TRADE_DATE}&limit=${LIMIT}&sort=${SORT}&enrich=${ENRICH}" | jq .
