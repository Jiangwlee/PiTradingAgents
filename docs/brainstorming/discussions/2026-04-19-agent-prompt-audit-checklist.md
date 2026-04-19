# Agent Prompt Audit Checklist

- Date: 2026-04-19
- Scope: `agents/` 中与纵横分析法接入、题材/趋势/辩论/裁判/研究/决策链路相关的 prompt 审查
- Goal: 先把问题落盘，后续逐项讨论和修复

## 本轮审查结论

### A. 纵横分析法接入结论
- [x] **主接入位置正确**：已接入 `agents/analysts/catalyst-analyst.md`
- [x] **A股化改造合理**：已转化为“历次炒作轨迹 / 同期题材生态位 / 纵横交汇判断”
- [x] **fallback 设计合理**：支持本题材 → 同层近义 → 上位概念
- [ ] **尚未形成全链路硬约束**：下游 agent 还没有全部强制消费“纵轴 / 横轴 / 交点”结论

### B. Prompt 整体质量结论
- [x] 整体结构化程度较高，角色边界基本清晰
- [ ] 存在多处术语不一致、规则不一致、旧模板残留问题
- [ ] 部分 prompt 已升级到“风险约束新体系”，部分仍停留在旧体系

---

## 已确认决议（2026-04-19）

### A. 统一术语字典（已确认）

#### 1) 市场级情绪阶段
- 冰点
- 启动
- 发酵
- 主升
- 分歧
- 退潮

#### 2) 题材级阶段
- 启动
- 发酵
- 主升
- 高潮
- 分歧
- 退潮

#### 3) 操作基调（统一为 5 档）
- 积极进攻
- 适度参与
- 谨慎观望
- 防守待机
- 空仓等待

#### 4) 仓位档位
- 0%
- 20%
- 40%
- 60%
- 80%
- 100%

#### 5) 废弃/替换词
- `谨慎参与` → 统一替换为 `适度参与` 或 `谨慎观望`（按语义择一）
- `防守观望` → 统一替换为 `防守待机`

#### 6) 适用原则
- 市场级阶段与题材级阶段不得混用
- 所有 agent 的模板、说明文字、枚举值、示例输出都应使用上述统一术语
- 下游结构化字段（如 `picks.json` / 标记行 / 裁判结果）必须使用统一后的标准枚举

### B. 统一术语字典后的待修文件
- [ ] `agents/judges/theme-judge.md`：替换 `谨慎参与`、`防守观望`
- [ ] `agents/decision/investment-manager.md`：统一仓位档位为 `0/20/40/60/80/100`
- [ ] 全量扫描 `agents/`、`bin/`、文档模板中是否还有旧词残留

### C. 入场风险唯一规则源（已确认）

#### 1) 规则源头
- **唯一规则源**：`agents/analysts/trend-analyst.md`
- `entry_risk` / `ma5_deviation` 的标准定义与首次判定，以趋势分析师输出为准

#### 2) 下游消费规则
- `agents/judges/theme-judge.md`：**只引用，不重判**
- `agents/researchers/stock-researcher-pipeline.md`：**优先引用**；若股票不在趋势分析师覆盖范围内，允许按**同口径规则补判**
- `agents/decision/investment-manager.md`：**只消费，不重算**；负责把结果写入 `picks.json`

#### 3) 禁止事项
- 不允许不同 agent 各自定义不同版本的入场风险分级逻辑
- 不允许下游 agent 任意推翻趋势分析师已给出的风险标签
- 不允许 `investment-manager` 在最终报告中另起一套“高/中/低风险”定义替代 `entry_risk`

#### 4) 补判原则
- 仅在趋势分析师未覆盖某股票时允许补判
- 补判必须显式说明：`按趋势分析师同口径规则补判`
- 补判结果只用于覆盖缺失，不用于推翻已有标签

#### 5) 小型 DAG（已确认采用）

```text
trend-analyst
  output: entry_risk, ma5_deviation

entry_risk
  ├──> theme-judge                [read-only]
  ├──> stock-researcher-pipeline  [reuse-first; fallback only if missing]
  └──> investment-manager         [read-only; serialize to picks.json]
```

