# ashare-platform 接口需求文档

**版本**: v1.2
**日期**: 2026-04-02
**需求方**: PiTradingAgents — 情绪周期分析 Agent 团队
**目标系统**: ashare-platform (FastAPI)

---

## 概述

PiTradingAgents 的 Agent 团队需要从 ashare-platform 获取市场情绪、题材情绪等数据，用于情绪周期阶段判断和题材交易决策。

当前 ashare-platform 已有 `market_emotion_daily` 和 `theme_emotion_daily` 两张数据表，但**未暴露 API 端点**。此外，情绪周期理论所需的部分关键指标（封板率、晋级率、涨跌家数、成交量）尚未采集。

本文档分为两部分：
- **Part A**：已有数据的 API 暴露（4 个端点）
- **Part B**：新增数据采集 + API 暴露（扩展现有表 + 1 个新端点）

---

## Part A：已有数据的 API 暴露

### A1. 获取单日市场情绪

**用途**：情绪分析师判断当日市场处于情绪周期哪个阶段

```
GET /market-emotion/daily/{trade_date}
```

**路径参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| trade_date | string | 是 | 交易日期，格式 YYYY-MM-DD |

**响应 Schema** — `MarketEmotionDailyResponse`：

```json
{
  "trade_date": "2026-03-21",
  "source": "ths",

  // ---- 核心计数 ----
  "limit_up_count": 58,
  "limit_down_count": 3,
  "highest_board": 7,
  "limit_up_ladder_count": 12,
  "board_ge_2_count": 15,
  "board_ge_3_count": 8,
  "board_ge_4_count": 3,
  "blowup_rate": 0.18,
  "yesterday_limit_up_return": 0.023,

  // ---- 题材概况 ----
  "theme_count": 25,
  "top_theme_name": "低空经济",
  "top_theme_limit_up_num": 12,

  // ---- 趋势变化（3d/5d delta） ----
  "highest_board_3d_delta": 2,
  "highest_board_5d_delta": 3,
  "board_ge_3_count_3d_delta": 1,
  "board_ge_4_count_3d_delta": 0,
  "limit_up_count_3d_delta": 15,
  "limit_down_count_3d_delta": -5,
  "top_theme_limit_up_num_3d_delta": 4,

  // ---- 综合评分 ----
  "heat_score": 12.5,
  "risk_score": 4.2,
  "emotion_score": 8.3,
  "cycle_stage_hint": "expanding",

  // ---- 计算依据 ----
  "evidence_json": {}
}
```

**响应字段说明**：

| 字段 | 类型 | 可空 | 说明 |
|------|------|------|------|
| trade_date | string | 否 | 交易日期 |
| source | string | 否 | 数据源标识，默认 "ths" |
| limit_up_count | int \| null | 是 | 涨停家数 |
| limit_down_count | int \| null | 是 | 跌停家数 |
| highest_board | int | 否 | 最高连板数 |
| limit_up_ladder_count | int | 否 | 涨停梯队数 |
| board_ge_2_count | int | 否 | ≥2 板个股数 |
| board_ge_3_count | int | 否 | ≥3 板个股数 |
| board_ge_4_count | int | 否 | ≥4 板个股数 |
| blowup_rate | float \| null | 是 | 炸板率（0-1） |
| yesterday_limit_up_return | float \| null | 是 | 昨日涨停股今日收益率 |
| theme_count | int | 否 | 活跃题材数量 |
| top_theme_name | string \| null | 是 | 最强题材名称 |
| top_theme_limit_up_num | int \| null | 是 | 最强题材涨停数 |
| highest_board_3d_delta | int \| null | 是 | 最高板 3 日变化 |
| highest_board_5d_delta | int \| null | 是 | 最高板 5 日变化 |
| board_ge_3_count_3d_delta | int \| null | 是 | ≥3 板数量 3 日变化 |
| board_ge_4_count_3d_delta | int \| null | 是 | ≥4 板数量 3 日变化 |
| limit_up_count_3d_delta | int \| null | 是 | 涨停数 3 日变化 |
| limit_down_count_3d_delta | int \| null | 是 | 跌停数 3 日变化 |
| top_theme_limit_up_num_3d_delta | int \| null | 是 | 最强题材涨停数 3 日变化 |
| heat_score | float \| null | 是 | 市场热度得分 |
| risk_score | float \| null | 是 | 市场风险得分 |
| emotion_score | float \| null | 是 | 综合情绪得分（heat - risk） |
| cycle_stage_hint | string \| null | 是 | 周期阶段提示：ice / warming / expanding / peak / cooling |
| evidence_json | object \| null | 是 | 计算依据（30 天窗口边界等） |

