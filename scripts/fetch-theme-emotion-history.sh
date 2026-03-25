#!/usr/bin/env bash
# fetch-theme-emotion-history.sh - 获取单个题材情绪历史
# 用法: ./fetch-theme-emotion-history.sh <theme_name> [days]
# 示例: ./fetch-theme-emotion-history.sh "机器人" 20
# API: GET /theme-emotion/themes/{theme_name}/history?days={days}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

# URL 编码函数
urlencode() {
    printf '%s' "$1" | jq -sRr @uri 2>/dev/null || printf '%s' "$1"
}

if [ $# -lt 1 ]; then
    echo "用法: $0 <theme_name> [days]" >&2
    echo "示例: $0 \"机器人\" 20" >&2
    exit 1
fi

THEME_NAME="$1"
DAYS="${2:-20}"

# URL 编码题材名称
THEME_NAME_ENCODED=$(urlencode "$THEME_NAME")

curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/theme-emotion/themes/${THEME_NAME_ENCODED}/history?days=${DAYS}" | jq .
