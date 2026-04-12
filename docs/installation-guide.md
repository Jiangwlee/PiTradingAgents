# PiTradingAgents 安装指南

## 概述

PiTradingAgents 遵循 Linux 最佳实践，将**应用代码**、**运行时数据**和**用户配置**分离到标准位置。

## 安装路径设计

### 目录结构（遵循 XDG Base Directory Specification）

```
~/.PiTradingAgents/                    # 应用根目录（代码）
├── bin/                                # 可执行脚本
│   ├── pi-trader                      # CLI 入口（uv run --script + Typer）
│   ├── run-analysis.sh                # 分析 Pipeline
│   └── run-reflect.sh                 # 复盘 Pipeline
├── scripts/                            # 数据获取脚本
│   ├── fetch-market-emotion.sh
│   ├── fetch-theme-pool.sh
│   └── ...
├── agents/                             # Agent 定义
│   ├── analysts/
│   ├── debaters/
│   ├── judges/
│   └── ...
└── skills/                             # Skill 定义
    └── ashare-data/SKILL.md

~/.local/share/PiTradingAgents/         # 运行时数据（XDG_DATA_HOME）
├── reports/YYYY-MM-DD/                 # 每日分析报告
├── memory/                             # BM25 记忆库
│   ├── bull.jsonl
│   ├── bear.jsonl
│   ├── judge.jsonl
│   └── trader.jsonl
├── research/                           # 个股深度研究输出
└── signals/                            # 复盘信号数据

~/.config/PiTradingAgents/              # 用户配置（XDG_CONFIG_HOME）
└── config.env                          # 环境变量配置

~/.local/bin/pi-trader                  # 命令入口（符号链接或包装脚本）
```

### 路径设计原则

1. **应用代码** (`~/.PiTradingAgents/`)
   - 存放程序代码、脚本和虚拟环境
   - 由 `install.sh` 自动部署
   - 升级时替换，不保留用户修改

2. **运行时数据** (`~/.local/share/PiTradingAgents/`)
   - 存放生成的报告和记忆库
   - 升级时保留
   - 可通过环境变量自定义位置

3. **用户配置** (`~/.config/PiTradingAgents/`)
   - 存放环境变量配置
   - 升级时保留并备份
   - 用户可手动编辑

## 安装步骤

### 前置要求：安装 ashare-data

**PiTradingAgents 依赖 ashare-data 提供行情数据服务，必须先安装并启动 ashare-data。**

```bash
# 1. 克隆 ashare-data 仓库
git clone git@github.com:Jiangwlee/ashare-data.git
cd ashare-data

# 2. 按照 ashare-data 文档启动服务（通常使用 Docker）
docker-compose up -d

# 3. 验证服务是否运行
curl http://localhost:8000/health
# 应该返回: {"status":"ok"}
```

**注意**: 如果 ashare-data 未运行，PiTradingAgents 将无法获取市场数据。

### 1. 克隆 PiTradingAgents 仓库

```bash
cd ~/Projects  # 或任意临时目录
git clone <repository-url> PiTradingAgents
cd PiTradingAgents
```

### 2. 运行安装脚本

```bash
./install.sh
```

安装脚本会检查 ashare-data 是否运行，如果未运行会给出提示。

```bash
./install.sh
```

安装脚本将：
1. 检查系统依赖（python3, uv, git, curl）
2. 创建标准目录结构
3. 同步代码到 `~/.PiTradingAgents/`
4. 创建命令入口 `~/.local/bin/pi-trader`（symlink）
5. 生成配置文件

注意：Python 依赖由各脚本通过 `uv run --script` 的 inline dependencies 自管理，无需手动安装。

### 3. 确保 PATH 配置

```bash
# 检查 ~/.local/bin 是否在 PATH 中
which pi-trader

# 如果不在，添加到 ~/.bashrc 或 ~/.zshrc
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

### 4. 验证安装

```bash
# 查看帮助
pi-trader --help

# 系统诊断
pi-trader doctor

