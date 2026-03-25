#!/usr/bin/env bash
# fetch-trend-stock-history.sh - 获取个股趋势历史数据
# 用法: ./fetch-trend-stock-history.sh <stock_code> [days]
# 示例: ./fetch-trend-stock-history.sh 000001 20
# API: GET /trend-pool/stocks/{stock_code}/history?days={days}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <stock_code> [days]" >&2
    echo "示例: $0 000001 20" >&2
    exit 1
fi

STOCK_CODE="$1"
DAYS="${2:-20}"

curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/trend-pool/stocks/${STOCK_CODE}/history?days=${DAYS}" | jq .
