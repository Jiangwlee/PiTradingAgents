#!/bin/bash
# fetch-theme-emotion.sh - 获取单日题材情绪排行
# 用法: ./fetch-theme-emotion.sh <trade_date> [limit] [sort]
# 示例: ./fetch-theme-emotion.sh 2026-03-21 50 theme_rank
# API: GET /theme-emotion/daily?trade_date={trade_date}&limit={limit}&sort={sort}

set -e

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <trade_date> [limit] [sort]" >&2
    echo "示例: $0 2026-03-21 50 theme_rank" >&2
    exit 1
fi

TRADE_DATE="$1"
LIMIT="${2:-50}"
SORT="${3:-theme_rank}"

curl -sf "${API_URL}/theme-emotion/daily?trade_date=${TRADE_DATE}&limit=${LIMIT}&sort=${SORT}" | jq .
