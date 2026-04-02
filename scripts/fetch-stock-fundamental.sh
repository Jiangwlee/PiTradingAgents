#!/usr/bin/env bash
# fetch-stock-fundamental.sh - 获取个股基本面（分析师评级 + 6年财务预测）
# 用法: ./fetch-stock-fundamental.sh <code>
# 示例: ./fetch-stock-fundamental.sh 600519
# API: GET /stocks/fundamental/{code}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <code>" >&2
    echo "示例: $0 600519" >&2
    exit 1
fi

CODE="$1"

curl -sf --connect-timeout 5 --max-time 30 "${API_URL}/stocks/fundamental/${CODE}" | jq .