# 测试数据查询
pi-trader data emotion 2026-03-24
```

## 升级

### 方式一：使用 install.sh（推荐）

```bash
cd ~/Projects/PiTradingAgents  # 源码目录
git pull                       # 更新代码
./install.sh --upgrade         # 升级安装
```

`--upgrade` 会：
- 备份当前配置
- 替换应用代码
- 保留数据和配置
- 更新虚拟环境依赖

### 方式二：手动升级

```bash
# 1. 备份配置
cp ~/.config/PiTradingAgents/config.env ~/.config/PiTradingAgents/config.env.backup

# 2. 重新运行 install.sh
./install.sh --upgrade
```

## 卸载

### 完全卸载（包括数据）

```bash
cd ~/Projects/PiTradingAgents
./install.sh --uninstall
```

然后按提示选择是否删除数据。

### 仅卸载应用（保留数据）

```bash
# 删除命令
rm -f ~/.local/bin/pi-trader

# 删除应用代码
rm -rf ~/.PiTradingAgents/

# 数据和配置保留在：
# ~/.local/share/PiTradingAgents/
# ~/.config/PiTradingAgents/
```

## 环境变量

可以通过环境变量自定义安装路径：

```bash
# 自定义应用目录
PITA_HOME=/opt/PiTradingAgents ./install.sh

# 自定义数据目录
PITA_DATA_DIR=/data/pita ./install.sh

# 自定义配置目录
PITA_CONFIG_DIR=/etc/pita ./install.sh

# 自定义命令目录
PITA_BIN_DIR=/usr/local/bin ./install.sh
```

## 故障排除

### 问题：命令未找到

```bash
# 检查 PATH
echo $PATH | grep ".local/bin"

# 如果没有，添加到 shell 配置
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

### 问题：权限错误

```bash
# 确保目录权限正确
chmod -R u+rw ~/.PiTradingAgents/
chmod -R u+rw ~/.local/share/PiTradingAgents/
chmod -R u+rw ~/.config/PiTradingAgents/
```

### 问题：Python 脚本运行报错

```bash
# 确保 uv 已安装
uv --version

# 如果未安装
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 问题：找不到 install.sh

```bash
# 确保在项目根目录运行
ls install.sh  # 应该显示文件存在

# 如果不存在，可能是目录错误
cd ~/Projects/PiTradingAgents  # 替换为实际路径
```

### 问题：ashare-data 未运行

```bash
# 检查 ashare-data 是否运行
curl http://localhost:8000/health

# 如果失败，启动 ashare-data
cd ~/ashare-data  # 或 ashare-data 的安装路径
docker-compose up -d

# 等待几秒钟后再次检查
curl http://localhost:8000/health
```

### 问题：无法连接到数据源

如果运行 `pi-trader data emotion 2026-03-24` 时报错：

1. 检查 ashare-data 是否运行：`curl http://localhost:8000/health`
2. 检查 API URL 配置：`cat ~/.config/PiTradingAgents/config.env`
3. 确保 ASHARE_API_URL 指向正确的地址（默认 http://127.0.0.1:8000）

## 开发 vs 部署

| 场景 | 代码位置 | 命令 | 用途 |
|------|---------|------|------|
| **开发** | `~/Projects/PiTradingAgents/` | `bin/pi-trader` | 写代码、调试 |
| **部署** | `~/.PiTradingAgents/` | `pi-trader` | 日常使用 |

### 开发模式

如果你想修改代码并测试：

```bash
cd ~/Projects/PiTradingAgents

# 直接运行（不通过安装后的命令）
bin/pi-trader run 2026-03-24

# 修改代码后，重新安装以生效
./install.sh
```

### 部署模式

普通用户只需：

```bash
pi-trader run 2026-03-24
pi-trader reflect 2026-03-20
pi-trader data emotion 2026-03-24
```

## 相关文档

- [CLI 使用指南](./cli-guide.md) - 完整的命令参考
- [更新日志](./CHANGELOG.md) - 版本历史

---

**版本**: 1.1.0  
**更新日期**: 2026-03-25