**错误响应**：
- `404`：指定日期无数据

---

### A2. 获取市场情绪历史

**用途**：情绪分析师观察情绪趋势变化，判断周期转换方向

```
GET /market-emotion/history
```

**查询参数**：

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| days | int | 否 | 20 | 回溯天数，范围 1-60 |
| end_date | string | 否 | 最近交易日 | 截止日期，格式 YYYY-MM-DD |

**响应**：`list[MarketEmotionDailyResponse]`，按 trade_date 升序排列。

---

### A3. 获取单日题材情绪列表

**用途**：题材分析师判断各题材所处的情绪周期阶段

```
GET /theme-emotion/daily
```

**查询参数**：

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| trade_date | string | 是 | — | 交易日期，格式 YYYY-MM-DD |
| cycle_hint | string | 否 | — | 按周期阶段过滤：start / ferment / main_rise / climax / bad_divergence |
| limit | int | 否 | 50 | 返回数量，范围 1-200 |
| sort | string | 否 | theme_rank | 排序方式：theme_rank / -heat_score / -limit_up_num |

**响应 Schema** — `ThemeEmotionDailyResponse`：

```json
{
  "trade_date": "2026-03-21",
  "theme_name": "低空经济",
  "theme_rank": 1,
  "source": "ths_block_top",

  // ---- 核心指标 ----
  "limit_up_num": 12,
  "theme_change_pct": 3.25,
  "sample_stock_count": 45,
  "first_limit_count": 8,
  "limit_back_count": 1,
  "high_limit_count": 3,

  // ---- 龙头指标 ----
  "leader_names_json": ["三房巷", "中信海直"],
  "leader_board_max": 5,
  "leader_board_count_ge_2": 3,
  "leader_continuity_score": 6.5,

  // ---- 趋势变化 ----
  "theme_rank_3d_delta": -2,
  "limit_up_num_3d_delta": 5,
  "limit_up_num_5d_delta": 8,
  "theme_change_3d_mean": 2.1,
  "leader_board_max_3d_trend": 1,

  // ---- 综合评分 ----
  "heat_score": 18.2,
  "risk_score": 3.5,
  "theme_cycle_hint": "main_rise",

  // ---- 计算依据 ----
  "evidence_json": {}
}
```

**响应字段说明**：

| 字段 | 类型 | 可空 | 说明 |
|------|------|------|------|
| trade_date | string | 否 | 交易日期 |
| theme_name | string | 否 | 题材名称 |
| theme_rank | int | 否 | 题材排名 |
| source | string | 否 | 数据源标识 |
| limit_up_num | int | 否 | 题材涨停股数量 |
| theme_change_pct | float \| null | 是 | 题材整体涨跌幅 (%) |
| sample_stock_count | int | 否 | 题材成分股数量 |
| first_limit_count | int | 否 | 首板数量 |
| limit_back_count | int | 否 | 炸板回封数量 |
| high_limit_count | int | 否 | 高位涨停数量 |
| leader_names_json | list[string] \| null | 是 | 龙头股名称列表 |
| leader_board_max | int | 否 | 龙头最高连板数 |
| leader_board_count_ge_2 | int | 否 | ≥2 板龙头数量 |
| leader_continuity_score | float \| null | 是 | 龙头连续性得分 |
| theme_rank_3d_delta | int \| null | 是 | 排名 3 日变化（负=上升） |
| limit_up_num_3d_delta | int \| null | 是 | 涨停数 3 日变化 |
| limit_up_num_5d_delta | int \| null | 是 | 涨停数 5 日变化 |
| theme_change_3d_mean | float \| null | 是 | 近 3 日平均涨跌幅 |
| leader_board_max_3d_trend | int \| null | 是 | 龙头连板高度 3 日趋势 |
| heat_score | float \| null | 是 | 题材热度得分 |
| risk_score | float \| null | 是 | 题材风险得分 |
| theme_cycle_hint | string \| null | 是 | 题材周期阶段：start / ferment / main_rise / climax / bad_divergence |
| evidence_json | object \| null | 是 | 计算依据 |

