#!/usr/bin/env bash
# fetch-market-emotion-history.sh - 获取市场情绪历史数据
# 用法: ./fetch-market-emotion-history.sh [days] [end_date]
# 示例: ./fetch-market-emotion-history.sh 20 2026-03-21
# API: GET /market-emotion/history?days={days}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

DAYS="${1:-20}"
END_DATE="${2:-}"

if [ -n "$END_DATE" ]; then
    curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/market-emotion/history?days=${DAYS}&end_date=${END_DATE}" | jq .
else
    curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/market-emotion/history?days=${DAYS}" | jq .
fi