#### 6) 受影响文件
- [ ] `agents/analysts/trend-analyst.md`：明确其为唯一规则源，并补充规则优先级/覆盖说明
- [ ] `agents/judges/theme-judge.md`：改成只引用趋势分析师的 `entry_risk`
- [ ] `agents/researchers/stock-researcher-pipeline.md`：改成“优先复用，缺失时同口径补判”
- [ ] `agents/decision/investment-manager.md`：改成只消费 `entry_risk`，不重算
- [ ] 如有必要，补一个共享说明文档，写清楚 `entry_risk` 的 DAG 依赖关系

---

## P0：最高优先级（先讨论）

### 1. 统一“纵横分析法”的下游消费规则
- [x] `theme-judge.md` 应**显式要求**引用 `04-catalyst-report.md` 中的：
  - 纵轴
  - 横轴
  - 交点
- [x] `investment-manager.md` 应**显式要求**在 Top 题材详细分析中引用：
  - 本轮 vs 上轮强弱差异
  - 当前生态位
  - 三剧本推演
- [x] “纵横分析法”正式定义为：
  - `catalyst-analyst` 的强制输出结构
  - `theme-judge` / `stock-researcher-pipeline` / `investment-manager` 的分层消费结构
- [x] 采用分层约束：
  - **硬约束**：`catalyst-analyst`、`theme-judge`、`investment-manager`
  - **半硬约束**：`stock-researcher-pipeline`
  - **非硬约束**：其余 agent
- [x] 最终报告必须**显性体现纵横分析法结论**，但应使用交易决策语言自然表达，而非机械复述“纵轴/横轴/交点”标题
- [ ] 评估 `investment-manager.md` 的 final report template 是否需要调整，以承载：
  - 历史位置
  - 当前生态位
  - 交汇后的交易判断

### 2. 统一全系统术语字典
- [x] 统一“操作基调”枚举值
- [x] 统一“仓位档位”枚举值
- [x] 统一“题材阶段”中文六阶段写法
- [x] 统一“情绪阶段（市场级）”与“题材阶段（题材级）”的边界说明
- [x] 统一“防守观望 / 防守待机 / 谨慎参与 / 适度参与”等近义词

### 3. 统一“入场风险”规则来源
- [x] 确定全系统唯一权威来源：以 `trend-analyst.md` 为准
- [x] 明确 `stock-researcher-pipeline.md`：优先复用，缺失时同口径补判
- [x] 明确不允许研究员/下游 agent 任意推翻趋势分析师标签

---

## P1：明确发现的矛盾 / 不一致

### 4. `theme-judge.md` 与 `market-judge.md` 的操作基调不一致
- [ ] `market-judge.md` 使用：
  - 积极进攻
  - 适度参与
  - 谨慎观望
  - 防守待机
  - 空仓等待
- [ ] `theme-judge.md` 使用：
  - 积极进攻
  - 谨慎参与
  - 防守观望
- [ ] 决定统一成哪一套

### 5. `theme-judge.md` 中存在命名冲突
- [ ] 注意事项里写的是“防守观望”
- [ ] 但上游 `market-judge.md` 使用的是“防守待机”
- [ ] 修正为一致术语

### 6. `investment-manager.md` 的仓位模板与上游不一致
- [ ] 上游：`0 / 20 / 40 / 60 / 80 / 100`
- [ ] 投资经理模板：`0 / 30 / 50 / 80`
- [ ] 决定是否统一使用上游硬约束档位

### 7. `trend-analyst.md` 与数据字段可能不一致
- [ ] prompt 里引用了 `is_uptrend = true`
- [ ] 但当前列出的 enriched 字段里未明确包含 `is_uptrend`
- [ ] 需要确认：
  - API 是否真的返回该字段
  - 若无，prompt 应如何改写

### 8. `stock-researcher-pipeline.md` 可能存在历史字段残留
- [ ] 检查 `period_gain_pct` 是否真实存在于输入数据
- [ ] 检查 `source=new_high` 是否应改为 `sources` 或其他字段
- [ ] 确认候选池真实 schema 与 prompt 是否完全一致

---

## P2：逐个 agent 的专项检查项