**响应**：`list[ThemeEmotionDailyResponse]`

---

### A4. 获取单题材情绪历史

**用途**：跟踪特定题材的情绪演变过程，判断题材生命周期位置

```
GET /theme-emotion/themes/{theme_name}/history
```

**路径参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| theme_name | string | 是 | 题材名称 |

**查询参数**：

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| days | int | 否 | 20 | 回溯天数，范围 1-60 |

**响应**：`list[ThemeEmotionDailyResponse]`，按 trade_date 升序排列。

---

## Part B：新增数据采集 + API 暴露

以下指标是情绪周期理论的**硬阈值判据**，当前未被 ashare-platform 采集。

### B1. 扩展 market_emotion_daily 表

在现有 `market_emotion_daily` 表中新增以下字段：

| 新增字段 | 类型 | 可空 | 说明 | 理论依据 |
|---------|------|------|------|---------|
| advance_count | Integer | 是 | 上涨家数 | >2800 = 修复信号 |
| decline_count | Integer | 是 | 下跌家数 | >4500 = 冰点确认 |
| flat_count | Integer | 是 | 平盘家数 | 辅助判断 |
| seal_rate | Float | 是 | 封板率（0-1） | >0.65 = 情绪修复 |
| promotion_2to3_total | Integer | 是 | 2 板进 3 板：候选数 | 晋级率分母 |
| promotion_2to3_success | Integer | 是 | 2 板进 3 板：成功数 | 晋级率分子 |
| promotion_3to4_total | Integer | 是 | 3 板进 4 板：候选数 | 晋级率分母 |
| promotion_3to4_success | Integer | 是 | 3 板进 4 板：成功数 | 晋级率分子 |
| market_volume | Float | 是 | 市场总成交额（亿元） | 2 万亿 = 结构性行情临界值 |

> **封板率** = 涨停封住家数 / (涨停封住家数 + 炸板家数)
>
> **晋级率** = success / total（当 total = 0 时返回 null）
>
> **注意**：返回原始计数，晋级率由调用方计算，保持接口原子性。

这些字段加入后，A1 和 A2 的响应自动包含它们。

**A1 响应补充字段**：

```json
{
  "...existing fields...": "...",

  // ---- 新增：涨跌分布 ----
  "advance_count": 2856,
  "decline_count": 1890,
  "flat_count": 209,

  // ---- 新增：封板率 ----
  "seal_rate": 0.72,

  // ---- 新增：晋级率原始数据 ----
  "promotion_2to3_total": 12,
  "promotion_2to3_success": 10,
  "promotion_3to4_total": 5,
  "promotion_3to4_success": 4,

  // ---- 新增：成交量 ----
  "market_volume": 23456.78
}
```

### B2. 扩展 theme stocks 响应字段

**用途**：催化剂分析师判断题材成分股的强弱、连板高度、涨停原因，识别最符合题材方向的核心个股。

当前 `GET /theme-pool/daily/{theme_name}/stocks` 返回的 `ThemeStockDailyResponse` 缺少 `evidence_json` 中的关键字段。

**需要在 ThemeStockDailyResponse 中新增以下字段**：

| 新增字段 | 类型 | 可空 | 说明 | 来源 |
|---------|------|------|------|------|
| continue_num | int \| null | 是 | 连板数（0=非连板） | evidence_json.continue_num |
| change_rate | float \| null | 是 | 当日涨跌幅 (%) | evidence_json.change_rate |
| reason_type | string \| null | 是 | 涨停原因/题材关联标签 | evidence_json.reason_type |
| change_tag | string \| null | 是 | 涨停类型标签 | evidence_json.change_tag |

