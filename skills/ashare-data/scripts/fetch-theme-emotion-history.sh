#!/bin/bash
# fetch-theme-emotion-history.sh - 获取单个题材情绪历史
# 用法: ./fetch-theme-emotion-history.sh <theme_name> [days]
# 示例: ./fetch-theme-emotion-history.sh "机器人" 20
# API: GET /theme-emotion/themes/{theme_name}/history?days={days}

set -e

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <theme_name> [days]" >&2
    echo "示例: $0 \"机器人\" 20" >&2
    exit 1
fi

THEME_NAME="$1"
DAYS="${2:-20}"

curl -sf "${API_URL}/theme-emotion/themes/${THEME_NAME}/history?days=${DAYS}" | jq .
