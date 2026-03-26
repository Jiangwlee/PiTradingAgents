# 经验注入命令设计（pi-trader inject）

> 允许用户手动注入交易经验，AI 通过 web-operator 深度研究验证后写入记忆库。

## 目录

1. [背景与动机](#1-背景与动机)
2. [设计方案](#2-设计方案)
3. [行动原则](#3-行动原则)
4. [行动计划](#4-行动计划)

---

## 1. 背景与动机

当前记忆库（`data/memory/*.jsonl`）中的经验全部由 `reflect` 流程自动生成：Pipeline 运行 → 次日对比 → Reflector Agent 反思 → 写入记忆。缺少人工注入通道，用户无法将自己的交易认知和经验教训直接融入系统。

**核心需求**：新增 `pi-trader inject` 命令，用户提供一条经验文本，AI 深度研究验证后写入记忆库。

## 2. 设计方案

### 2.1 整体架构

单 Agent 一体化方案。一个 `experience-injector.md` Agent 完成全部工作。

```
pi-trader inject "经验文本" [--role trader]
       │
       ▼
  run-inject.sh
       │
       ├── 1. 构造 prompt（用户经验 + 可选 role）
       │
       ├── 2. 调用 experience-injector Agent（默认 stream 模式）
       │      └── Agent 内部：解析 → web-operator 多源搜索 → 结论 → JSON
       │
       ├── 3. 从输出提取 JSON
       │
       ├── 4. 检查 verdict
       │      ├── reject → 打印拒绝理由，exit 1
       │      └── accept → 继续
       │
       └── 5. 补充 meta（date=今天, source=manual）→ memory.py store
```

### 2.2 Agent 定义：`agents/reflection/experience-injector.md`

**定位**：交易经验研究员（不是裁判）。核心价值是丰富经验上下文，而非投票判定对错。

**frontmatter**：

```yaml
name: experience-injector
description: 交易经验研究员 — 研究验证用户经验并形成结构化记忆
tools: bash, read, web-operator
model: qwen3.5-35b
```

**工作流程**（4 步）：

1. **解析经验** — 理解核心主张和适用场景
2. **网络研究** — 通过 Google/淘股吧/雪球搜索相关案例、正反观点（至少 3 个来源）
3. **形成结论** — 判断是否与市场基本规律矛盾；不矛盾则提炼适用条件和边界
4. **输出结果** — JSON 格式

**拒绝标准**（严格限制，只拒绝明显错误的）：

- 与市场基本机制矛盾（如"涨停板可以无限买入"）
- 因果关系明显错误
- 基于已被废除的政策/规则

**角色自动判定逻辑**（用户未指定 `--role` 时）：

- 涉及多空方向判断 → bull 或 bear
- 涉及仓位/风控/综合决策 → trader
- 涉及题材评估/市场环境判断 → judge

**输出 JSON 结构**：

accept 时：

```json
{
  "verdict": "accept",
  "role": "trader",
  "research_summary": "搜索了3个来源，找到2个支持案例...",
  "market_situation": "由 AI 根据经验内容推断的适用情境描述（如：冰点期 跌停家数增加 情绪低迷）",
  "situation": "用户注入的经验原文",
  "recommendation": "经过研究丰富后的结构化经验",
  "improvements": ["当冰点期跌停家数未连续两天缩减时，应回避抄底操作"],
  "summary": "丰富后的经验摘要",
  "query": "BM25 检索用的高密度语句"
}
```

reject 时：

```json
{
  "verdict": "reject",
  "reason": "该经验与市场基本规律矛盾：...",
  "research_summary": "搜索发现..."
}
```

### 2.3 编排脚本：`bin/run-inject.sh`

**参数**：

```
run-inject.sh [--mode stream|text|json] [-m MODEL] [--role ROLE] "经验文本"
```

**关键设计**：

- **多 skill 加载**：`run_agent_node` 当前硬编码 `--skill ashare-data`，无法追加第二个 skill。解决方案：支持 `EXTRA_SKILLS` 环境变量，`run_agent_node` 读取后追加到 `pi_args`。修改 `pi-runner.sh` 加入：
  ```bash
  # 在 pi_args 构造后追加额外 skill
  if [[ -n "${EXTRA_SKILLS:-}" ]]; then
      for skill_path in $EXTRA_SKILLS; do
          pi_args+=(--skill "$skill_path")
      done
  fi
  ```
  `run-inject.sh` 中设置 `EXTRA_SKILLS="$HOME/.agents/skills/web-operator"` 后调用 `run_agent_node`
- 复用 `bin/lib/pi-runner.sh` 的 `run_agent_node` 函数
- 复用 reflect 中的 `parse_reflection_json` 逻辑提取 JSON
- **role 白名单校验**：提取 JSON 后、写入记忆前，校验 `role` 是否在 `[bull, bear, judge, trader]` 范围内，不合法则报错提示用户手动指定 `--role`
- **路径初始化**：与 `run-reflect.sh` 一致，通过环境变量推导 `MEMORY_DIR`：
  ```bash
  PITA_HOME="${PITA_HOME:-$HOME/.local/share/PiTradingAgents}"
  PITA_DATA_DIR="${PITA_DATA_DIR:-$PITA_HOME/data}"
  MEMORY_DIR="$PITA_DATA_DIR/memory"
  mkdir -p "$MEMORY_DIR"
  ```
- **临时目录隔离**：使用 `mktemp -d` 创建临时目录，`trap` 清理，避免多实例并发文件名冲突
- 记忆写入通过 `memory.py store-batch`（stdin JSON），额外传入 `source: "manual"` 字段

**prompt 构造**：

```
请研究并验证以下交易经验：

"""
{用户输入的经验文本}
"""

{如果指定 role: "请将此经验归类到角色：{role}"}
{如果未指定: "请根据经验内容自动判定最适合的角色（bull/bear/judge/trader）"}
```

### 2.4 CLI 命令：`pi-trader inject`

```python
@app.command()
def inject(
    experience: Annotated[str, typer.Argument(help="交易经验文本")],
    role: Annotated[Optional[str], typer.Option("--role", "-r", help="目标角色")] = None,
    model: Annotated[Optional[str], typer.Option("--model", "-m", help="LLM 模型")] = None,
    mode: Annotated[Literal["stream", "text", "json"], typer.Option("--mode")] = "stream",
) -> None:
    """注入交易经验（AI 研究验证后写入记忆库）"""
```

**默认 `stream` 模式**（不同于其他命令默认 `text`），因为深度研究过程需要实时可见。

**使用示例**：

```bash
# 最简用法
pi-trader inject "冰点期不要抄底，等跌停家数连续两天缩减再入场"

# 指定角色
pi-trader inject --role trader "连板股第三天放量要警惕，大概率是出货"
```

### 2.5 记忆写入字段映射

| Agent 输出字段 | memory.py 字段 | 说明 |
|---|---|---|
| `role` | `role` | Agent 判定或用户指定 |
| （注入当天） | `date` | `YYYY-MM-DD` 格式 |
| `situation` | `situation` | 用户经验原文 |
| `recommendation` | `recommendation` | 研究丰富后的结构化经验 |
| `improvements` | extra: `improvements` | 可执行规则列表 |
| `summary` | extra: `summary` | 经验摘要 |
| `query` | extra: `query` | BM25 检索语句 |
| `research_summary` | extra: `research_summary` | 研究过程摘要 |
| `"manual"` | extra: `source` | 来源标记 |

### 2.6 不做的事

- 不加 `--file` 输入方式
- 不加 `--force` 强制写入
- 不修改 `memory.py`（现有接口足够）
- 不做 `--deep` 开关（始终深度研究）
- 不修改 `reflector.md`
- 不支持 `interactive` 模式（单 Agent 无需 TUI 会话）
- web-operator 不可用时 Agent 仍可基于模型知识给出结论，在 `research_summary` 中标注"无网络搜索"

## 3. 行动原则

### TDD

`run-inject.sh` 完成后用一条真实经验端到端测试：stream 输出可见 → JSON 解析成功 → verdict 判断正确 → 记忆写入正确（检查 jsonl 文件）。

### Break Don't Bend

experience-injector 是独立新 Agent，不修改 reflector.md，不复用 reflect 的 prompt 逻辑。编排脚本独立，不嵌入 run-reflect.sh。

### Zero-Context Entry

Agent prompt 自包含完整工作流程、输出格式、拒绝标准和角色判定规则，不依赖外部文档。

## 4. 行动计划

### 文件变更清单

| 操作 | 文件 | 说明 |
|---|---|---|
| 新建 | `agents/reflection/experience-injector.md` | Agent 定义 |
| 新建 | `bin/run-inject.sh` | 编排脚本 |
| 修改 | `bin/lib/pi-runner.sh` | 支持 `EXTRA_SKILLS` 环境变量 |
| 修改 | `bin/pi-trader` | 新增 `inject` 命令 |
| 修改 | `CLAUDE.md` | 目录结构 + 常用命令 + 自进化闭环图 |

### 任务步骤

1. **修改 pi-runner.sh** — 在 `run_agent_node` 中支持 `EXTRA_SKILLS` 环境变量，追加额外 `--skill` 参数到 `pi_args`
2. **新建 Agent 定义** — 编写 `agents/reflection/experience-injector.md`，包含 system prompt、工作流程、输出格式、拒绝标准、角色判定规则、`market_situation` 推断要求
3. **新建编排脚本** — 编写 `bin/run-inject.sh`，处理参数解析、prompt 构造、Agent 调用、JSON 提取、verdict 判断、role 白名单校验、记忆写入
4. **修改 CLI** — 在 `bin/pi-trader` 中新增 `inject` 命令
5. **端到端测试** — 用一条真实经验测试完整流程
6. **更新文档** — CLAUDE.md 中补充 inject 命令说明、目录结构、自进化闭环图中的手动注入通道