**change_tag 枚举值**：
- `FIRST_LIMIT` — 首板涨停
- `LIMIT_BACK` — 炸板回封
- `HIGH_LIMIT` — 高位涨停
- 其他值按数据源原样返回

**扩展后的响应示例**：
```json
{
  "trade_date": "2026-03-18",
  "theme_name": "新能源汽车",
  "code": "002913",
  "name": "奥士康",
  "role": "leader",
  "is_core": true,
  "rank_in_theme": 1,
  "trend_score": 85.2,
  "star_rating": 4,
  "emotion_level": 3,
  "comment": null,
  "continue_num": 3,
  "change_rate": 10.01,
  "reason_type": "新能源汽车+锂电池",
  "change_tag": "HIGH_LIMIT"
}
```

---

### B3. 新增个股 K 线数据接口

**用途**：趋势分析师分析个股的技术形态（K线走势、量价关系），辅助判断个股强弱和买卖时机。

当前 ashare-platform **没有 K 线数据 API**。`fetch_jrj_daily_kline()` 仅在 `red_for_n_days` 管线中临时使用，不入库不暴露。

```
GET /kline/daily/{code}
```

**路径参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| code | string | 是 | 股票代码 |

**查询参数**：

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| days | int | 否 | 20 | 回溯交易日数，范围 1-120 |

**响应 Schema** — `KlineDailyResponse`：

```json
[
  {
    "date": "2026-03-18",
    "open": 12.50,
    "high": 13.20,
    "low": 12.30,
    "close": 13.10,
    "volume": 1523400,
    "amount": 19856.32,
    "change_pct": 4.80
  }
]
```

**响应字段说明**：

| 字段 | 类型 | 可空 | 说明 |
|------|------|------|------|
| date | string | 否 | 交易日期 |
| open | float | 否 | 开盘价 |
| high | float | 否 | 最高价 |
| low | float | 否 | 最低价 |
| close | float | 否 | 收盘价 |
| volume | int | 否 | 成交量（手） |
| amount | float | 否 | 成交额（万元） |
| change_pct | float \| null | 是 | 涨跌幅 (%) |

**响应**：`list[KlineDailyResponse]`，按 date 升序排列。

**实现建议**：
- 可复用现有的 `fetch_jrj_daily_kline()` 数据源
- K 线数据无需入库，可实时从数据源获取（透传模式）
- 如考虑性能，可增加缓存或入库

---

### B4. 新增数据源采集建议

| 指标 | 可选数据源 | 采集方式 |
|------|-----------|---------|
| 上涨/下跌/平盘家数 | 东方财富大盘行情 | HTTP API |
| 封板率 | 东方财富涨停板复盘 | HTTP API（涨停封住 vs 炸板） |
| 晋级率 (2→3, 3→4) | 东方财富连板统计 | 基于现有 THS 连板数据推算，或东财 HTTP API |
| 市场总成交额 | 东方财富/新浪大盘数据 | HTTP API |

> 具体的数据源接口选择由 ashare-platform 开发者确定，此处仅说明需求。

---

---

## Part C：个股深度研究支撑接口

**背景**：个股研究员（stock-researcher）需要对每只候选股票进行五维度评估（技术面、题材面、赛道地位、基本面、消息面）。当前 pi-trader 侧只有原始 K 线和候选池数据，无法完成这些分析。

**设计原则**：分析逻辑在 ashare-platform 侧完成，pi-trader 只消费结论性字段，不做二次计算。

---

### C1. 个股技术面分析摘要

**用途**：直接给出技术面结论，研究员无需自行解读 K 线数据

```
GET /stocks/{code}/technical-summary/{trade_date}
```

**路径参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| code | string | 是 | 股票代码 |
| trade_date | string | 是 | 交易日期，格式 YYYY-MM-DD |

**响应 Schema** — `TechnicalSummaryResponse`：

