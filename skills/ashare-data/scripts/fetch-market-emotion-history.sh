#!/bin/bash
# fetch-market-emotion-history.sh - 获取市场情绪历史数据
# 用法: ./fetch-market-emotion-history.sh [days] [end_date]
# 示例: ./fetch-market-emotion-history.sh 20 2026-03-21
# API: GET /market-emotion/history?days={days}&end_date={end_date}

set -e

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

DAYS="${1:-20}"
END_DATE="${2:-}"

URL="${API_URL}/market-emotion/history?days=${DAYS}"
if [ -n "$END_DATE" ]; then
    URL="${URL}&end_date=${END_DATE}"
fi

curl -sf "$URL" | jq .
