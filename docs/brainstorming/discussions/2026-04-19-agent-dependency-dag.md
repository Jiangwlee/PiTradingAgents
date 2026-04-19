# Agent Dependency DAG

- Date: 2026-04-19
- Project: PiTradingAgents
- Purpose: 理清各 Agent 产出物之间的依赖关系，明确 source-of-truth、只读引用、允许 fallback 的边界；后续所有 prompt 修改应优先对齐本 DAG

---

## 一、总原则

### 1. 先 DAG，后 Prompt
后续修改任何 Agent prompt，必须先回答：
- 它的上游是谁
- 它能读哪些文件
- 哪些字段只能只读引用
- 哪些字段允许 fallback
- 它输出给谁消费

### 2. 每个关键字段只有一个 source-of-truth
禁止多 Agent 各自定义同一字段的不同版本。

### 3. 下游只允许三种动作
对于上游产出，下游只允许：
- **read-only 引用**
- **基于该结论做综合判断**
- **缺失时按同口径 fallback 补判**（仅少数节点允许）

禁止：
- 平行重算
- 任意推翻
- 用另一套规则覆盖上游字段

### 4. Prompt 必须显式声明前置依赖
后续每个关键 Agent prompt 中，都应写清：
- 前置依赖文件
- 只读字段
- fallback 允许范围
- 禁止重算的字段

---

## 二、文件级 DAG

```text
基础分析层（并行）
  emotion-analyst   ──> 01-emotion-report.md
  theme-analyst     ──> 02-theme-report.md
  trend-analyst     ──> 03-trend-report.md
  catalyst-analyst  ──> 04-catalyst-report.md

市场辩论层
  01 + 02 + 03 + 04
    ├──> bull-debater   ──> bull 论述
    └──> bear-debater   ──> bear 论述

  01 + 02 + 03 + 04 + bull + bear
    └──> market-judge   ──> 05-market-debate.md

题材辩论层
  01 + 02 + 03 + 04 + 05(TOP_THEMES)
    ├──> bull-debater(theme mode)
    └──> bear-debater(theme mode)

  01 + 02 + 03 + 04 + 05 + theme bull + theme bear
    └──> theme-judge    ──> 06-theme-debate.md

个股研究层
  01 + 02 + 03 + 04 + 06 + 候选池/MA5数据
    └──> stock-researcher-pipeline ──> 08-stock-research.md

最终决策层
  01 + 02 + 03 + 04 + 05 + 06 + 08
    └──> investment-manager ──> 07-final-report.md + picks.json
```

---

## 三、字段级 DAG（source-of-truth）

### A. 市场风险字段 DAG

```text
emotion-analyst
  ├── EMOTION_RISK
  ├── NEXT_STAGE
  └── POSITION_CAP

EMOTION_RISK / NEXT_STAGE / POSITION_CAP
  ├──> bull-debater
  ├──> bear-debater
  ├──> market-judge
  ├──> stock-researcher-pipeline
  └──> investment-manager
```

#### 规则
- **source-of-truth**：`emotion-analyst`
- 下游只能引用和应用，**不得重算**
- `market-judge` 可据此施加硬约束，但不得改写字段含义

---

### B. 题材入口字段 DAG

```text
market-judge
  └── TOP_THEMES

TOP_THEMES
  ├──> 题材辩论范围
  ├──> theme-judge 聚焦范围
  └──> 下游题材优先级输入范围
```

#### 规则
- **source-of-truth**：`market-judge`
- 下游不应再自创另一套“最终 Top 题材列表”作为正式入口
- 允许在最终报告中做排序压缩表达，但不能绕开 `TOP_THEMES` 另起题材池

---

### C. 入场风险字段 DAG

```text
trend-analyst
  ├── entry_risk
  └── ma5_deviation

entry_risk
  ├──> theme-judge                [read-only]
  ├──> stock-researcher-pipeline  [reuse-first; fallback only if missing]
  └──> investment-manager         [read-only]
```

#### 规则
- **source-of-truth**：`trend-analyst`
- `theme-judge`：只读引用，不重判
- `stock-researcher-pipeline`：优先复用；仅在未覆盖股票时，允许按**同口径规则**补判
- `investment-manager`：只消费，不重算
- 禁止下游 Agent 推翻趋势分析师已给出的 `entry_risk`

---

### D. 纵横分析字段 DAG

```text
catalyst-analyst
  ├── 纵轴
  ├── 横轴
  └── 交点

纵横分析结论
  ├──> theme-judge                [hard consume]
  ├──> stock-researcher-pipeline  [partial consume]
  └──> investment-manager         [hard consume]
```

#### 规则
- **source-of-truth**：`catalyst-analyst`
- `theme-judge`：强制消费
- `investment-manager`：强制消费，且最终报告必须显性体现其关键结论
- `stock-researcher-pipeline`：部分消费，优先消费**纵轴结论**（如历次兑现、本轮 vs 上轮）
- 不要求所有下游机械复述“纵轴/横轴/交点”标题，但必须消费其判断内核

---

### E. 个股研究字段 DAG

```text
stock-researcher-pipeline
  ├── researcher_rating
  ├── weighted_score
  ├── dimensions
  ├── core_logic
  └── entry_risk (reuse/fallback after trend source)

这些字段
  └──> investment-manager
```

#### 规则
- **source-of-truth**：`stock-researcher-pipeline`（针对研究员五维度结论）
- `investment-manager` 应优先使用其结构化研究结论
- `investment-manager` 不应重新发明一套五维度评分体系
- 若研究员已给出“暂不关注”，投资经理原则上不得推荐