```json
{
  "code": "600396",
  "name": "大众公用",
  "trade_date": "2026-03-21",

  // ---- 均线 ----
  "ma5": 12.50,
  "ma10": 12.10,
  "ma20": 11.80,
  "ma30": 11.50,
  "ma60": 10.90,
  "ma120": 10.20,
  "ma_alignment": "bullish",

  // ---- 连阳结构 ----
  "consecutive_up_days": 7,
  "period_gain_pct": 18.5,

  // ---- 量能 ----
  "turnover_rate": 3.2,
  "volume_ratio": 1.8,
  "volume_trend": "increasing",

  // ---- 价格位置 ----
  "price_vs_120d_high_pct": 0.92,
  "is_near_52w_high": true,

  // ---- 区间涨幅 ----
  "change_7d_pct": 15.2,
  "change_30d_pct": 28.6,
  "change_120d_pct": 45.3,

  // ---- 综合评分 ----
  "technical_score": 82,
  "technical_verdict": "strong"
}
```

**关键字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| ma_alignment | string | `bullish`=MA5>MA10>MA20>MA60 多头排列；`bearish`=空头；`mixed`=混合 |
| volume_trend | string | `increasing` / `decreasing` / `stable`（基于近5日成交量趋势） |
| volume_ratio | float | 当日成交量 / 近5日均量 |
| price_vs_120d_high_pct | float | 当前价 / 近120日最高价，0-1，越接近1说明接近历史高位 |
| technical_score | int | 0-100，由 ashare-platform 综合计算（均线/量能/位置加权） |
| technical_verdict | string | `strong` / `neutral` / `weak`，基于 technical_score 的结论标签 |

**评分计算建议**（ashare-platform 内部）：
- MA 多头排列：+30 分
- 连阳天数 ≥5：+20 分
- 量比 ≥1.5（温和放量）：+15 分
- 换手率 2%-8%（健康区间）：+15 分
- 7日涨幅 10%-30%（有动能但未过热）：+20 分

**错误响应**：
- `404`：股票代码不存在或当日无数据

---

### C2. 个股基本面摘要

**用途**：提供公司基础信息和近期财务快照，研究员评估基本面支撑强度

```
GET /stocks/{code}/fundamental-summary
```

**路径参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| code | string | 是 | 股票代码 |

**响应 Schema** — `FundamentalSummaryResponse`：

```json
{
  "code": "600396",
  "name": "大众公用",
  "industry": "公用事业",
  "listed_date": "2001-06-15",

  // ---- 市值与估值 ----
  "market_cap": 185.6,
  "circulating_market_cap": 142.3,
  "pe_ttm": 28.5,
  "pb": 2.1,
  "ps_ttm": 3.2,

  // ---- 近3季度财务（按时间升序，最新在最后） ----
  "quarterly_financials": [
    {
      "period": "2025Q2",
      "revenue": 8.5,
      "revenue_yoy_pct": 12.3,
      "net_profit": 1.2,
      "net_profit_yoy_pct": 18.5,
      "gross_margin": 0.38
    },
    {
      "period": "2025Q3",
      "revenue": 9.1,
      "revenue_yoy_pct": 15.6,
      "net_profit": 1.4,
      "net_profit_yoy_pct": 22.1,
      "gross_margin": 0.40
    },
    {
      "period": "2025Q4",
      "revenue": 10.2,
      "revenue_yoy_pct": 20.1,
      "net_profit": 1.6,
      "net_profit_yoy_pct": 28.3,
      "gross_margin": 0.41
    }
  ],

  // ---- 偿债与现金流 ----
  "debt_to_asset_ratio": 0.45,
  "operating_cash_flow": 2.3,

  // ---- 机构持仓（最新季报） ----
  "institution_holding_pct": 0.32,
  "top_holder_change": "increasing"
}
```

**关键字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| market_cap | float | 总市值（亿元） |
| quarterly_financials | list | 最近3个已披露季度，按时间升序，最新在最后 |
| revenue_yoy_pct | float | 营收同比增速 (%) |
| gross_margin | float | 毛利率（0-1） |
| top_holder_change | string | 近一季度主要股东持仓变化：`increasing` / `decreasing` / `stable` / `unknown` |

