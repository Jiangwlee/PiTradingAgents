#!/usr/bin/env bash
# fetch-theme-stocks.sh - 获取题材成分股列表
# 用法: ./fetch-theme-stocks.sh <theme_name> <trade_date>
# 示例: ./fetch-theme-stocks.sh "机器人" 2026-03-21
# API: GET /theme-pool/daily/{theme_name}/stocks?trade_date={trade_date}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

# URL 编码函数
urlencode() {
    printf '%s' "$1" | jq -sRr @uri 2>/dev/null || printf '%s' "$1"
}

if [ $# -lt 2 ]; then
    echo "用法: $0 <theme_name> <trade_date>" >&2
    echo "示例: $0 \"机器人\" 2026-03-21" >&2
    exit 1
fi

THEME_NAME="$1"
TRADE_DATE="$2"

# URL 编码题材名称
THEME_NAME_ENCODED=$(urlencode "$THEME_NAME")

curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/theme-pool/daily/${THEME_NAME_ENCODED}/stocks?trade_date=${TRADE_DATE}" | jq .