---

### F. 最终荐股字段 DAG

```text
investment-manager
  └── picks.json

picks.json
  ├──> save-state.py
  ├──> calc-signals.py
  ├──> update-signals.py
  └──> 后续 review / reflect / 自进化闭环
```

#### 规则
- **source-of-truth**：`investment-manager`
- `picks.json` 是最终荐股结构化输出的唯一正式来源
- Markdown 提取仅为 fallback，不应作为长期主路径

---

## 四、各 Agent 的 allowed inputs / allowed actions

## 1. emotion-analyst
- **输入**：市场情绪原始数据、历史情绪数据
- **输出**：`EMOTION_RISK` / `NEXT_STAGE` / `POSITION_CAP`
- **禁止**：引用下游辩论结果反向修正自身结论

## 2. theme-analyst
- **输入**：题材池、题材情绪、历史情绪、成分股数据
- **输出**：Top 题材初筛、题材阶段初判
- **禁止**：冒充 `catalyst-analyst` 输出完整纵横分析结论

## 3. trend-analyst
- **输入**：trend-pool enriched 数据、题材交叉数据
- **输出**：`entry_risk` / `ma5_deviation` / 核心标的池
- **禁止**：依赖下游研究员或投资经理反向修正风险标签

## 4. catalyst-analyst
- **输入**：Top 题材、成分股、web research 结果
- **输出**：题材驱动力 + `纵轴/横轴/交点`
- **禁止**：输出无法追溯来源的历史脉冲或机构观点

## 5. bull-debater / bear-debater
- **输入**：01/02/03/04；题材模式下还读取 `TOP_THEMES` 上下文
- **输出**：多空论述
- **允许**：引用上游字段做论证
- **禁止**：重定义 `EMOTION_RISK` / `entry_risk`

## 6. market-judge
- **输入**：01/02/03/04 + bull/bear
- **输出**：05-market-debate.md + `TOP_THEMES`
- **允许**：基于 `EMOTION_RISK` 施加操作基调和仓位上限
- **禁止**：重算 `EMOTION_RISK` / `NEXT_STAGE`

## 7. theme-judge
- **输入**：01/02/03/04/05 + 题材多空论述
- **必须引用**：
  - `03` 的 `entry_risk`
  - `04` 的纵轴/横轴/交点
  - `05` 的市场环境基调
- **输出**：06-theme-debate.md
- **禁止**：自创 `entry_risk`、跳过纵横分析结论

## 8. stock-researcher-pipeline
- **输入**：01/02/03/04/06 + 候选池 + MA5 数据
- **必须引用**：
  - `03` 的 `entry_risk`（优先）
  - `04` 的纵轴结论（强制）
  - `06` 的题材裁判结论
- **允许 fallback**：仅当 `03` 未覆盖股票时，按同口径补判 `entry_risk`
- **输出**：08-stock-research.md
- **禁止**：推翻趋势分析师已给出的 `entry_risk`

## 9. investment-manager
- **输入**：01/02/03/04/05/06/08
- **必须引用**：
  - `04` 纵横分析关键结论
  - `06` 题材裁判结果与参与建议
  - `08` 研究员结构化结论
  - `03` 的 `entry_risk`
- **输出**：07-final-report.md + `picks.json`
- **禁止**：
  - 重算 `entry_risk`
  - 推翻研究员评级
  - 另起一套仓位体系

---

## 五、fallback 规则总表

| 字段/结论 | source-of-truth | 谁可 fallback | fallback 条件 | fallback 要求 |
|---|---|---|---|---|
| `EMOTION_RISK` / `NEXT_STAGE` / `POSITION_CAP` | `emotion-analyst` | 无 | 不允许 | 下游只读 |
| `TOP_THEMES` | `market-judge` | 无 | 不允许 | 下游按其聚焦题材 |
| `entry_risk` | `trend-analyst` | `stock-researcher-pipeline` | 趋势分析师未覆盖该股票 | 必须注明“按趋势分析师同口径规则补判” |
| 纵轴/横轴/交点 | `catalyst-analyst` | 无正式 fallback | 若缺失则下游只能注明“催化剂报告未提供充分纵横信息” | 不得脑补完整纵横结论 |
| 研究员五维度结论 | `stock-researcher-pipeline` | `investment-manager` 可降级到不用研究员文件 | 仅当 08 缺失 | 必须明确说明是 fallback 路径 |
| 最终荐股结构化输出 | `investment-manager` (`picks.json`) | Markdown 提取脚本 | 仅当 `picks.json` 缺失 | 仅作为兼容 fallback |

---

## 六、后续 prompt 修改的检查清单

后续每修改一个 Agent prompt，都先检查：

- [ ] 它依赖的上游文件是否写清楚了
- [ ] 它引用的关键字段是否已有 source-of-truth
- [ ] 它是否错误地重算了上游字段
- [ ] 它是否需要 fallback；如果需要，条件是否写清楚
- [ ] 它的输出是否会被下游继续消费；若会，结构是否稳定

---

## 七、当前最受本 DAG 约束的 prompt

后续修改时应优先对齐本 DAG 的文件：

- `agents/analysts/trend-analyst.md`
- `agents/analysts/catalyst-analyst.md`
- `agents/judges/theme-judge.md`
- `agents/researchers/stock-researcher-pipeline.md`
- `agents/decision/investment-manager.md`

---

## 八、一句话总纲

> 先理清 DAG，再改 Agent prompt；先确定 source-of-truth，再讨论谁能引用、谁能 fallback、谁绝不能重算。
