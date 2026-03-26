# pi-trader CLI 运行模式重构

> 将 `pi-trader` 的 agent 类命令统一到显式运行模式协议，消除 `-v/--verbose` 的歧义，并为多 Agent workflow 提供不会混流的可观测 stream 输出。

## 目录

- [设计方案](#设计方案)
- [行动原则](#行动原则)
- [行动计划](#行动计划)

---

## 设计方案

### 背景与目标

当前 `pi-trader run / research / reflect` 的输出语义不一致：`run` 和 `reflect` 依赖旧的 `pi-watch`，`research` 的 `-v` 只是 `--print + tee`，并不能形成真正可观测的流式协议。用户必须记忆每个命令各自的 verbose 行为，且多 Agent workflow 没有被正式建模，导致并行执行时正文混流风险没有被设计约束吸收。

本次重构目标是保留扁平命令结构，但将 `run / research / reflect` 统一为显式的 `text / stream / json / interactive` 四模式协议。`research` 与 `reflect` 采用单 Agent stream，`run` 采用 workflow-safe stream，确保多 Agent 并行阶段不会产生字符级交错输出。

成功标准：
- `pi-trader run / research / reflect` 共享同一套 `--mode text|stream|json|interactive`
- 删除 `-v/--verbose`，不保留兼容层
- `run --mode stream` 在并行阶段可观测，但不会混合多个 Agent 的正文字符流
- `research --mode stream` 与 `reflect --mode stream` 提供单 Agent 连续流式文本
- `json` 与 `interactive` 成为一等模式，而不是隐藏实现分支

### 架构

整体架构保留扁平 CLI，但把“业务编排”和“运行模式协议”拆开：

| 层 | 位置 | 职责 |
|----|------|------|
| 顶层 CLI | `bin/pi-trader` | 解析命令参数、暴露帮助文本、把 `mode` 和业务参数传给下层 |
| 共享执行层 | `bin/lib/pi-runner.*` | 解析 agent frontmatter，构造 `pi` 命令，统一实现 `text / stream / json / interactive` |
| 业务编排层 | `bin/run-analysis.sh` / `bin/run-research.sh` / `bin/run-reflect.sh` | 构造 prompt、编排阶段依赖、管理报告文件和业务降级逻辑 |

命令接口保持扁平：

```bash
pi-trader run [DATE] [--mode text|stream|json|interactive] [--model MODEL] [--stages 1,2,3]
pi-trader research [--stocks CODE_OR_NAME[,CODE_OR_NAME...]] [--mode text|stream|json|interactive] [--model MODEL]
pi-trader reflect DATE [--mode text|stream|json|interactive] [--model MODEL]
```

其中：
- `text`：stdout 只输出最终 assistant 文本；业务报告仍照常落盘
- `stream`：stdout 输出人类可读的可观测执行过程
- `json`：stdout 原样透传 `pi --mode json --print` 的 JSON lines
- `interactive`：直接进入 Pi TUI，并将业务 prompt 作为首条消息传入

`data / doctor` 不引入 `--mode`，因为它们不是 agent run 协议的一部分。

### Stream 设计

#### 单 Agent stream

`research` 与 `reflect` 都属于单 Agent 调用。它们的 `stream` 采用标准单流渲染：

```text
pi --mode json --print
    ↓
single-agent event parser
    ↓
single-agent stream renderer
    ├── header
    ├── assistant text_delta 连续输出
    ├── tool 完成摘要
    └── footer + usage
```

#### 多 Agent workflow stream

`run` 不是单 Agent 调用，而是一个多阶段、多 Agent 的 workflow。其 `stream` 必须定义为 workflow-safe stream，而不是把多个 agent 的 `text_delta` 同时写入共享 stdout。

workflow-safe stream 规则：
- 并行阶段禁止多个 agent 正文直写同一 stdout
- 每个 agent 的 JSON 事件流独立采集到各自缓冲或日志文件
- 终端实时展示 workflow 级事件：agent started / tool summary / agent completed / agent failed / stage completed
- 某个并行 agent 完成后，再一次性输出该 agent 的完整正文块，并带明确 label
- 串行阶段允许恢复连续正文 stream，因为同一时刻只有一个 agent 在前台执行

这样可以同时满足“长任务可观测”和“多 Agent 不混流”两个约束。

### 关键决策

- **保留扁平命令，不重组为二级子命令**：用户已经确认 `run / research / reflect / data / doctor` 的顶层心智模型是稳定的，本次只重构运行协议，不重排命令树。
- **删除 `-v/--verbose`，改为显式 `--mode`**：`verbose` 是含混的显示等级概念，不是协议。四模式是不同的 stdout contract，必须显式表达。
- **共享执行层成为唯一运行协议事实源**：业务脚本不得再各自手写 `pi --print`、`pi --mode json` 或自定义 verbose 分支，所有 agent 调用都必须经过统一 runner。
- **`run` 的 stream 单独建模为 workflow stream**：多 Agent workflow 不能照搬单 Agent 流式正文，否则会出现字符级交错和不可读输出。
- **报告落盘与 stdout mode 解耦**：`text / stream / json / interactive` 决定的是终端协议，不决定业务报告是否生成；报告保存继续由业务编排层负责。
- **本次不重构 install 机制**：CLI 重构不依赖安装链路调整，只要求新的命令语义在固定运行时根目录下稳定生效。

---

## 行动原则

- **TDD: Red → Green → Refactor**：先用最小可复现命令定义四模式行为，再改实现。 **禁止：** 先重写 CLI 再补行为验证。
- **Break, Don't Bend**：直接移除 `-v/--verbose` 和旧帮助文案，不做兼容层。 **禁止：** 保留 `verbose`、`legacy stream`、`deprecated mode` 等双轨语义。
- **Zero-Context Entry**：`bin/pi-trader`、共享 runner、相关文档的前部必须让读者立即理解四模式边界。 **禁止：** 文件头部不说明 mode 语义；文档没有目录。
- **Explicit Contract**：`text / stream / json / interactive` 的 stdout 语义必须在 CLI 帮助、共享 runner 和文档中一致声明。 **禁止：** 通过隐式默认或脚本内部约定表达模式差异。
- **First Principles over Analogy**：设计以“降低 `pi` 调用复杂度”和“让多 Agent 工作流可观测且不混流”为根本需求，不模仿别的 CLI。 **禁止：** 以“其他工具也有 `-v`”作为保留旧接口的理由。
- **Minimum Blast Radius**：只修改 agent 类命令及其相关文档，不借机重构 `data`、`doctor` 或安装系统。 **禁止：** 顺手改动无关命令或安装链路。

---

## 行动计划

### 文件变更清单

| 操作 | 文件路径 | 说明 |
|------|----------|------|
| 修改 | `bin/pi-trader` | 删除 `-v/--verbose`，引入统一 `--mode` 参数和帮助文本 |
| 新增 | `bin/lib/pi-runner.sh` | 共享执行层，统一解析 agent frontmatter 和四模式协议 |
| 新增 | `bin/lib/pi-stream.py` | stream/json 事件解析与渲染实现，覆盖单 Agent 与 workflow-safe stream |
| 修改 | `bin/run-analysis.sh` | 保留 workflow 编排，接入共享 runner，替换旧 verbose 分支 |
| 修改 | `bin/run-research.sh` | 保留 research 业务逻辑，接入共享 runner，删除 `--print + tee` verbose |
| 修改 | `bin/run-reflect.sh` | 保留 reflect 业务逻辑，接入共享 runner，删除 `pi-watch` 依赖 |
| 修改 | `docs/cli-guide.md` | 更新命令语义、示例和模式说明 |
| 修改 | `docs/cli-testing.md` | 更新 CLI 行为测试矩阵，覆盖四模式 |

### 任务步骤

#### Task 1: 重构顶层 CLI 契约

**Files:**
- 修改: `bin/pi-trader`
- 测试: `docs/cli-testing.md`

- [ ] **Step 1: 写行为验证清单**

  固定以下最小场景：

```bash
pi-trader run 2026-03-26
pi-trader run --mode stream 2026-03-26
pi-trader research --stocks 大胜达 --mode stream
pi-trader reflect 2026-03-25 --mode json
```

  验证点：
  - `text`：stdout 仅最终文本
  - `stream`：stdout 为人类可读流式输出
  - `json`：stdout 为 JSON lines
  - `interactive`：进入 Pi TUI

- [ ] **Step 2: 修改 `bin/pi-trader`**

  - 删除 `-v/--verbose`
  - 为 `run / research / reflect` 引入统一 `--mode`
  - 在帮助文本中明确四模式语义

- [ ] **Step 3: 手工验证帮助与参数解析**

```bash
pi-trader run --help
pi-trader research --help
pi-trader reflect --help
```

  预期：
  - 三个命令都出现相同的 `--mode` 说明
  - 不再出现 `verbose`

#### Task 2: 建立共享执行层

**Files:**
- 新增: `bin/lib/pi-runner.sh`
- 新增: `bin/lib/pi-stream.py`

- [ ] **Step 1: 提取统一的 agent 调用协议**

  共享 runner 负责：
  - 解析 frontmatter 的 `model / tools / system prompt`
  - 接收 `mode / output_file / label / prompt`
  - 构造统一 `pi` 命令

- [ ] **Step 2: 实现四模式分流**

  - `text` → `pi --print`
  - `stream` → `pi --mode json --print` + 本地 renderer
  - `json` → `pi --mode json --print` 原样透传
  - `interactive` → 进入 Pi TUI

- [ ] **Step 3: 实现最终文本提取**

  在 `text` 和 `stream` 下都能稳定提取最终 assistant 文本，以供业务层写报告文件。

#### Task 3: 设计并实现 stream 渲染

**Files:**
- 新增: `bin/lib/pi-stream.py`

- [ ] **Step 1: 实现单 Agent stream renderer**

  覆盖 `research / reflect`：
  - header
  - text_delta 连续输出
  - tool 完成摘要
  - usage/footer

- [ ] **Step 2: 实现 workflow-safe stream renderer**

  覆盖 `run`：
  - 并行阶段显示 workflow 级事件
  - 每个 agent 正文在完成后整块输出
  - 串行阶段允许连续正文 stream

- [ ] **Step 3: 验证并行阶段不混流**

```bash
pi-trader run --mode stream 2026-03-26
```

  预期：
  - 不会出现不同 agent 的字符级交错
  - 可看到每个 agent 的启动、工具摘要和完成状态

#### Task 4: 迁移业务编排脚本

**Files:**
- 修改: `bin/run-analysis.sh`
- 修改: `bin/run-research.sh`
- 修改: `bin/run-reflect.sh`

- [ ] **Step 1: `run-analysis.sh` 接入共享 runner**

  - 保留阶段编排、并行调度、记忆注入、状态保存
  - 删除旧 `run_agent()` 中的 verbose/`pi-watch` 逻辑
  - 接入 workflow-safe stream

- [ ] **Step 2: `run-research.sh` 接入共享 runner**

  - 保留 trade date、候选池和 prompt 构造
  - 删除 `--print + tee` 逻辑
  - 修复未传递 `--tools` 的问题

- [ ] **Step 3: `run-reflect.sh` 接入共享 runner**

  - 保留 state 校验、role prompt 构造、结果解析
  - 删除 `pi-watch` 依赖

#### Task 5: 文档更新

**Files:**
- 修改: `docs/cli-guide.md`
- 修改: `docs/cli-testing.md`

- [ ] **Step 1: 识别过时内容**

  检查：
  - `-v/--verbose` 示例
  - `insight` 等旧命令名或帮助文本
  - 缺失 `stream / json / interactive` 说明的章节

- [ ] **Step 2: 更新文档内容**

  - 统一 `run / research / reflect` 的四模式说明
  - 补充 `run` 的 workflow-safe stream 语义
  - 更新测试矩阵和示例命令

- [ ] **Step 3: 提交**

```bash
git add bin/pi-trader bin/lib/pi-runner.sh bin/lib/pi-stream.py \
        bin/run-analysis.sh bin/run-research.sh bin/run-reflect.sh \
        docs/cli-guide.md docs/cli-testing.md \
        docs/brainstorming/specs/2026-03-26-pi-trader-cli-redesign.md
git commit -m "feat: redesign pi-trader run modes"
```
