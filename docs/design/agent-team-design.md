# Agent 团队设计方案

**版本**: v1.0
**日期**: 2026-03-22

---

## 1. 整体架构

```
PiTradingAgents/
├── skills/
│   └── ashare-data/                    # 数据采集 Skill
│       ├── SKILL.md
│       ├── scripts/
│       │   ├── fetch-market-emotion.sh     # 市场情绪数据
│       │   ├── fetch-market-emotion-history.sh
│       │   ├── fetch-theme-emotion.sh      # 题材情绪数据
│       │   ├── fetch-theme-emotion-history.sh
│       │   ├── fetch-theme-pool.sh         # 题材池数据
│       │   ├── fetch-theme-stocks.sh       # 题材成分股
│       │   ├── fetch-trend-pool.sh         # 趋势池数据
│       │   ├── fetch-trend-stock-history.sh
│       │   └── fetch-market-review.sh      # 市场综述
│       └── references/
│           ├── emotion-cycle-theory.md     # 情绪周期六阶段理论
│           ├── emotion-cycle-indicators.md # 量化指标体系
│           └── api-guide.md               # API 接口说明
│
├── agents/                             # Agent 定义（Pi .md 格式）
│   ├── analysts/
│   │   ├── emotion-analyst.md          # 情绪分析师
│   │   ├── theme-analyst.md            # 题材分析师
│   │   ├── trend-analyst.md            # 趋势分析师
│   │   └── catalyst-analyst.md          # 催化剂分析师
│   ├── debaters/
│   │   ├── bull-debater.md             # 看多辩手
│   │   └── bear-debater.md             # 看空辩手
│   ├── judges/
│   │   ├── market-judge.md             # 市场环境裁判
│   │   └── theme-judge.md              # 题材机会裁判
│   └── decision/
│       └── investment-manager.md       # 投资经理
│
├── bin/
│   └── run-analysis.sh                 # Pipeline 编排脚本（Conductor）
│
├── data/
│   ├── reports/                        # 输出报告（按日期归档）
│   │   └── {YYYY-MM-DD}/
│   │       ├── 01-emotion-report.md
│   │       ├── 02-theme-report.md
│   │       ├── 03-trend-report.md
│   │       ├── 04-catalyst-report.md
│   │       ├── 05-market-debate.md
│   │       ├── 06-theme-debate.md
│   │       └── 07-final-report.md
│   └── memory/                         # 记忆/学习存储
│       ├── lessons.jsonl               # 经验教训（追加写入）
│       └── performance.jsonl           # 历史决策与结果
│
└── docs/
    ├── theory/                         # 情绪周期理论
    ├── design/                         # 设计文档（本文件）
    └── requirements/                   # 需求文档
```

---

## 2. Agent 清单

### 2.1 分析团队（4 个 Agent，并行执行）

#### 情绪分析师 (emotion-analyst)

| 属性 | 值 |
|------|------|
| 职责 | 判断当前市场所处的情绪周期阶段 |
| 输入数据 | market-emotion/daily + market-emotion/history (20天) |
| 输出 | 情绪周期阶段判定 + 转换信号识别 + 操作建议 |
| Skill 模式 | Tool Wrapper（情绪周期理论作为 references） |
| 关键判据 | 六阶段模型 + 量化指标阈值（见理论文档） |

**核心输出结构**：
```markdown
## 情绪周期分析报告

### 当前阶段判定
- 阶段: [冰点/启动/发酵/主升/分歧/退潮]
- 置信度: [高/中/低]
- 依据: [具体量化指标]

### 关键指标快照
| 指标 | 当前值 | 阈值参考 | 信号 |
|------|--------|---------|------|
| 涨停家数 | ... | <40=低迷, >60=修复 | ... |
| 跌停家数 | ... | >10=退潮 | ... |
| 封板率 | ... | >65%=修复 | ... |
| 炸板率 | ... | >30%=退潮, >50%=变盘 | ... |
| 晋级率(2→3) | ... | 100%=启动确认 | ... |
| 最高板 | ... | 压制4-5板=冰点 | ... |
| 成交量(亿) | ... | <20000=收缩 | ... |

### 趋势判断
- 3日趋势: [改善/持平/恶化]
- 关键变化: ...

### 转换信号
- 是否出现阶段转换信号: [是/否]
- 信号描述: ...

### 操作建议
- 仓位指导: [空仓/轻仓试错/正常仓位/重仓]
```

