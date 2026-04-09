#!/usr/bin/env bash
# fetch-ths-ljqs.sh - 获取同花顺量价齐升股票排行
# 用法: ./fetch-ths-ljqs.sh
# 来源: http://data.10jqka.com.cn/rank/ljqs/
# 输出: JSON 数组 [{code, name, source, price, volume_price_up_days, period_change_pct, turnover_rate, industry}, ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:149.0) Gecko/20100101 Firefox/149.0'

curl -sf --connect-timeout 10 --max-time 30 \
    'http://data.10jqka.com.cn/rank/ljqs/' \
    -H "User-Agent: $UA" \
    -H 'Accept: text/html' \
    -H 'Accept-Encoding: gzip, deflate' \
    --compressed \
    | iconv -f gbk -t utf-8 \
    | python3 "$SCRIPT_DIR/parse-ths-table.py" --source ths_ljqs
