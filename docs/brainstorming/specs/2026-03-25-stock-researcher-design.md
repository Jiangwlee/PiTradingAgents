# 个股深度研究 Agent（stock-researcher）设计方案

## 目录

1. [一句话摘要](#一句话摘要)
2. [设计方案](#设计方案)
   - [架构选型](#架构选型)
   - [调用方式](#调用方式)
   - [候选池来源](#候选池来源)
   - [5轮研究框架](#5轮研究框架)
   - [淘汰机制细节](#淘汰机制细节)
   - [输出报告结构](#输出报告结构)
3. [行动原则](#行动原则)
4. [行动计划](#行动计划)

---

## 一句话摘要

新增 `stock-researcher` Agent，通过5轮分层淘汰研究框架，自动挖掘7连阳和历史新高股票的深层走强原因，并通过 `pi-trader research` 命令调用。

---

## 设计方案

### 架构选型

**单 Agent + 结构化阶段**（与 catalyst-analyst 模式一致）

一个 `.md` 文件，内嵌完整的5轮研究流程。Agent 自管状态，每轮有明确的输入/输出和淘汰记录。选择此方案原因：与现有 catalyst-analyst 架构模式完全一致，项目内已有成功先例，维护成本最低。

### 调用方式

通过 `pi-trader research` CLI 命令调用，无日期参数（自动取最近交易日）：

```bash
# 默认模式（自动获取7连阳+历史新高）
pi-trader research

# 指定股票（跳过前3轮淘汰，直接深度研究）
pi-trader research --stocks 600396,603929

# verbose + 指定模型
pi-trader research -v --model kimi-k2p5
```

底层调用链：`pi-trader research` → `bin/run-research.sh` → `pi --print --agent agents/researchers/stock-researcher.md`

### 候选池来源

默认模式下，候选股票来源于两个接口（合并去重）：

| 来源 | 接口 | 过滤条件 | 优先级排序 |
|------|------|---------|---------|
| 连阳股票 | `pi-trader data consecutive-red` | `consecutive_days >= 7` | `consecutive_days` 降序，`gain_pct` 降序 |
| 历史新高 | `pi-trader data new-high` | 全量 | `change_pct` 降序 |

指定股票模式：直接进入 Round 4，跳过前3轮淘汰。

### 5轮研究框架

```
候选池（7连阳 + 历史新高，合并去重）
    │
    ▼
Round 1 — 基本面排雷        每只股票 2~3 次搜索
    │  淘汰：ST/壳股/纯概念/近期重大利空
    ▼
Round 2 — 催化剂验证        每只股票 3~4 次搜索
    │  淘汰：无明确驱动力/催化剂已完全消化/谣言
    ▼
Round 3 — 赛道与竞争位置    每只股票 3~4 次搜索
    │  淘汰：同题材内有更强龙头/跟风概念股/市值过大
    ▼
Round 4 — AI 自主深度研究   Top 3~5，每只 3~5 轮搜索
    │  AI 自主决定研究方向
    ▼
Round 5 — AI 自主深度研究   Top 3，最终定稿
    │
    ▼
最终报告：强烈推荐 / 关注 / 回避
```

### 淘汰机制细节

#### Round 1 — 基本面排雷

- **搜索渠道**：百度 / Google
- **搜索词**：`{股票名} 主营业务`、`{股票名} 公告`
- **淘汰条件**（满足任意一条）：
  - ST / \*ST 股票
  - 主营业务与走强逻辑明显无关（纯壳公司、主业亏损多年）
  - 近30天有重大利空公告（减持、业绩暴雷、立案调查）
- **记录格式**：每只股票一行，`✅ 保留` 或 `❌ 淘汰（原因）`

#### Round 2 — 催化剂验证

- **搜索渠道**：淘股吧 / 雪球 / 微信
- **搜索词**：`{股票名} 涨停`、`{题材} 政策/订单/业绩`
- **淘汰条件**（满足任意一条）：
  - 找不到明确催化剂（纯技术突破、无基本面支撑）
  - 催化剂已完全消化（2周前旧消息，市场已充分反应）
  - 催化剂为谣言/被辟谣
- **保留优先级**：政策刚落地 > 订单/业绩超预期 > 行业景气周期 > 资金持续关注

#### Round 3 — 赛道与竞争位置

- **搜索渠道**：雪球 / Google
- **搜索词**：`{股票名} 行业地位`、`{题材} 龙头股`
- **淘汰条件**（满足任意一条）：
  - 同题材内有明显更强龙头
  - 跟风股（蹭概念，实际主营无关联）
  - 流通市值 > 500亿（弹性不足）
- **输出**：每只保留股打赛道地位评分（龙头 / 次龙 / 跟风）

#### Round 4~5 — AI 自主深度研究

Agent 基于前3轮发现，自主决定：
- 哪些信息空白需要填补
- 聚焦哪个渠道（机构观点 / 产业链调研 / 游资动向）
- 每只股票完成 3~5 轮搜索后给出最终评级

**可用搜索渠道**（全部通过 `omp-web-operator`）：Google / 百度 / 微信 / 雪球 / 淘股吧

### 输出报告结构

文件路径：`data/reports/{YYYY-MM-DD}/stock-research-{YYYY-MM-DD}.md`

```markdown
# 个股深度研究报告 — {日期}

## 候选池（共 N 只）
| 代码 | 名称 | 来源 | 连阳天数 | 区间涨幅 | 入选理由 |

## Round 1 淘汰记录 — 基本面排雷
| 代码 | 名称 | 结果 | 原因 |

## Round 2 淘汰记录 — 催化剂验证
（同上格式）

## Round 3 淘汰记录 — 赛道与竞争位置
（同上格式）

## 深度研究 — Top N 股票

### {股票名}（{代码}）
#### Round 4 — {AI自主决定的研究方向}
**搜索词**：...  **阅读内容**：... **关键发现**：... **下一轮方向**：...
#### Round 5 — {AI自主决定的研究方向}
...
#### 最终评级：强烈推荐 / 关注 / 回避
**走强核心原因**：（1~2句话）
**推荐理由**：...  **主要风险**：...  **关注价位**：（有把握时给出）

## 综合结论
### 强烈推荐 / 关注 / 回避
- **{股票名}**：{一句话理由}

### 跨标的发现（可选）
- 多只股票共振的主线：...
- 资金流向线索：...
```

---

## 行动原则

- **Zero-Context Entry**：任何人拿到 Agent 文件和 SKILL.md 即可独立运行，无需口头交接
- **Break Don't Bend**：淘汰标准硬编码在 system prompt 中，不因"差不多"而保留不合格标的
- **Explicit Contract**：ashare-data SKILL.md 是调用约定的唯一事实来源，Agent 不重复定义脚本路径
- **Minimum Blast Radius**：CLI 扩展仅新增命令和脚本，不修改现有 `run`/`insight`/`data` 命令逻辑

---

## 行动计划

### 文件改动清单

| 操作 | 文件 |
|------|------|
| 新建 | `agents/researchers/stock-researcher.md` |
| 新建 | `bin/run-research.sh` |
| 新建 | `scripts/fetch-consecutive-red.sh` |
| 新建 | `scripts/fetch-new-high.sh` |
| 修改 | `cli/app.py` — 新增 `research` 命令 |
| 修改 | `skills/ashare-data/SKILL.md` — 新增 consecutive-red / new-high 子命令文档 |
| 修改 | `CLAUDE.md` — 更新目录结构和常用命令 |

### 任务步骤

**Task 1 — 新增数据脚本 + 更新 SKILL.md**
- 新建 `scripts/fetch-consecutive-red.sh`：调用 `/consecutive-red/daily/{date}`
- 新建 `scripts/fetch-new-high.sh`：调用 `/new-high/daily/{date}`
- 在 `cli/app.py` 的 `subcommand_map` 里注册 `consecutive-red` 和 `new-high`
- 更新 `skills/ashare-data/SKILL.md`：在 Available Commands 中添加两个新命令的描述、用法、返回字段

**Task 2 — 在 `cli/app.py` 新增 `research` 命令**
- 参数：`--stocks`（可选，逗号分隔）、`--model/-m`、`--verbose/-v`
- 无日期参数，脚本内部自动取最近交易日
- 调用 `_run_script("run-research.sh", args)`

**Task 3 — 创建 `bin/run-research.sh`**
- 支持 `-v`（verbose）和 `-m model` 参数
- 自动获取最近交易日（复用 run-analysis.sh 中的逻辑）
- 调用 `pi --print [--verbose] --model ... --agent agents/researchers/stock-researcher.md "..."`
- 输出写入 `data/reports/{date}/stock-research-{date}.md`

**Task 4 — 创建 `agents/researchers/stock-researcher.md`**
- YAML frontmatter：name, description, tools, model
- 双入口逻辑（指定股票 vs 默认模式）
- 完整5轮研究框架 system prompt
- 淘汰标准、搜索策略、输出报告模板

**Task 5 — 更新 `CLAUDE.md`**
- 目录结构中添加 `agents/researchers/stock-researcher.md`
- 常用命令中添加 `pi-trader research` 示例