---

#### 题材分析师 (theme-analyst)

| 属性 | 值 |
|------|------|
| 职责 | 识别主流题材、判断题材阶段、排序题材优先级 |
| 输入数据 | theme-pool/daily + theme-emotion/daily + theme-emotion/history (5天) |
| 输出 | 主流题材清单 + 各题材周期阶段 + 核心成分股 |
| Skill 模式 | Tool Wrapper |
| 关键判据 | 题材得分、题材周期阶段、龙头连续性 |

**核心输出结构**：
```markdown
## 题材分析报告

### 主流题材排名（Top 5）
| 排名 | 题材 | 得分 | 阶段 | 龙头 | 涨停数 | 热度趋势 |
|------|------|------|------|------|--------|---------|
| 1 | ... | ... | ... | ... | ... | ... |

### 各题材详细分析
#### 题材 1: [名称]
- 周期阶段: [start/ferment/main_rise/climax/bad_divergence]
- 龙头股: [名称列表]
- 龙头最高板: X
- 龙头连续性得分: X
- 3日涨停变化: +X
- 核心成分股: [列表]
- 评估: ...

### 新兴题材（可能在酝酿的方向）
...

### 退潮题材（应回避）
...
```

---

#### 趋势分析师 (trend-analyst)

| 属性 | 值 |
|------|------|
| 职责 | 从趋势池中识别核心交易标的，评估个股强度 |
| 输入数据 | trend-pool/daily + theme-pool/daily/{theme}/stocks |
| 输出 | 核心标的池 + 个股评级 |
| Skill 模式 | Tool Wrapper |
| 关键判据 | 趋势得分、星级、情绪等级、是否在主流题材中 |

**核心输出结构**：
```markdown
## 趋势分析报告

### 核心标的池
| 代码 | 名称 | 星级 | 趋势得分 | 情绪等级 | 交易信号 | 所属题材 |
|------|------|------|---------|---------|---------|---------|
| ... | ... | ... | ... | ... | ... | ... |

### 题材-个股交叉分析
- 同时出现在趋势池和主流题材中的个股: [重点关注]
- 仅在趋势池中的个股: [待观察]

### 关注度排名（前 10）
...
```

---

#### 催化剂分析师 (catalyst-analyst)

| 属性 | 值 |
|------|------|
| 职责 | 对 Top N 题材进行深度研究，挖掘真实驱动力、识别最符合题材方向的核心个股 |
| 输入数据 | ashare API（题材池 + 成分股）+ `omp web-operator`（Google/淘股吧/雪球） |
| 输出 | 每个题材的深度研究报告（驱动力 + 核心个股 + 市场叙事） |
| Skill 模式 | Pipeline（10 轮迭代研究，结构化模板强制填写） |
| 依赖 | 需要 Chrome 浏览器运行 |

**与其他分析师的分工**：
- **题材分析师**回答"哪些题材最强"（量化排名）
- **催化剂分析师**回答"这些题材为什么强、能持续多久、买谁"（定性深挖）
- 两者并行执行，催化剂分析师独立从 ashare API 获取 Top N 题材列表

**工作流程**：

```
步骤 1: 获取题材列表和成分股
  ├─ 调用 GET /theme-pool/daily 获取 Top 5 题材
  └─ 对每个题材调用 GET /theme-pool/daily/{theme}/stocks 获取成分股池

步骤 2: 对每个题材进行 10 轮迭代研究
  ├─ 每轮使用 Google / 淘股吧 / 雪球 三个渠道搜索
  ├─ 选取 2-3 篇高价值内容深度阅读
  ├─ 提炼发现、识别空白、调整下一轮搜索方向
  └─ 10 轮完成后输出该题材的研究结论

步骤 3: 汇总所有题材研究，输出最终报告
```

