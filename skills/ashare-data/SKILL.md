---
name: ashare-data
description: A股市场数据采集 Skill，封装 ashare-platform API 调用
tools: bash
---

# ashare-data Skill

本 Skill 提供 A 股市场数据的统一采集接口，封装对 ashare-platform API 的调用。

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `ASHARE_API_URL` | `http://127.0.0.1:8000` | ashare-platform API 地址 |

## 可用脚本

### 市场情绪数据

| 脚本 | 功能 | 用法 |
|------|------|------|
| `fetch-market-emotion.sh` | 获取单日市场情绪数据 | `./fetch-market-emotion.sh <trade_date>` |
| `fetch-market-emotion-history.sh` | 获取市场情绪历史数据 | `./fetch-market-emotion-history.sh [days] [end_date]` |

### 题材情绪数据

| 脚本 | 功能 | 用法 |
|------|------|------|
| `fetch-theme-emotion.sh` | 获取单日题材情绪排行 | `./fetch-theme-emotion.sh <trade_date> [limit] [sort]` |
| `fetch-theme-emotion-history.sh` | 获取单个题材情绪历史 | `./fetch-theme-emotion-history.sh <theme_name> [days]` |

### 题材池数据

| 脚本 | 功能 | 用法 |
|------|------|------|
| `fetch-theme-pool.sh` | 获取单日题材池排行 | `./fetch-theme-pool.sh <trade_date> [limit] [sort]` |
| `fetch-theme-stocks.sh` | 获取题材成分股列表 | `./fetch-theme-stocks.sh <theme_name> <trade_date>` |

### 趋势池数据

| 脚本 | 功能 | 用法 |
|------|------|------|
| `fetch-trend-pool.sh` | 获取单日趋势池排行 | `./fetch-trend-pool.sh <trade_date> [limit] [sort]` |
| `fetch-trend-stock-history.sh` | 获取个股趋势历史 | `./fetch-trend-stock-history.sh <code> [days]` |

### 市场复盘数据

| 脚本 | 功能 | 用法 |
|------|------|------|
| `fetch-market-review.sh` | 获取市场复盘数据 | `./fetch-market-review.sh <trade_date>` |

## 参数说明

- `trade_date`: 交易日期，格式 `YYYY-MM-DD`
- `theme_name`: 题材名称，如 "机器人"
- `code`: 股票代码，如 "002123"
- `days`: 历史天数，默认 20
- `end_date`: 结束日期，格式 `YYYY-MM-DD`
- `limit`: 返回条数限制
- `sort`: 排序字段

## 错误处理

所有脚本：
- 使用 `curl -sf` 调用 API（`-s` 静默模式，`-f` HTTP 错误时返回非零）
- 输出通过 `jq .` 格式化
- 出错时写入 stderr 并以非零退出码退出

## 参考文档

- `references/emotion-cycle-theory.md` — 情绪周期六阶段理论
- `references/emotion-cycle-indicators.md` — 情绪周期量化指标
- `references/api-guide.md` — API 接口速查手册

## 示例

```bash
# 获取某日市场情绪
cd skills/ashare-data/scripts
./fetch-market-emotion.sh 2026-03-21

# 获取最近20天市场情绪历史
./fetch-market-emotion-history.sh 20 2026-03-21

# 获取某日题材排行（前20）
./fetch-theme-emotion.sh 2026-03-21 20

# 获取"机器人"题材历史情绪
./fetch-theme-emotion-history.sh "机器人" 30
```
