---
name: ashare-data
description: "A-share market data skill wrapping the ashare-platform API. Use when: (1) fetching daily market emotion indicators, (2) retrieving theme pool or theme emotion rankings, (3) querying trend pool or individual stock trend history, (4) getting market review data, (5) fetching strong-stock candidates with theme cross-reference, (6) looking up individual stock fundamentals or theme tags."
tools: bash
---

# ashare-data Skill

Provides unified A-share market data access via the `pi-trader data` CLI.

## Prerequisite Check

Before fetching any data, verify the API is reachable:

```bash
curl -sf --connect-timeout 3 http://127.0.0.1:8000/health > /dev/null
```

If this fails, stop immediately and report: "ashare-platform API unreachable at http://127.0.0.1:8000". Do not proceed.

## Calling Convention

All data is fetched via the `pi-trader data` CLI command:

```bash
pi-trader data emotion 2026-03-21
```

## Available Commands

### Market Emotion

| Command | Function | Usage |
|---------|----------|-------|
| `emotion` | Single-day market emotion | `pi-trader data emotion <trade_date>` |
| `emotion-history` | Market emotion history | `pi-trader data emotion-history [days] [end_date]` |

### Theme Emotion

| Command | Function | Usage |
|---------|----------|-------|
| `theme-emotion` | Daily theme emotion ranking | `pi-trader data theme-emotion <trade_date> [limit] [sort]` |
| `theme-emotion-history` | Single theme emotion history | `pi-trader data theme-emotion-history <theme_name> [days]` |

### Theme Pool

| Command | Function | Usage |
|---------|----------|-------|
| `theme-pool` | Daily theme pool ranking | `pi-trader data theme-pool <trade_date> [limit] [sort]` |
| `theme-stocks` | Theme constituent stocks | `pi-trader data theme-stocks <theme_name> <trade_date>` |

### Trend Pool

| Command | Function | Usage |
|---------|----------|-------|
| `trend-pool` | Daily trend pool ranking (with kline metrics) | `pi-trader data trend-pool <trade_date> [limit] [sort]` |
| `trend-history` | Individual stock trend history | `pi-trader data trend-history <code> [days]` |

**trend-pool enriched fields** (included by default):
- `close`: closing price
- `change_pct`: daily change percentage
- `ma5_deviation`: price deviation from MA5 (%), positive = above MA5
- `consecutive_up_days`: number of consecutive up days
- `gain_5d`: cumulative gain over last 5 trading days (%)

### Market Review

| Command | Function | Usage |
|---------|----------|-------|
| `review` | Market review data | `pi-trader data review <trade_date>` |

### Screening

| Command | Function | Usage |
|---------|----------|-------|
| `consecutive-red` | Consecutive up stocks | `pi-trader data consecutive-red <trade_date> [days] [min_red]` |
| `new-high` | Historical new high stocks | `pi-trader data new-high <trade_date>` |

### Individual Stock Research

| Command | Function | Usage |
|---------|----------|-------|
| `stock-candidates` | Strong-stock candidate pool with theme cross-reference | `pi-trader data stock-candidates <trade_date> [min_days] [top_n_themes]` |
| `stock-fundamental` | Analyst ratings + 6-year financial forecast | `pi-trader data stock-fundamental <code>` |
| `stock-themes` | Stock theme tags (role, stage, heat, delta) | `pi-trader data stock-themes <code> <trade_date>` |

## Parameters

- `trade_date`: trading date in `YYYY-MM-DD` format
- `theme_name`: theme name, e.g. `"机器人"` — always quote strings containing Chinese characters
- `code`: stock code, e.g. `"002123"`
- `days`: number of historical days, default 20
- `end_date`: end date in `YYYY-MM-DD` format
- `limit`: maximum number of results to return
- `sort`: sort field

## Return Format

- Most list endpoints return a **JSON array** `[...]` directly — not a `{"data": [...]}` wrapper object.
- Access elements with `.[0]`, `.[]` etc. Never use `.data`.
- Exception: `new-high` returns `{"trade_date": "...", "count": N, "stocks": [...]}` — the script extracts `.stocks` automatically, so callers still receive a bare array.
- The `theme_stage` field uses English codes. Translate to Chinese when writing reports:

| API value | Chinese stage |
|-----------|--------------|
| `early`     | 启动 |
| `ferment`   | 发酵 |
| `main_rise` | 主升 |
| `climax`    | 高潮 |
| `middle`    | 分歧 |
| `late`      | 退潮 |

### consecutive-red fields
- `code`: stock code
- `name`: stock name
- `sc`: full code with exchange prefix (e.g. `SH600396`)
- `window_days`: window size (5 or 7)
- `red_count`: actual number of up days within the window
- `min_red`: min_red filter value used in this query (may be absent if not filtered)
- `gain_pct`: total gain percentage over the window period
- `bars`: daily bar array, each with `date` and `change_pct`

### new-high fields
- `code`: stock code
- `name`: stock name
- `price`: current price
- `change_pct`: change percentage on this day
- `turnover_rate`: turnover rate
- `prev_high`: previous historical high price
- `prev_high_date`: date of previous historical high

### stock-candidates fields
- `code`, `name`: stock identifier
- `source`: `consecutive_red` | `new_high` | `both`
- `consecutive_up_days`, `period_gain_pct`, `bars`: trend structure (consecutive_red/both only)
- `prev_high`, `prev_high_date`, `change_pct_today`: new-high context (new_high/both only)
- `primary_theme`, `primary_theme_rank`, `primary_theme_cycle_hint`: top matched theme
- `theme_resonance`: true if primary theme is in top-N themes
- `prev_day_yizi`: true if previous day was a one-character-limit stock (filtered out by default)

### stock-fundamental fields
- `analyst_count`: number of analysts covering the stock
- `ratings`: `{buy, outperform, neutral, underperform, sell}` counts
- `forecast_years`: list of years (3 actuals + 3 forecasts), each with `revenue`, `revenue_growth`, `net_profit`, `net_profit_growth`, `roe`, `pe_dynamic`, `is_actual`

### stock-themes fields (list)
- `theme_name`, `theme_rank`, `theme_cycle_hint`, `theme_heat_score`: theme identity and status
- `role_in_theme`: `leader` | `core` | `member` | `edge` (may be null)
- `rank_in_theme`: stock's rank within the theme
- `theme_rank_3d_delta`: theme rank change over 3 days (negative = rising)
- `is_theme_leader`: whether this stock is the theme leader today
- `leader_names`: list of leader stock names in this theme

## Failure Handling

If a command fails: record "数据获取失败: `<command>`" in the report and continue. Do not retry. Do not call curl directly.

## Guardrails

NO extra jq filters appended to command output. No exceptions.
Output already includes `jq .`; adding a second filter silently returns null or corrupts output.

NO direct curl calls to the API. No exceptions.
NEVER reconstruct the API call manually.

NO `.data` key when accessing output. No exceptions.
All list endpoints return a bare JSON array `[...]`.