**脚本路径**：

| 渠道 | 搜索脚本 | 阅读脚本 |
|------|---------|---------|
| Google | `omp web-operator search google "<query>" [limit]` | `omp web-operator read-url "<url>"` |
| 淘股吧 | `omp web-operator search taoguba "<query>" [limit]` | `omp web-operator open-post taoguba "<url>"` |
| 雪球 | `omp web-operator search xueqiu "<query>" [limit]` | `omp web-operator open-post xueqiu "<url>"` |

**10 轮研究模板**（每个题材）：

> 模板采用 ADK Inversion 模式的结构化约束——Agent 必须逐轮填写，不得跳轮，不得在 Round 10 完成前输出结论。

```markdown
---
### Round 1 / 10 — [题材名称]
**Google 搜索词**: ___
**淘股吧搜索词**: ___
**雪球搜索词**: ___
**阅读的内容**: (列出 URL)
**关键发现**:
  - 催化剂/驱动力: ___
  - 政策/事件: ___
  - 核心个股线索: ___
**信息空白**: ___
**下一轮搜索方向**: ___

### Round 2 / 10 — [题材名称]
...（同上结构，共 10 轮）

### Round 10 / 10 — [题材名称]
...
---
```

**核心输出结构**：

```markdown
## 催化剂深度研究报告

### 题材 1: [名称]

#### 驱动力分析
- 核心催化剂: [政策/事件/技术突破/资金面]
- 催化剂时效: [刚发生/持续中/已充分消化]
- 持续性判断: [一日游/短期(3-5天)/中期(1-2周)/长期]
- 判断依据: ...

#### 市场叙事
- 主流叙事: [市场参与者如何理解这个题材]
- 分歧点: [看多方和看空方的核心分歧]
- 叙事演变: [从首日到现在，叙事如何变化]

#### 核心个股识别
| 代码 | 名称 | 题材角色 | 连板数 | 契合度 | 推荐理由 |
|------|------|---------|--------|--------|---------|
| ... | ... | leader | 3 | 高 | 业务最纯正，主营XX占比Y% |

- **契合度评判标准**: 个股主营业务与题材驱动力的匹配程度
  - 高: 主营业务直接受益于催化剂
  - 中: 部分业务相关或间接受益
  - 低: 蹭概念，实际业务关联弱

#### 大V/机构观点
| 来源 | 作者 | 核心观点 | 看多/看空 |
|------|------|---------|----------|

#### 风险因素
1. ...

### 题材 2: [名称]
...（同上结构）

### 跨题材发现
- 多个题材共振的个股: [值得重点关注]
- 题材间的传导关系: [如 A 退潮资金可能流向 B]
- 市场整体叙事倾向: [偏科技/偏周期/偏防御]

### 研究局限
- 未能覆盖的信息: ...
- 需要后续跟踪的线索: ...
```

**运行时间预估**：
- 每个题材 10 轮研究，每轮约 2-3 次搜索 + 2-3 次页面阅读
- 预计单题材耗时 10-15 分钟
- Top 5 题材串行研究总计约 50-75 分钟
- 这是整个 Pipeline 中最耗时的环节，但可以与其他 3 个分析师并行

**降级策略**：
- 如 Chrome 不可用：跳过催化剂分析师，辩论团队仅基于量化数据工作
- 如某个搜索渠道不可用：用剩余渠道继续研究，在报告中注明
- 如时间紧迫：可通过参数将轮次从 10 降至 5（快速模式）

---

### 2.2 辩论团队（2 辩手 + 2 裁判，两轮辩论）

#### 第一轮：市场环境辩论

**看多辩手 (bull-debater)**

