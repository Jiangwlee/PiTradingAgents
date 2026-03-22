# ashare-platform API 速查手册

## 基础信息

- **Base URL**: `http://127.0.0.1:8000`（可通过 `ASHARE_API_URL` 环境变量修改）
- **数据格式**: JSON
- **日期格式**: `YYYY-MM-DD`

---

## API 端点列表

### 1. 单日市场情绪

| 项目 | 内容 |
|------|------|
| **端点** | `GET /market-emotion/daily/{trade_date}` |
| **脚本** | `fetch-market-emotion.sh` |
| **参数** | `trade_date` (必填) - 交易日期 |
| **返回** | 当日市场情绪综合数据 |

**示例**:
```bash
./fetch-market-emotion.sh 2026-03-21
```

---

### 2. 市场情绪历史

| 项目 | 内容 |
|------|------|
| **端点** | `GET /market-emotion/history?days={days}&end_date={end_date}` |
| **脚本** | `fetch-market-emotion-history.sh` |
| **参数** | `days` (可选，默认20) - 历史天数<br>`end_date` (可选) - 结束日期 |
| **返回** | 历史市场情绪数据列表 |

**示例**:
```bash
./fetch-market-emotion-history.sh 20 2026-03-21
```

---

### 3. 单日题材情绪排行

| 项目 | 内容 |
|------|------|
| **端点** | `GET /theme-emotion/daily?trade_date={trade_date}&limit={limit}&sort={sort}` |
| **脚本** | `fetch-theme-emotion.sh` |
| **参数** | `trade_date` (必填) - 交易日期<br>`limit` (可选，默认50) - 返回条数<br>`sort` (可选，默认theme_rank) - 排序字段 |
| **返回** | 题材情绪排行列表 |

**示例**:
```bash
./fetch-theme-emotion.sh 2026-03-21 50 theme_rank
```

---

### 4. 单个题材情绪历史

| 项目 | 内容 |
|------|------|
| **端点** | `GET /theme-emotion/themes/{theme_name}/history?days={days}` |
| **脚本** | `fetch-theme-emotion-history.sh` |
| **参数** | `theme_name` (必填) - 题材名称<br>`days` (可选，默认20) - 历史天数 |
| **返回** | 单个题材历史情绪数据 |

**示例**:
```bash
./fetch-theme-emotion-history.sh "机器人" 30
```

---

### 5. 单日题材池排行

| 项目 | 内容 |
|------|------|
| **端点** | `GET /theme-pool/daily?trade_date={trade_date}&limit={limit}&sort={sort}` |
| **脚本** | `fetch-theme-pool.sh` |
| **参数** | `trade_date` (必填) - 交易日期<br>`limit` (可选，默认100) - 返回条数<br>`sort` (可选，默认theme_rank) - 排序字段 |
| **返回** | 题材池排行列表 |

**示例**:
```bash
./fetch-theme-pool.sh 2026-03-21 100 theme_rank
```

---

### 6. 题材成分股列表

| 项目 | 内容 |
|------|------|
| **端点** | `GET /theme-pool/daily/{theme_name}/stocks?trade_date={trade_date}` |
| **脚本** | `fetch-theme-stocks.sh` |
| **参数** | `theme_name` (必填) - 题材名称<br>`trade_date` (必填) - 交易日期 |
| **返回** | 题材成分股列表 |

**示例**:
```bash
./fetch-theme-stocks.sh "机器人" 2026-03-21
```

---

### 7. 单日趋势池排行

| 项目 | 内容 |
|------|------|
| **端点** | `GET /trend-pool/daily?trade_date={trade_date}&limit={limit}&sort={sort}` |
| **脚本** | `fetch-trend-pool.sh` |
| **参数** | `trade_date` (必填) - 交易日期<br>`limit` (可选，默认100) - 返回条数<br>`sort` (可选，默认rank) - 排序字段 |
| **返回** | 趋势池股票排行列表 |

**示例**:
```bash
./fetch-trend-pool.sh 2026-03-21 100 rank
```

---

### 8. 个股趋势历史

| 项目 | 内容 |
|------|------|
| **端点** | `GET /trend-pool/stocks/{code}/history?days={days}` |
| **脚本** | `fetch-trend-stock-history.sh` |
| **参数** | `code` (必填) - 股票代码<br>`days` (可选，默认20) - 历史天数 |
| **返回** | 个股趋势历史数据 |

**示例**:
```bash
./fetch-trend-stock-history.sh 002123 20
```

---

### 9. 市场复盘数据

| 项目 | 内容 |
|------|------|
| **端点** | `GET /market-reviews/daily/{trade_date}` |
| **脚本** | `fetch-market-review.sh` |
| **参数** | `trade_date` (必填) - 交易日期 |
| **返回** | 当日市场复盘综合报告 |

**示例**:
```bash
./fetch-market-review.sh 2026-03-21
```

---

## 返回字段说明

### 市场情绪数据
- `trade_date`: 交易日期
- `emotion_index`: 情绪指数
- `limit_up_count`: 涨停家数
- `limit_down_count`: 跌停家数
- `up_count`: 上涨家数
- `down_count`: 下跌家数
- `turnover`: 成交额

### 题材情绪数据
- `theme_name`: 题材名称
- `theme_rank`: 题材排名
- `emotion_score`: 情绪得分
- `lead_stock`: 龙头股
- `stocks_count`: 成分股数量

### 趋势池数据
- `code`: 股票代码
- `name`: 股票名称
- `rank`: 趋势排名
- `trend_score`: 趋势得分
- `close_price`: 收盘价
- `change_pct`: 涨跌幅