**数据来源建议**：AkShare `ak.stock_financial_report_sina()` 或同类接口

---

### C3. 个股题材归属与热度

**用途**：直接告知研究员该股属于哪些题材、每个题材的当前阶段和热度排名，避免研究员自行交叉比对

```
GET /stocks/{code}/themes/{trade_date}
```

**路径参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| code | string | 是 | 股票代码 |
| trade_date | string | 是 | 交易日期 |

**响应 Schema** — `list[StockThemeTagResponse]`：

```json
[
  {
    "theme_name": "低空经济",
    "role_in_theme": "core",
    "rank_in_theme": 2,
    "theme_rank": 1,
    "theme_cycle_hint": "main_rise",
    "theme_heat_score": 18.2,
    "theme_limit_up_num": 12,
    "theme_rank_3d_delta": -2,
    "is_theme_leader": false,
    "leader_names": ["三房巷", "中信海直"]
  },
  {
    "theme_name": "城市低空基础设施",
    "role_in_theme": "member",
    "rank_in_theme": 5,
    "theme_rank": 8,
    "theme_cycle_hint": "ferment",
    "theme_heat_score": 9.5,
    "theme_limit_up_num": 4,
    "theme_rank_3d_delta": -3,
    "is_theme_leader": false,
    "leader_names": ["XX股份"]
  }
]
```

**关键字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| role_in_theme | string | `leader`=龙头；`core`=核心成员；`member`=普通成员；`edge`=边缘受益 |
| rank_in_theme | int | 该股在题材内的排名（按涨停/连板高度） |
| theme_rank | int | 题材在全市场题材池中的排名 |
| theme_cycle_hint | string | 题材周期阶段（与 A3 一致：start/ferment/main_rise/climax/bad_divergence） |
| theme_rank_3d_delta | int | 题材排名3日变化，负值=排名上升（热度提升） |
| is_theme_leader | bool | 该股是否为该题材当日龙头 |

**空响应**：若股票未被任何题材收录，返回 `[]`

---

### C4. 赛道地位分析

**用途**：在同行业中定位该股的市值排名和近期相对强弱，判断是龙头/次龙/跟风

```
GET /stocks/{code}/sector-position/{trade_date}
```

**路径参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| code | string | 是 | 股票代码 |
| trade_date | string | 是 | 交易日期 |

**响应 Schema** — `SectorPositionResponse`：

```json
{
  "code": "600396",
  "name": "大众公用",
  "industry": "公用事业",
  "sector_stock_count": 85,

  // ---- 市值地位 ----
  "market_cap_rank_in_sector": 12,
  "market_cap_rank_pct": 0.14,

  // ---- 近期相对强弱 ----
  "return_7d_pct": 15.2,
  "sector_avg_return_7d_pct": 3.8,
  "return_7d_vs_sector": 11.4,
  "return_7d_rank_in_sector": 3,

  "return_30d_pct": 28.6,
  "sector_avg_return_30d_pct": 8.2,
  "return_30d_vs_sector": 20.4,
  "return_30d_rank_in_sector": 2,

  // ---- 综合定位 ----
  "sector_role": "sector_leader",
  "sector_role_reason": "7日涨幅行业第3，30日涨幅行业第2，市值行业前20%"
}
```

**关键字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| market_cap_rank_pct | float | 市值排名百分位（0=最大，1=最小）；< 0.2 说明市值偏大弹性受限 |
| return_7d_vs_sector | float | 个股7日涨幅超出行业均值的幅度（百分点） |
| return_7d_rank_in_sector | int | 7日涨幅在行业内的排名 |
| sector_role | string | `sector_leader`=板块领涨龙头；`strong_follow`=强势跟涨；`neutral`=随波逐流；`laggard`=行业拖累 |
| sector_role_reason | string | ashare-platform 生成的一句话判断理由，直接可用于报告 |