| 属性 | 值 |
|------|------|
| 职责 | 从分析报告中提炼所有看多论据，构建看多逻辑链 |
| 输入 | 4 份分析报告 |
| 输出 | 看多论述（结构化） |
| 设计模式 | Reviewer（评审分析报告中的积极因素） |

**看空辩手 (bear-debater)**

| 属性 | 值 |
|------|------|
| 职责 | 从分析报告中提炼所有看空论据和风险因素 |
| 输入 | 4 份分析报告 + 看多辩手论述 |
| 输出 | 看空论述（结构化，需回应看多方论点） |
| 设计模式 | Reviewer（评审分析报告中的风险因素） |

**市场裁判 (market-judge)**

| 属性 | 值 |
|------|------|
| 职责 | 评估多空双方论据，判定市场环境和操作基调 |
| 输入 | 4 份分析报告 + 多空论述 |
| 输出 | 市场环境判定 + 操作基调 + 仓位指导 |

**市场辩论输出结构**：
```markdown
## 市场环境辩论总结

### 多方核心论据
1. ...
2. ...

### 空方核心论据
1. ...
2. ...

### 裁判判定
- 市场环境: [强势/震荡/弱势]
- 情绪周期: [具体阶段]
- 操作基调: [积极进攻/谨慎参与/防守观望/空仓等待]
- 建议仓位: [0%/30%/50%/80%]
- 判定理由: ...
```

#### 第二轮：题材机会辩论

对第一轮裁判认可的 Top N 题材（默认 Top 3），逐一进行多空辩论。

**复用看多/看空辩手**，但切换上下文为具体题材。

**题材裁判 (theme-judge)**

| 属性 | 值 |
|------|------|
| 职责 | 评估各题材的多空论据，排序题材优先级，确定核心标的 |
| 输入 | 市场辩论结果 + 各题材多空论述 + 分析报告 |
| 输出 | 题材优先级排序 + 每个题材的核心标的 + 风险提示 |

**题材辩论输出结构**：
```markdown
## 题材机会辩论总结

### 题材 1: [名称]
- 多方论据: ...
- 空方论据: ...
- 裁判判定: [强烈看好/适度看好/中性/回避]
- 核心标的: [代码 名称]
- 风险提示: ...

### 题材 2: [名称]
...

### 最终题材优先级
1. [题材名] — [判定] — [核心标的]
2. ...
3. ...
```

---

### 2.3 决策团队（1 个 Agent）

#### 投资经理 (investment-manager)

| 属性 | 值 |
|------|------|
| 职责 | 综合所有分析和辩论结果，生成最终盘后分析报告 |
| 输入 | 全部分析报告 + 两轮辩论结果 + 历史记忆 |
| 输出 | 最终盘后分析报告（结构化 Markdown） |
| Skill 模式 | Generator（基于模板生成报告） |
| 特殊能力 | 读取历史记忆，反思过往决策 |

**最终报告结构**：
```markdown
# 盘后分析报告 — {YYYY-MM-DD}

## 一、市场概况
- 情绪周期阶段: [X]
- 市场环境: [X]
- 操作基调: [X]

## 二、核心数据
| 指标 | 值 | 信号 |
|------|------|------|
| 涨停家数 | ... | ... |
| 跌停家数 | ... | ... |
| 封板率 | ... | ... |
| 炸板率 | ... | ... |
| 晋级率 | ... | ... |
| 成交量 | ... | ... |
| 最高板 | ... | ... |

## 三、主流题材
| 优先级 | 题材 | 阶段 | 核心标的 | 判定 |
|--------|------|------|---------|------|
| 1 | ... | ... | ... | ... |

## 四、核心标的池
| 代码 | 名称 | 所属题材 | 星级 | 交易信号 | 关注理由 |
|------|------|---------|------|---------|---------|

## 五、风险提示
1. ...

## 六、操作计划
- 仓位: [X%]
- 方向: [题材名称]
- 标的: [具体股票]
- 策略: [具体操作策略]

## 七、反思与学习
- 昨日判断回顾: ...
- 经验总结: ...
```

---