### 9. `emotion-analyst.md`
- [x] 显式写清：当“当前阶段”和“次日预判”冲突时，交易判断以次日预判优先
- [x] 将风险等级 → 仓位上限映射写成更硬的规则，并与下游保持一致
- [x] 补一条“冲突信号裁决规则”，避免模型在发酵/主升/分歧边界摇摆
- [ ] 在 prompt 中明确其字段为市场风险 source-of-truth：`EMOTION_RISK` / `NEXT_STAGE` / `POSITION_CAP`

### 10. `theme-analyst.md`
- [x] 继续保持“量化初筛 agent”定位，不强接完整纵横分析法
- [x] 可补一个轻量版“历史重炒 / 新分支 / 轮动承接”字段，但不升级为深研究 agent
- [x] 增强其与 `catalyst-analyst.md` 的接口关系：明确 theme-analyst 负责初筛，catalyst-analyst 负责深挖
- [ ] 按 DAG 视角补充其 allowed inputs / outputs 描述，避免与 catalyst 角色重叠

### 11. `trend-analyst.md`
- [x] 已核实：enriched trend-pool API **确实返回** `is_uptrend`
- [x] 在字段说明表中补充 `is_uptrend`，避免 prompt 内引用但说明表缺失
- [x] 补充“风险判定优先级：🔴 > 🟡 > 🟢 覆盖”
- [x] 把“负偏离 / 大跌 / 情绪等级5”这些特殊情况写成更严格的裁决顺序
- [x] 将“高风险（次日追高大概率亏损）”改成更稳健的专业表述
- [ ] 具体改写时，明确特殊情况的覆盖顺序：先按基础规则判级，再按特殊情况上调/限制风险等级

### 12. `catalyst-analyst.md`
- [x] 保留“纵轴 / 横轴 / 交点”作为强制输出，但允许对研究轮次做适度降复杂度，避免执行负担过重
- [x] 要求在最终“纵轴 / 横轴 / 交点”结论中回指关键来源，防止过程有来源、结论无来源
- [x] 将“三剧本推演”格式进一步标准化，便于 `theme-judge` / `investment-manager` 消费
- [ ] 在 prompt 中显式声明其为纵横分析结论的 source-of-truth

### 13. `bull-debater.md`
- [x] 与 bear 对齐，明确回应“趋势分析师的入场风险评估”
- [x] 弱化“对模糊或负面信息给出合理的看多解读”这类易被滥用的表述，避免强行乐观
- [x] 增加“不得突破风险硬约束”的明确提示
- [ ] 从 DAG 视角明确：可引用上游字段论证，但不得重定义 `EMOTION_RISK` / `entry_risk`

### 14. `bear-debater.md`
- [x] 检查并承认其当前力度偏强于 `bull-debater.md`，后续应做一定平衡
- [x] 为 bull / bear 建立更对称的论证抓手，避免结构性偏空
- [x] 对“历史失败案例类比”增加约束，避免过度保守或类比滥用
- [ ] 从 DAG 视角明确：可引用上游字段论证，但不得重定义 `EMOTION_RISK` / `entry_risk`

### 15. `market-judge.md`
- [x] 将最终决策公式写得更明确：
  - 原始判定
  - 风险上限
  - 入场可行性修正
- [x] 进一步标准化“硬约束限制前 / 限制后”的写法
- [ ] 从 DAG 视角补充：`EMOTION_RISK` / `NEXT_STAGE` 为只读输入，`TOP_THEMES` 为其唯一正式输出之一

### 16. `theme-judge.md`
- [x] 强制消费纵横分析三类结论：
  - 历史位置
  - 当前生态位
  - 交汇后的交易判断
- [x] 强制引用 `catalyst-analyst.md` 的纵轴 / 横轴 / 交点结论
- [x] 强制引用趋势分析师的 `entry_risk`，且 **不自行补判**
- [x] 将“题材判定结果”和“参与建议”拆开
- [ ] 统一操作基调词汇
- [ ] 统一参与建议词汇
- [ ] 调整输出模板，使裁判判定至少包含：
  - 判定结果
  - 判定理由
  - 历史位置判断
  - 当前生态位判断
  - 交易结论
  - 优先级得分
