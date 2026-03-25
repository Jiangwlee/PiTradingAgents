---
name: ashare-data
description: "A-share market data skill wrapping the ashare-platform API. Use when: (1) fetching daily market emotion indicators, (2) retrieving theme pool or theme emotion rankings, (3) querying trend pool or individual stock trend history, (4) getting market review data."
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
| `trend-pool` | Daily trend pool ranking | `pi-trader data trend-pool <trade_date> [limit] [sort]` |
| `trend-history` | Individual stock trend history | `pi-trader data trend-history <code> [days]` |

### Market Review

| Command | Function | Usage |
|---------|----------|-------|
| `review` | Market review data | `pi-trader data review <trade_date>` |

### Screening

| Command | Function | Usage |
|---------|----------|-------|
| `consecutive-red` | Consecutive up stocks | `pi-trader data consecutive-red <trade_date> [min_days]` |
| `new-high` | Historical new high stocks | `pi-trader data new-high <trade_date>` |

## Parameters

- `trade_date`: trading date in `YYYY-MM-DD` format
- `theme_name`: theme name, e.g. `"机器人"` — always quote strings containing Chinese characters
- `code`: stock code, e.g. `"002123"`
- `days`: number of historical days, default 20
- `end_date`: end date in `YYYY-MM-DD` format
- `limit`: maximum number of results to return
- `sort`: sort field

## Return Format

- All list endpoints return a **JSON array** `[...]` directly — not a `{"data": [...]}` wrapper object.
- Access elements with `.[0]`, `.[]` etc. Never use `.data`.
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
- `consecutive_days`: number of consecutive up days
- `gain_pct`: total gain percentage over the consecutive period
- `bars`: daily bar array, each with `date` and `change_pct`

### new-high fields
- `code`: stock code
- `name`: stock name
- `price`: current price
- `change_pct`: change percentage on this day
- `turnover_rate`: turnover rate
- `prev_high`: previous historical high price
- `prev_high_date`: date of previous historical high

## Failure Handling

If a command fails: record "数据获取失败: `<command>`" in the report and continue. Do not retry. Do not call curl directly.

## Guardrails

NO extra jq filters appended to command output. No exceptions.
Output already includes `jq .`; adding a second filter silently returns null or corrupts output.

NO direct curl calls to the API. No exceptions.
NEVER reconstruct the API call manually.

NO `.data` key when accessing output. No exceptions.
All list endpoints return a bare JSON array `[...]`.

