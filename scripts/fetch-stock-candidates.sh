#!/usr/bin/env bash
# fetch-stock-candidates.sh - 获取主流题材强势股候选池（连阳+新高，已交叉题材）
# 用法: ./fetch-stock-candidates.sh <trade_date> [min_consecutive_days] [top_n_themes]
# 示例: ./fetch-stock-candidates.sh 2026-04-02 5 10
# API: GET /stocks/candidates/{trade_date}

set -euo pipefail

API_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

if [ $# -lt 1 ]; then
    echo "用法: $0 <trade_date> [min_consecutive_days] [top_n_themes]" >&2
    echo "示例: $0 2026-04-02 5 10" >&2
    exit 1
fi

TRADE_DATE="$1"
MIN_DAYS="${2:-5}"
TOP_N="${3:-10}"

curl -sf --connect-timeout 5 --max-time 30 \
    "${API_URL}/stocks/candidates/${TRADE_DATE}?min_consecutive_days=${MIN_DAYS}&top_n_themes=${TOP_N}&exclude_yizi=true&include_new_high=true" \
    | jq .
