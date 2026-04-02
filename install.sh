#!/bin/bash
# PiTradingAgents 一键安装脚本
# 使用方式: curl -fsSL https://raw.githubusercontent.com/Jiangwlee/PiTradingAgents/main/install.sh | bash
#
# 功能:
# - 从 GitHub 克隆/更新代码
# - 注册 pi-trader 命令（symlink，依赖由 uv run --script 自管理）
# - 初始化数据目录

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
GITHUB_REPO="Jiangwlee/PiTradingAgents"
INSTALL_DIR="${HOME}/.PiTradingAgents"
BIN_DIR="${HOME}/.local/bin"
DATA_DIR="${HOME}/.local/share/PiTradingAgents"
CONFIG_DIR="${HOME}/.config/PiTradingAgents"

# 打印信息
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    info "检查依赖..."
    
    local missing=()
    
    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi
    
    if ! command -v uv &> /dev/null; then
        missing+=("uv")
    fi
    
    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "缺少必要依赖: ${missing[*]}"
        echo ""
        echo "请安装以下工具:"
        echo "  - git:    sudo apt install git"
        echo "  - uv:     curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo "  - python3: sudo apt install python3"
        echo "  - curl:   sudo apt install curl"
        echo ""
        exit 1
    fi
    
    success "所有依赖已满足"
}

# 克隆或更新代码
clone_or_update() {
    info "准备代码..."
    
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        # 已存在，执行更新
        info "检测到现有安装，执行更新..."
        cd "$INSTALL_DIR"
        git pull origin main
        success "代码已更新"
    else
        # 全新安装
        info "从 GitHub 克隆代码..."
        rm -rf "$INSTALL_DIR"  # 清理可能存在的旧目录
        git clone "https://github.com/$GITHUB_REPO.git" "$INSTALL_DIR"
        success "代码已克隆到 $INSTALL_DIR"
    fi
}

# 创建命令入口
create_command() {
    info "创建命令入口..."

    mkdir -p "$BIN_DIR"

    # symlink 到 bin/pi-trader（自带 uv run --script shebang，无需包装器）
    ln -sf "$INSTALL_DIR/bin/pi-trader" "$BIN_DIR/pi-trader"

    success "命令已注册: $BIN_DIR/pi-trader → $INSTALL_DIR/bin/pi-trader"
}

# 初始化数据目录
init_directories() {
    info "初始化数据目录..."
    
    # 创建数据目录
    mkdir -p "$DATA_DIR/data/reports"
    mkdir -p "$DATA_DIR/data/memory"
    
    # 创建记忆文件
    touch "$DATA_DIR/data/memory/bull.jsonl"
    touch "$DATA_DIR/data/memory/bear.jsonl"
    touch "$DATA_DIR/data/memory/judge.jsonl"
    touch "$DATA_DIR/data/memory/trader.jsonl"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 生成配置文件
    cat > "$CONFIG_DIR/config.env" << EOF
PITA_HOME="$INSTALL_DIR"
PITA_APP_DIR="$INSTALL_DIR"
PITA_DATA_DIR="$DATA_DIR"
PITA_CONFIG_DIR="$CONFIG_DIR"
ASHARE_API_URL="http://127.0.0.1:8000"
# PITA_DEFAULT_MODEL="qwen3.5-35b"             # run/reflect 全局默认模型
# PITA_DEFAULT_MODE="stream"                    # run/reflect 全局默认输出模式
# PITA_MODEL_STAGE3_BULL="kimi-k2-thinking"    # run 阶段3 看多辩手专用模型
# PITA_MODEL_STAGE3_BEAR="kimi-k2-thinking"    # run 阶段3 看空辩手专用模型
# PITA_MODEL_STAGE3_JUDGE="kimi-k2-thinking"   # run 阶段3 题材裁判专用模型
# PITA_MODEL_TRADER="kimi-k2-thinking"         # run 阶段4 投资经理专用模型
# PITA_MODEL_REFLECT="kimi-k2-thinking"         # reflect（反思）专用模型
EOF
    
    success "数据目录已初始化"
}

# 检查 ashare-data
check_ashare_data() {
    info "检查 ashare-data 服务..."
    
    if curl -sf --connect-timeout 3 "http://127.0.0.1:8000/health" &> /dev/null; then
        success "ashare-data 服务运行正常"
    else
        warn "ashare-data 未运行"
        echo ""
        echo "PiTradingAgents 需要 ashare-data 提供行情数据。"
        echo "请先安装并启动 ashare-data:"
        echo ""
        echo "  git clone git@github.com:Jiangwlee/ashare-data.git"
        echo "  cd ashare-data"
        echo "  docker-compose up -d"
        echo ""
    fi
}

# 打印完成信息
print_completion() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}✅ PiTradingAgents 安装成功!${NC}"
    echo "=============================================="
    echo ""
    echo "📁 安装路径:"
    echo "   代码:   $INSTALL_DIR"
    echo "   数据:   $DATA_DIR"
    echo "   配置:   $CONFIG_DIR"
    echo "   命令:   $BIN_DIR/pi-trader"
    echo ""
    
    # 检查 PATH
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo -e "${YELLOW}⚠️  请添加以下命令到你的 shell 配置文件:${NC}"
        echo ""
        echo "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        echo "   source ~/.bashrc"
        echo ""
    fi
    
    echo "🚀 快速开始:"
    echo "   pi-trader --help           # 查看帮助"
    echo "   pi-trader doctor           # 系统诊断"
    echo "   pi-trader run 2026-03-24   # 运行分析"
    echo ""
    echo "📖 文档:"
    echo "   cat $INSTALL_DIR/README.md"
    echo "   cat $INSTALL_DIR/docs/cli-guide.md"
    echo ""
    echo "🔄 升级:"
    echo "   重新运行安装命令即可自动更新"
    echo ""
}

# 主流程
main() {
    echo ""
    echo "=============================================="
    echo "PiTradingAgents 一键安装"
    echo "=============================================="
    echo ""
    
    check_dependencies
    clone_or_update
    create_command
    init_directories
    check_ashare_data
    print_completion
}

# 执行
main "$@"
