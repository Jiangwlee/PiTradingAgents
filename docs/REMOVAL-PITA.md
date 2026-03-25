# 移除 `pita` 命令说明

## 概述

在版本 1.1.0 中，项目已完全移除了旧的 `pita` Bash CLI 命令，所有功能统一迁移到现代化的 `pi-trader` Python CLI。

**重要**: 请只使用 `pi-trader`，不要再尝试使用 `pita`。

## 移除原因

1. **更好的用户体验**
   - 自动化的 Help 信息生成
   - 类型安全的参数验证
   - 彩色输出和友好的错误提示

2. **统一的参数支持**
   - 所有命令支持 `--model`, `--verbose` 等选项
   - 灵活的参数顺序（选项可在日期前或后）

3. **现代化技术栈**
   - 基于 Typer + Rich 框架
   - 更易维护和扩展
   - 与现有 Python 代码库兼容

4. **命令重命名**
   - `reflect` → `insight`（强调自进化能力）

## 变更清单

### 已删除的文件
- ❌ `bin/pita` (Bash CLI)
- ❌ 所有对 `pita` 的引用

### 新增的文件
- ✅ `bin/pi-trader` (Python CLI)
- ✅ `cli/app.py` (Typer 应用主程序)
- ✅ `docs/cli-guide.md` (完整使用指南)
- ✅ `docs/cli-migration.md` (迁移指南)
- ✅ `docs/cli-testing.md` (测试报告)

### 更新的文件
- 🔄 `install.sh` - 移除 `pita` 安装，只安装 `pi-trader`
- 🔄 `skills/ashare-data/SKILL.md` - 更新为 `pi-trader data`
- 🔄 `docs/CHANGELOG.md` - 记录 breaking changes

## 迁移指南

### 基本命令对照

| 旧命令 (不再可用) | 新命令 (请使用) | 说明 |
|------------------|----------------|------|
| `pita run DATE` | `pi-trader run DATE` | 运行分析流程 |
| `pita reflect DATE` | `pi-trader insight DATE` | 运行复盘反思 |
| `pita data emotion DATE` | `pi-trader data emotion DATE` | 查询市场情绪 |
| `pita doctor` | `pi-trader doctor` | 系统诊断 |

### 新增功能

#### 1. 模型选择
```bash
# 之前：需要手动编辑脚本
# 现在：使用 --model 选项
pi-trader run -m qwen3.5-35b 2026-03-24
pi-trader insight -m kimi-k2-thinking 2026-03-20
```

#### 2. 阶段选择
```bash
# 仅执行特定阶段
pi-trader run -s 3 2026-03-24           # 仅题材辩论
pi-trader run -s 1,2 2026-03-24         # 阶段 1+2
```

#### 3. 灵活参数顺序
```bash
# 以下命令完全等价
pi-trader run 2026-03-24 -m qwen3.5-35b -v
pi-trader run -m qwen3.5-35b -v 2026-03-24
pi-trader run -v -s 3 -m qwen3.5-35b 2026-03-24
```

## 安装步骤

### 首次安装
```bash
cd /home/bruce/Projects/PiTradingAgents

# 1. 安装依赖
uv pip install typer

# 2. 运行安装脚本
./install.sh

# 3. 确保 ~/.local/bin 在 PATH 中
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 4. 开始使用
pi-trader --help
```

### 升级现有安装
```bash
cd /home/bruce/Projects/PiTradingAgents

# 1. 安装 Typer
uv pip install typer

# 2. 重新安装
./install.sh --upgrade

# 3. 旧版 pita 将被替换为 pi-trader
```

## 常见问题

### Q: 为什么移除 `pita`？
A: `pita` 是旧的 Bash 实现，存在以下问题：
- Help 信息需要手动维护
- 没有参数验证
- 错误提示不友好
- 不支持统一的选项（如 `--model`）

`pi-trader` 基于 Typer 框架，提供了更好的用户体验和可维护性。

### Q: 可以回退到 `pita` 吗？
A: 不可以。`pita` 已被完全移除，无法回退。请全部使用 `pi-trader`。

### Q: 如果遇到问题怎么办？
A: 
1. 查看帮助：`pi-trader --help`
2. 查看详细文档：`docs/cli-guide.md`
3. 检查依赖：`pi-trader doctor`

### Q: `data` 子命令还能用吗？
A: 可以！`pi-trader data <subcommand>` 完全保留，只是内部实现从 Bash 改为 Python。

支持的子命令：
- `emotion`, `emotion-history`
- `theme-pool`, `theme-emotion`, `theme-emotion-history`, `theme-stocks`
- `trend-pool`, `trend-history`
- `review`

## 技术细节

### 架构变化

**旧架构 (v1.0)**
```
pita (Bash)
├── run-analysis.sh
├── run-reflect.sh
└── data/*.sh
```

**新架构 (v1.1)**
```
pi-trader (Python + Typer)
├── cli/app.py
│   ├── run_analysis() → run-analysis.sh
│   ├── run_insight() → run-reflect.sh
│   ├── query_data() → fetch-*.sh
│   └── system_diagnostic() → inline
└── bin/pi-trader
```

### 依赖变化

| 依赖 | v1.0 | v1.1 | 说明 |
|------|------|------|------|
| Bash | ✅ | ✅ | 底层脚本仍用 Bash |
| Typer | ❌ | ✅ | 新增 CLI 框架 |
| Rich | ❌ | ✅ | 彩色输出 |
| Requests | ❌ | ✅ | API 调用（doctor） |

## 兼容性

### 向后兼容
- ❌ **无**。`pita` 命令已完全移除
- ✅ **底层脚本不变**。`run-analysis.sh`, `run-reflect.sh` 等仍然可用
- ✅ **数据格式不变**。所有输出格式保持一致

### 破坏性变更
1. `pita` 命令不可用
2. `reflect` 命令更名为 `insight`
3. 必须安装 Typer 才能使用 `pi-trader`

## 下一步

1. **阅读完整文档**: [`docs/cli-guide.md`](./cli-guide.md)
2. **了解技术细节**: [`docs/cli-migration.md`](./cli-migration.md)
3. **查看版本历史**: [`docs/CHANGELOG.md`](./CHANGELOG.md)

---

**版本**: 1.1.0  
**更新日期**: 2026-03-25  
**状态**: ✅ 已完成移除，所有功能迁移至 `pi-trader`
