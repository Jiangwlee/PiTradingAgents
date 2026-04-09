#!/usr/bin/env bash
# fetch-ths-lxsz.sh - 获取同花顺连续上涨股票排行
# 用法: ./fetch-ths-lxsz.sh
# 来源: http://data.10jqka.com.cn/rank/lxsz/
# 输出: JSON 数组 [{code, name, source, close, consecutive_up_days, consecutive_change_pct, turnover_rate, industry}, ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:149.0) Gecko/20100101 Firefox/149.0'

curl -sf --connect-timeout 10 --max-time 30 \
    'http://data.10jqka.com.cn/rank/lxsz/' \
    -H "User-Agent: $UA" \
    -H 'Accept: text/html' \
    -H 'Accept-Encoding: gzip, deflate' \
    --compressed \
    | iconv -f gbk -t utf-8 \
    | python3 "$SCRIPT_DIR/parse-ths-table.py" --source ths_lxsz