## 3. Pipeline 编排流程

```bash
#!/usr/bin/env bash
# run-analysis.sh — Conductor 编排脚本

TRADE_DATE="${1:-$(date +%Y-%m-%d)}"
REPORT_DIR="data/reports/$TRADE_DATE"

# ======== 阶段 1: 分析团队（并行） ========
# 4 个分析师同时执行，输出各自报告

pi --print --agent agents/analysts/emotion-analyst.md \
   "$TRADE_DATE" > "$REPORT_DIR/01-emotion-report.md" &

pi --print --agent agents/analysts/theme-analyst.md \
   "$TRADE_DATE" > "$REPORT_DIR/02-theme-report.md" &

pi --print --agent agents/analysts/trend-analyst.md \
   "$TRADE_DATE" > "$REPORT_DIR/03-trend-report.md" &

pi --print --agent agents/analysts/catalyst-analyst.md \
   "$TRADE_DATE" > "$REPORT_DIR/04-catalyst-report.md" &

wait  # 等待所有分析师完成

# ======== 阶段 2: 市场环境辩论（顺序） ========
# 看多 → 看空 → 裁判

REPORTS=$(cat "$REPORT_DIR"/0{1,2,3,4}-*-report.md)

pi --print --agent agents/debaters/bull-debater.md \
   "分析报告: $REPORTS" > "$REPORT_DIR/05a-bull-argument.md"

pi --print --agent agents/debaters/bear-debater.md \
   "分析报告: $REPORTS
    看多论述: $(cat $REPORT_DIR/05a-bull-argument.md)" \
   > "$REPORT_DIR/05b-bear-argument.md"

pi --print --agent agents/judges/market-judge.md \
   "分析报告: $REPORTS
    看多论述: $(cat $REPORT_DIR/05a-bull-argument.md)
    看空论述: $(cat $REPORT_DIR/05b-bear-argument.md)" \
   > "$REPORT_DIR/05-market-debate.md"

# ======== 阶段 3: 题材辩论（按题材顺序） ========
# 从市场裁判结果中提取 Top 3 题材，逐一辩论
# （具体实现需解析裁判输出，此处为伪代码）

for theme in $(extract_top_themes "$REPORT_DIR/05-market-debate.md"); do
  pi --print --agent agents/debaters/bull-debater.md \
     "题材辩论模式 题材:$theme 分析报告:$REPORTS" \
     > "$REPORT_DIR/06a-bull-$theme.md"

  pi --print --agent agents/debaters/bear-debater.md \
     "题材辩论模式 题材:$theme 分析报告:$REPORTS
      看多论述: $(cat $REPORT_DIR/06a-bull-$theme.md)" \
     > "$REPORT_DIR/06b-bear-$theme.md"
done

pi --print --agent agents/judges/theme-judge.md \
   "市场辩论结果: $(cat $REPORT_DIR/05-market-debate.md)
    题材辩论: $(cat $REPORT_DIR/06*)" \
   > "$REPORT_DIR/06-theme-debate.md"

# ======== 阶段 4: 最终决策 ========

pi --print --agent agents/decision/investment-manager.md \
   "所有分析报告: $REPORTS
    市场辩论: $(cat $REPORT_DIR/05-market-debate.md)
    题材辩论: $(cat $REPORT_DIR/06-theme-debate.md)
    历史记忆: $(tail -20 data/memory/lessons.jsonl)" \
   > "$REPORT_DIR/07-final-report.md"

echo "分析完成: $REPORT_DIR/07-final-report.md"
```

---

## 4. 记忆/学习机制

### 4.1 记忆存储

```
data/memory/
├── lessons.jsonl          # 经验教训（每行一条 JSON）
└── performance.jsonl      # 决策-结果对照
```

**lessons.jsonl 格式**：
```json
{
  "date": "2026-03-21",
  "stage": "expanding",
  "lesson": "发酵期第二天激进追高导致亏损，应等主升确认再加仓",
  "category": "timing",
  "source": "reflector"
}
```