- [ ] 明确 `题材风险` 与 `入场风险` 的分工：
  - `题材风险` = 裁判综合判断
  - `入场风险` = 趋势分析师输出，只引用不重算

### 17. `stock-researcher-pipeline.md`
- [x] 入场风险改为：**优先复用趋势分析师结果，缺失时按同口径补判**
- [x] 不得推翻趋势分析师已有的风险标签
- [x] 强制消费“纵轴结论”，不强制消费完整横轴
- [x] 后续必须清理字段名残留问题
- [ ] 将“历次兑现”字段设为强制消费纵轴结论的正式接口
- [ ] 补充：若催化剂报告无纵轴，如何降级而不胡写
- [ ] 明确“市场风险约束”与“五维度评分”的先后关系
- [ ] 技术面章节中拆分“趋势结构判断”与“入场风险来源”，避免自创第二套风控逻辑
- [ ] 检查并修正字段名一致性：
  - `period_gain_pct`
  - `source=new_high`
  - 示例 JSON 与实际输入 schema 的一致性

### 18. `investment-manager.md`
- [x] 最终报告必须显性体现纵横分析法三类结论：
  - 历史位置
  - 当前生态位
  - 交汇后的交易判断
- [x] 这些内容应嵌入现有 Top 题材详细分析，而不是单独新增“纵横分析法章节”
- [x] 投资经理只负责整合与表达：
  - 不重算 `entry_risk`
  - 不推翻研究员评级
  - 不另起一套仓位体系
- [x] final report template 需要调整，以承载纵横分析法结论
- [ ] 统一仓位档位
- [ ] 清理旧模板残留（如旧版核心标的池表述）
- [ ] 进一步明确：荐股必须优先使用 `08-stock-research.md` 的结构化结论
- [ ] 调整 Top 题材详细分析模板，使每个题材至少体现：
  - 历史位置
  - 当前生态位
  - 交易判断
- [ ] 评估“主流题材排名”表是否增加 `参与建议` 或 `当前位置` 字段
- [ ] 增强前文题材判断与“今日荐股”之间的回溯关系，避免前后矛盾

---

## P3：建议修复顺序

### 第一轮：先统一规则，不直接大改文案
- [ ] 统一术语字典（操作基调 / 仓位 / 阶段）
- [ ] 统一入场风险规则
- [ ] 统一候选池 / enriched 数据字段名

### 第二轮：再修纵横分析法链路
- [ ] 强化 `catalyst-analyst.md` 输出规范
- [ ] 强化 `theme-judge.md` 对“交点”的消费
- [ ] 强化 `investment-manager.md` 对“纵轴 / 横轴 / 交点”的消费

### 第三轮：再平衡辩论与裁判 prompt
- [ ] 平衡 bull / bear prompt 力度
- [ ] 优化 market/theme judge 的判决逻辑表达

### 第四轮：最后做模板清理
- [ ] 清理旧模板残留
- [ ] 减少重复规则
- [ ] 必要时抽出共享规则文档

---

## 建议的讨论顺序（一次只聊一个）

1. [ ] 先定：**全系统统一术语字典**
2. [ ] 再定：**入场风险唯一规则源**
3. [ ] 再定：**纵横分析法下游是否设为硬约束**
4. [ ] 再定：`theme-judge.md` 如何改
5. [ ] 再定：`investment-manager.md` 如何改
6. [ ] 再定：其余 agent 的细节修订

---

## 文件清单（本轮重点审查对象）
- `agents/analysts/emotion-analyst.md`
- `agents/analysts/theme-analyst.md`
- `agents/analysts/trend-analyst.md`
- `agents/analysts/catalyst-analyst.md`
- `agents/debaters/bull-debater.md`
- `agents/debaters/bear-debater.md`
- `agents/judges/market-judge.md`
- `agents/judges/theme-judge.md`
- `agents/researchers/stock-researcher-pipeline.md`
- `agents/decision/investment-manager.md`

## 备注
- 本文档是讨论用 checklist，不是最终修复方案。
- 后续每次只处理一个主题，确认后再改文件，避免单 session 改动过大。