**sector_role 判断逻辑建议**（ashare-platform 内部）：
- 7日涨幅排名前10% AND 30日涨幅排名前20% → `sector_leader`
- 7日涨幅排名前30% → `strong_follow`
- 7日涨幅排名前70% → `neutral`
- 其余 → `laggard`

---

### C5. 主流题材强势股候选池（Pipeline 集成接口）

**用途**：为 Pipeline Stage 3.5（个股研究员）直接提供已过滤、已交叉的候选池，替代 pi-trader 侧的三步拼接逻辑

当前 pi-trader 侧的流程：`fetch-consecutive-red.sh` + `fetch-new-high.sh` + `filter-yiziboard.sh` + 手动题材交叉 → 可全部下沉到此接口。

```
GET /stocks/theme-aligned-candidates/{trade_date}
```

**路径参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| trade_date | string | 是 | 交易日期 |

**查询参数**：

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| top_n_themes | int | 否 | 10 | 只纳入主流题材 Top N 中的股票 |
| min_consecutive_days | int | 否 | 5 | 连阳天数下限 |
| exclude_yizi | bool | 否 | true | 排除上一交易日为一字板的股票 |
| include_new_high | bool | 否 | true | 是否纳入历史新高股票 |
| limit | int | 否 | 50 | 最大返回数量 |

**响应 Schema** — `list[ThemeAlignedCandidateResponse]`：

```json
[
  {
    "code": "600396",
    "name": "大众公用",
    "source": "consecutive_red",
    "consecutive_up_days": 7,
    "period_gain_pct": 18.5,
    "change_pct_today": 5.2,

    // ---- 题材交叉结果 ----
    "primary_theme": "低空经济",
    "primary_theme_rank": 1,
    "primary_theme_cycle_hint": "main_rise",
    "role_in_primary_theme": "core",
    "theme_resonance": true,

    // ---- 技术面速览 ----
    "ma_alignment": "bullish",
    "technical_score": 82,
    "technical_verdict": "strong",

    // ---- 一字板过滤 ----
    "prev_day_yizi": false,

    // ---- 综合优先级 ----
    "candidate_score": 91,
    "candidate_rank": 1
  }
]
```

**关键字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| source | string | `consecutive_red`=连阳来源；`new_high`=历史新高来源；`both`=两者同时命中 |
| theme_resonance | bool | 该股主要题材是否在当日 Top N 主流题材中（共振标志） |
| candidate_score | int | 0-100，综合连阳强度 + 技术得分 + 题材热度的加权评分 |
| candidate_rank | int | 在本次候选池中的排名 |

**candidate_score 计算建议**（ashare-platform 内部）：
- 连阳天数 × 3（上限30）：最多 30 分
- technical_score × 0.4：最多 40 分
- 题材热度（theme_heat_score 归一化）：最多 20 分
- theme_resonance = true：+10 分

**与现有接口的关系**：
- 本接口内部依赖 `red_for_n_days`（连阳数据）+ `new_high` + `yizi_filter`（一字板过滤）+ `theme-pool/daily`（题材交叉）
- pi-trader 侧的 `fetch-consecutive-red.sh`、`fetch-new-high.sh`、`filter-yiziboard.sh` 可在此接口上线后废弃

---

### C6. 个股研究快照（一站式复合接口）

**用途**：将 C1-C4 合并为单次调用，个股研究员用此接口完成五维度中的结构化数据采集，减少 API 调用轮次

```
GET /stocks/{code}/research-snapshot/{trade_date}
```

**路径参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| code | string | 是 | 股票代码 |
| trade_date | string | 是 | 交易日期 |

**响应 Schema** — `ResearchSnapshotResponse`：