**performance.jsonl 格式**：
```json
{
  "decision_date": "2026-03-20",
  "theme": "低空经济",
  "action": "买入",
  "stocks": ["中信海直", "三房巷"],
  "stage_at_decision": "ferment",
  "result_date": "2026-03-21",
  "result": "+3.2%",
  "stage_at_result": "main_rise"
}
```

### 4.2 学习流程

记忆的写入和使用分两个时机：

1. **决策时读取**：投资经理读取最近 20 条 lessons，避免重复犯错
2. **复盘时写入**：手动触发复盘脚本，对比前日决策与实际结果，生成新 lesson

> 复盘脚本暂不在 MVP 范围内，MVP 阶段支持手动追加 lesson。

---

## 5. Skills 设计

### 5.1 ashare-data Skill

每个脚本是一个简单的 curl wrapper，接收参数、调用 API、返回格式化结果。

**示例 — fetch-market-emotion.sh**：
```bash
#!/usr/bin/env bash
# 用法: fetch-market-emotion.sh <trade_date>
TRADE_DATE="${1:?用法: fetch-market-emotion.sh YYYY-MM-DD}"
BASE_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

curl -sf "$BASE_URL/market-emotion/daily/$TRADE_DATE" | jq .
```

**示例 — fetch-theme-emotion.sh**：
```bash
#!/usr/bin/env bash
# 用法: fetch-theme-emotion.sh <trade_date> [limit] [sort]
TRADE_DATE="${1:?用法: fetch-theme-emotion.sh YYYY-MM-DD [limit] [sort]}"
LIMIT="${2:-50}"
SORT="${3:-theme_rank}"
BASE_URL="${ASHARE_API_URL:-http://127.0.0.1:8000}"

curl -sf "$BASE_URL/theme-emotion/daily?trade_date=$TRADE_DATE&limit=$LIMIT&sort=$SORT" | jq .
```

### 5.2 web-operator Skill（复用）

催化剂分析师复用现有的 `~/.agents/skills/web-operator/` skill，通过 `omp web-operator` 调用站点工作流：

| 渠道 | 脚本 | 用途 |
|------|------|------|
| Google | `google/search.sh <query>` | 搜索题材相关新闻、政策、事件 |
| 淘股吧 | `taoguba/search.sh <query>` | 搜索题材相关讨论 |
| 淘股吧 | `taoguba/open-post.sh <url>` | 阅读帖子全文 |
| 雪球 | `xueqiu/search.sh <query>` | 搜索题材相关分析 |
| 雪球 | `xueqiu/open-post.sh <url>` | 阅读帖子全文 |

---

## 6. 技术约束

| 约束 | 值 |
|------|------|
| LLM 模型 | kimi-k2-thinking |
| Agent 框架 | Pi（.md 格式 agent 定义）|
| 编排方式 | Shell 脚本 (Conductor) |
| 数据接口 | ashare-platform HTTP API (localhost:8000) |
| 深度研究 | web-operator Skill / `omp web-operator` (需浏览器调试环境，催化剂分析师使用) |
| 运行环境 | 当前主机本地执行 |
| 运行频率 | 手动触发（shell 脚本） |

---

## 7. MVP 范围

### MVP 包含
- [ ] 4 个分析师 Agent（情绪/题材/趋势/催化剂）
- [ ] 2 个辩手 Agent（看多/看空，市场+题材两轮复用）
- [ ] 2 个裁判 Agent（市场/题材）
- [ ] 1 个投资经理 Agent
- [ ] ashare-data Skill（9 个数据采集脚本）
- [ ] web-operator Skill 复用（催化剂分析师的搜索/阅读能力）
- [ ] Conductor 编排脚本
- [ ] 最终报告输出

### MVP 不包含（后续迭代）
- 自动复盘与学习（需要次日数据回填）
- 盘前/盘中简化版分析
- 自动化定时执行
- Web UI 展示
- 回测系统
- K 线技术形态分析（依赖 B3 接口）
