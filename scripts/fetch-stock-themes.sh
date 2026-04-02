#!/usr/bin/env bash
# fetch-stock-themes.sh - 获取个股题材归属（所属题材、阶段、热度、角色）
# 用法: ./fetch-stock-themes.sh <code> <trade_date>
# 示例: ./fetch-stock-themes.sh 002454 2026-04-02
# API: GET /stocks/themes/{code}/{trade_date}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 2 ]; then
    echo "用法: $0 <code> <trade_date>" >&2
    echo "示例: $0 002454 2026-04-02" >&2
    exit 1
fi

CODE="$1"
TRADE_DATE="$2"

curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/stocks/themes/${CODE}/${TRADE_DATE}" | jq .
