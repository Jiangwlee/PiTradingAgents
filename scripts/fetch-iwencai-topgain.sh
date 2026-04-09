#!/usr/bin/env bash
# fetch-iwencai-topgain.sh - 获取问财涨幅榜 Top 50（60日/120日/240日）
# 用法: ./fetch-iwencai-topgain.sh
# 依赖: omp web-operator (read-url)
# 输出: JSON 数组（三个周期合并），每个元素 {code, name, source, price, change_pct, rank, period_gain_pct}
#       source 取值: iwencai_60d, iwencai_120d, iwencai_240d

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_PY="$SCRIPT_DIR/parse-iwencai-topgain.py"
BASE_URL="https://www.iwencai.com/unifiedwap/result?querytype=stock&w="

# 检查 omp 可用性
if ! command -v omp >/dev/null 2>&1; then
    echo "[]"
    exit 0
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 串行获取三个周期（问财 SPA 页面并行加载不稳定）
for period in 60 120 240; do
    URL="${BASE_URL}${period}日涨幅榜"
    MD=$(omp web-operator read-url "$URL" --limit 8000 2>/dev/null || echo "")
    if [[ -n "$MD" ]]; then
        echo "$MD" | python3 "$PARSE_PY" --period "$period" > "$TMP_DIR/${period}.json" 2>/dev/null
    else
        echo "[]" > "$TMP_DIR/${period}.json"
    fi
done

# 合并三个周期的结果
python3 -c "
import json, sys
merged = []
for p in [60, 120, 240]:
    try:
        with open(f'$TMP_DIR/{p}.json') as f:
            merged.extend(json.load(f))
    except (FileNotFoundError, json.JSONDecodeError):
        pass
json.dump(merged, sys.stdout, ensure_ascii=False, indent=2)
print()
"