```json
{
  "code": "600396",
  "name": "大众公用",
  "trade_date": "2026-03-21",

  "technical": { /* C1 TechnicalSummaryResponse 完整内容 */ },
  "fundamental": { /* C2 FundamentalSummaryResponse 完整内容 */ },
  "themes": [ /* C3 list[StockThemeTagResponse] 完整内容 */ ],
  "sector_position": { /* C4 SectorPositionResponse 完整内容 */ },

  // ---- 五维度综合结论（ashare-platform 生成） ----
  "summary": {
    "technical_verdict": "strong",
    "fundamental_verdict": "stable_growth",
    "theme_verdict": "main_theme_core",
    "sector_verdict": "sector_leader",
    "overall_score": 85,
    "highlight": "7连阳+MA多头排列，题材低空经济主升阶段核心票，30日行业涨幅第2"
  }
}
```

**summary 字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| fundamental_verdict | string | `high_growth`=高增长；`stable_growth`=稳健增长；`flat`=持平；`declining`=下滑；`loss`=亏损 |
| theme_verdict | string | `main_theme_leader`=主流题材龙头；`main_theme_core`=主流题材核心；`marginal`=边缘受益；`no_theme`=无题材支撑 |
| overall_score | int | 0-100，四个维度加权综合（技术30% + 题材35% + 赛道20% + 基本面15%） |
| highlight | string | 一句话核心亮点，ashare-platform 自动拼接关键信号，可直接引用入报告 |

**实现建议**：
- 并行调用 C1-C4，在服务端聚合
- 如 C2（财务数据）获取失败，`fundamental` 字段返回 `null`，`fundamental_verdict` 返回 `"unknown"`，不阻塞整体响应

---

## 接口清单汇总

| 编号 | 方法 | 路径 | 类型 | 优先级 |
|------|------|------|------|--------|
| A1 | GET | `/market-emotion/daily/{trade_date}` | 暴露已有数据 | P0 — 已完成 ✅ |
| A2 | GET | `/market-emotion/history` | 暴露已有数据 | P0 — 已完成 ✅ |
| A3 | GET | `/theme-emotion/daily` | 暴露已有数据 | P0 — 已完成 ✅ |
| A4 | GET | `/theme-emotion/themes/{theme_name}/history` | 暴露已有数据 | P0 — 已完成 ✅ |
| B1 | — | 扩展 market_emotion_daily 表 + 采集管线 | 新增数据采集 | P1 — 已完成 ✅ |
| B2 | — | 扩展 ThemeStockDailyResponse 字段 | 暴露已有数据 | P0 — 已完成 ✅ |
| B3 | GET | `/kline/daily/{code}` | 新增接口 | P1 — 已完成 ✅ |
| C1 | GET | `/stocks/{code}/technical-summary/{trade_date}` | 新增接口（计算后返回结论） | P1 |
| C2 | GET | `/stocks/{code}/fundamental-summary` | 新增接口（新数据源） | P2 |
| C3 | GET | `/stocks/{code}/themes/{trade_date}` | 新增接口（题材交叉） | P1 |
| C4 | GET | `/stocks/{code}/sector-position/{trade_date}` | 新增接口（行业横向比较） | P2 |
| C5 | GET | `/stocks/theme-aligned-candidates/{trade_date}` | 新增接口（Pipeline 集成） | P1 |
| C6 | GET | `/stocks/{code}/research-snapshot/{trade_date}` | 新增复合接口（C1+C2+C3+C4） | P2 |

优先级说明：
- **P0**：Agent 团队 MVP 必需，阻塞开发
- **P1**：个股研究员核心功能，建议优先实现
- **P2**：提升分析精度，可在 P1 接口上线后补充

---

## 与现有接口的关系

Agent 团队将同时使用以下已有接口：

| 已有接口 | 使用方 |
|---------|--------|
| `GET /trend-pool/daily` | 趋势分析师 — 获取趋势股池 |
| `GET /trend-pool/stocks/{code}/history` | 趋势分析师 — 个股趋势跟踪 |
| `GET /theme-pool/daily` | 题材分析师 — 获取题材池 |
| `GET /theme-pool/daily/{theme_name}/stocks` | 题材分析师 — 获取题材成分股 |
| `GET /theme-pool/themes/{theme_name}/history` | 题材分析师 — 题材历史跟踪 |
| `GET /market-reviews/daily/{trade_date}` | 决策团队 — 参考市场综述 |
