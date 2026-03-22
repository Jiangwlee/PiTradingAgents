#!/bin/bash
# fetch-trend-stock-history.sh - 获取个股趋势历史
# 用法: ./fetch-trend-stock-history.sh <code> [days]
# 示例: ./fetch-trend-stock-history.sh 002123 20
# API: GET /trend-pool/stocks/{code}/history?days={days}

set -e

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <code> [days]" >&2
    echo "示例: $0 002123 20" >&2
    exit 1
fi

CODE="$1"
DAYS="${2:-20}"

curl -sf "${API_URL}/trend-pool/stocks/${CODE}/history?days=${DAYS}" | jq .
