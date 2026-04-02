#!/usr/bin/env bash
# pi-runner.sh - shared agent invocation helpers for pi-trader shell workflows.

set -euo pipefail

PI_RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_TRADER_ROOT="$(cd "$PI_RUNNER_DIR/../.." && pwd)"
PI_STREAM_PY="$PI_TRADER_ROOT/bin/lib/pi-stream.py"

map_model_id() {
    local model="$1"
    case "$model" in
        kimi-k2-thinking) echo "kimi-coding/kimi-k2-thinking" ;;
        kimi-k2p5)        echo "kimi-coding/kimi-k2p5" ;;
        qwen3.5-35b)      echo "litellm-local/qwen3.5-35b" ;;
        qwen3.5-27b)      echo "litellm-local/qwen3.5-27b" ;;
        *)                echo "$model" ;;
    esac
}

extract_frontmatter_field() {
    local path="$1"
    local field="$2"
    awk -F': ' -v field="$field" '
        $0 ~ ("^" field ":") {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            if (field == "tools") gsub(/[[:space:]]/, "", $2)
            print $2
            exit
        }
    ' "$path"
}

extract_system_prompt() {
    local path="$1"
    awk 'BEGIN{n=0} /^---/{n++; next} n>=2{print}' "$path"
}

run_agent_node() {
    local mode="$1"
    local label="$2"
    local output_file="$3"
    local agent_md="$4"
    shift 4

    local append_system_prompt=""
    local passthrough=()
    local json_log="${PI_JSON_LOG:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --append-system-prompt-file)
                local append_file="${2:-}"
                [[ -z "$append_file" ]] && {
                    echo "[错误] --append-system-prompt-file 缺少路径" >&2
                    return 1
                }
                local append_content
                append_content="$(cat "$append_file")"
                if [[ -n "$append_system_prompt" ]]; then
                    append_system_prompt+=$'\n\n'
                fi
                append_system_prompt+="$append_content"
                shift 2
                ;;
            *)
                passthrough+=("$1")
                shift
                ;;
        esac
    done

    local model tools system_prompt
    model="$(extract_frontmatter_field "$agent_md" "model")"
    tools="$(extract_frontmatter_field "$agent_md" "tools")"
    system_prompt="$(extract_system_prompt "$agent_md")"

    if [[ -n "${MODEL_OVERRIDE:-}" ]]; then
        model="$MODEL_OVERRIDE"
    fi
    model="$(map_model_id "$model")"

    local pi_args=(
        --no-session
        --model "$model"
        --tools "$tools"
        --system-prompt "$system_prompt"
        --skill "$PI_TRADER_ROOT/skills/ashare-data"
    )
    if [[ -n "${EXTRA_SKILLS:-}" ]]; then
        for skill_path in $EXTRA_SKILLS; do
            pi_args+=(--skill "$skill_path")
        done
    fi
    if [[ -n "$append_system_prompt" ]]; then
        pi_args+=(--append-system-prompt "$append_system_prompt")
    fi
    pi_args+=("${passthrough[@]}")

    case "$mode" in
        text)
            pi "${pi_args[@]}" --print > "$output_file" 2>&1
            ;;
        stream)
            : "${json_log:=${TMP_DIR:-/tmp}/$(basename "$output_file" .md).jsonl}"
            pi "${pi_args[@]}" --mode json --print \
                | tee "$json_log" \
                | python3 "$PI_STREAM_PY" render-single --label "$label" --model "$model" --tools "$tools"
            python3 "$PI_STREAM_PY" extract-final "$json_log" > "$output_file"
            ;;
        json)
            : "${json_log:=${TMP_DIR:-/tmp}/$(basename "$output_file" .md).jsonl}"
            pi "${pi_args[@]}" --mode json --print | tee "$json_log"
            python3 "$PI_STREAM_PY" extract-final "$json_log" > "$output_file"
            ;;
        capture)
            : "${json_log:=${TMP_DIR:-/tmp}/$(basename "$output_file" .md).jsonl}"
            pi "${pi_args[@]}" --mode json --print > "$json_log" 2>&1
            python3 "$PI_STREAM_PY" extract-final "$json_log" > "$output_file"
            ;;
        interactive)
            pi "${pi_args[@]}"
            ;;
        *)
            echo "[错误] 未知运行模式: $mode" >&2
            return 1
            ;;
    esac
}

render_completed_stream_block() {
    local label="$1"
    local agent_md="$2"
    local json_log="$3"

    local model tools
    model="$(extract_frontmatter_field "$agent_md" "model")"
    tools="$(extract_frontmatter_field "$agent_md" "tools")"
    if [[ -n "${MODEL_OVERRIDE:-}" ]]; then
        model="$MODEL_OVERRIDE"
    fi
    model="$(map_model_id "$model")"
    python3 "$PI_STREAM_PY" render-single --label "$label" --model "$model" --tools "$tools" --file "$json_log"
}


# resolve_trade_date — 确定行情日期
# 规则：若最近交易日是今天且当前时间 < 16:00，使用前一交易日（16:00 前数据未采集完成）
# 依赖：jq，$API_URL 或 $ASHARE_API_URL 环境变量
resolve_trade_date() {
    local _api="${API_URL:-${ASHARE_API_URL:-http://127.0.0.1:8000}}"
    local recent latest prev today now_hhmm
    recent=$(curl -sf --connect-timeout 5 --max-time 10 \
        "$_api/trade-dates/recent?days=30" 2>/dev/null) || {
        echo "[错误] 无法连接 ashare-platform API: $_api" >&2
        echo "[错误] 请确认服务已启动，或手动指定日期" >&2
        return 1
    }
    latest=$(echo "$recent" | jq -r '.trade_dates[-1]')
    prev=$(echo "$recent"   | jq -r '.trade_dates[-2]')
    today=$(date +%Y-%m-%d)
    now_hhmm=$(date +%H%M)

    if [[ "$latest" == "$today" && "$now_hhmm" < "1600" ]]; then
        echo "$prev"
    else
        echo "$latest"
    fi
}
