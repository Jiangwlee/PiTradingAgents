#!/usr/bin/env bash
# PiTradingAgents 标准安装脚本
# 遵循 Linux 最佳实践：代码部署到 ~/.PiTradingAgents/，数据分离到 XDG 目录

set -euo pipefail

# 版本
VERSION="1.1.0"

# 标准路径（遵循 XDG Base Directory Specification）
PITA_HOME="${PITA_HOME:-$HOME/.PiTradingAgents}"           # 应用根目录
PITA_DATA_DIR="${PITA_DATA_DIR:-$HOME/.local/share/PiTradingAgents}"  # 运行时数据
PITA_CONFIG_DIR="${PITA_CONFIG_DIR:-$HOME/.config/PiTradingAgents}"   # 配置文件
PITA_BIN_DIR="${PITA_BIN_DIR:-$HOME/.local/bin}"          # 用户命令目录

# 源代码位置（当前执行 install.sh 的目录）
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
PiTradingAgents Installer v${VERSION}

Usage: ./install.sh [OPTIONS]

Install PiTradingAgents to standard locations:
  - Code:    ~/.PiTradingAgents/
  - Data:    ~/.local/share/PiTradingAgents/
  - Config:  ~/.config/PiTradingAgents/
  - Command: ~/.local/bin/pi-trader

Options:
  --upgrade          Upgrade existing installation
  --uninstall        Remove PiTradingAgents completely
  --help, -h         Show this help message

Environment variables:
  PITA_HOME          Override application directory (default: ~/.PiTradingAgents)
  PITA_DATA_DIR      Override data directory (default: ~/.local/share/PiTradingAgents)
  PITA_CONFIG_DIR    Override config directory (default: ~/.config/PiTradingAgents)
  PITA_BIN_DIR       Override binary directory (default: ~/.local/bin)

Examples:
  ./install.sh                    # Fresh install
  ./install.sh --upgrade          # Upgrade existing installation
  ./install.sh --uninstall        # Complete removal
EOF
}

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_success() {
    echo "[OK] $1"
}

log_warn() {
    echo "[WARN] $1"
}

# 检查依赖
check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing=()
    
    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi
    
    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_error "Please install them and retry."
        exit 1
    fi
    
    log_success "All dependencies satisfied"
}

# 检查 ashare-data 服务
check_ashare_data() {
    log_info "Checking ashare-data service..."
    
    local ashare_url="${ASHARE_API_URL:-http://127.0.0.1:8000}"
    
    if curl -sf --connect-timeout 3 "$ashare_url/health" &> /dev/null; then
        log_success "ashare-data is running at $ashare_url"
        return 0
    else
        echo ""
        log_error "ashare-data is NOT running!"
        echo ""
        echo "PiTradingAgents requires ashare-data to function."
        echo ""
        echo "Please install and start ashare-data first:"
        echo ""
        echo "  1. Clone the repository:"
        echo "     git clone git@github.com:Jiangwlee/ashare-data.git"
        echo "     cd ashare-data"
        echo ""
        echo "  2. Start the service (usually with Docker):"
        echo "     docker-compose up -d"
        echo ""
        echo "  3. Verify it's running:"
        echo "     curl http://localhost:8000/health"
        echo ""
        echo "For more information, visit:"
        echo "  https://github.com/Jiangwlee/ashare-data"
        echo ""
        
        read -p "Continue installation anyway? [y/N] " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation aborted. Please start ashare-data and retry."
            exit 1
        fi
        
        log_warn "Continuing without ashare-data. PiTrader commands will fail until it's started."
    fi
}

# 创建目录结构
create_directories() {
    log_info "Creating directory structure..."
    
    # 应用目录
    mkdir -p "$PITA_HOME"/{bin,cli,scripts,agents,skills}
    mkdir -p "$PITA_HOME/agents"/{analysts,debaters,judges,reflection,decision}
    
    # 数据目录
    mkdir -p "$PITA_DATA_DIR"/{data/reports,data/memory}
    
    # 配置目录
    mkdir -p "$PITA_CONFIG_DIR"
    
    # 初始化记忆文件
    touch "$PITA_DATA_DIR/data/memory"/{bull,bear,judge,trader}.jsonl
    
    log_success "Directories created"
}

# 复制代码
copy_code() {
    log_info "Installing code to $PITA_HOME..."
    
    # 检查源目录
    if [[ ! -d "$SOURCE_DIR/cli" ]] || [[ ! -d "$SOURCE_DIR/scripts" ]]; then
        log_error "Source directory missing required subdirectories (cli/, scripts/)"
        log_error "Please run install.sh from the project root directory."
        exit 1
    fi
    
    # 复制 Python CLI
    cp -r "$SOURCE_DIR/cli" "$PITA_HOME/"
    
    # 复制 Bash 脚本
    cp -r "$SOURCE_DIR/scripts" "$PITA_HOME/"
    
    # 复制 Agents
    cp -r "$SOURCE_DIR/agents" "$PITA_HOME/"
    
    # 复制入口脚本
    cp "$SOURCE_DIR/bin/pi-trader" "$PITA_HOME/bin/"
    cp "$SOURCE_DIR/bin/run-analysis.sh" "$PITA_HOME/bin/"
    cp "$SOURCE_DIR/bin/run-reflect.sh" "$PITA_HOME/bin/"
    
    # 使脚本可执行
    chmod +x "$PITA_HOME/bin/"*
    chmod +x "$PITA_HOME/scripts/"*.sh
    
    log_success "Code installed"
}

# 创建虚拟环境
setup_venv() {
    log_info "Setting up Python virtual environment..."
    
    local venv_path="$PITA_HOME/.venv"
    
    if [[ -d "$venv_path" ]]; then
        log_info "Virtual environment already exists, skipping creation"
    else
        python3 -m venv "$venv_path"
        log_success "Virtual environment created"
    fi
    
    # 安装依赖
    log_info "Installing Python dependencies..."
    "$venv_path/bin/pip" install --upgrade pip -q
    "$venv_path/bin/pip" install -q typer rich requests
    
    log_success "Dependencies installed"
}

# 创建命令入口
create_command() {
    log_info "Creating command entry point..."
    
    local target="$PITA_BIN_DIR/pi-trader"
    
    # 创建包装脚本
    cat > "$target" <<EOF
#!/usr/bin/env bash
# PiTradingAgents CLI wrapper
# Auto-generated by install.sh

export PITA_HOME="$PITA_HOME"
export PITA_DATA_DIR="$PITA_DATA_DIR"
export PITA_CONFIG_DIR="$PITA_CONFIG_DIR"
export PITA_APP_DIR="$PITA_HOME"
export ASHARE_API_URL="\${ASHARE_API_URL:-http://127.0.0.1:8000}"

exec "$PITA_HOME/.venv/bin/python3" "$PITA_HOME/bin/pi-trader" "\$@"
EOF
    
    chmod +x "$target"
    log_success "Command created: $target"
}

# 生成配置文件
generate_config() {
    log_info "Generating configuration..."
    
    cat > "$PITA_CONFIG_DIR/config.env" <<EOF
# PiTradingAgents Configuration
# Generated by install.sh v${VERSION}

PITA_HOME="$PITA_HOME"
PITA_DATA_DIR="$PITA_DATA_DIR"
PITA_CONFIG_DIR="$PITA_CONFIG_DIR"
PITA_APP_DIR="$PITA_HOME"
ASHARE_API_URL="http://127.0.0.1:8000"

# Python Environment
PYTHON_BIN="$PITA_HOME/.venv/bin/python3"
EOF
    
    log_success "Configuration saved to $PITA_CONFIG_DIR/config.env"
}

# 验证安装
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # 检查目录
    [[ -d "$PITA_HOME/cli" ]] || { log_error "Missing: $PITA_HOME/cli"; errors=$((errors+1)); }
    [[ -d "$PITA_HOME/scripts" ]] || { log_error "Missing: $PITA_HOME/scripts"; errors=$((errors+1)); }
    [[ -f "$PITA_HOME/bin/pi-trader" ]] || { log_error "Missing: $PITA_HOME/bin/pi-trader"; errors=$((errors+1)); }
    
    # 检查命令
    [[ -x "$PITA_BIN_DIR/pi-trader" ]] || { log_error "Missing: $PITA_BIN_DIR/pi-trader"; errors=$((errors+1)); }
    
    # 检查 Python 环境
    [[ -f "$PITA_HOME/.venv/bin/python3" ]] || { log_error "Missing: Python venv"; errors=$((errors+1)); }
    
    if [[ $errors -eq 0 ]]; then
        log_success "Installation verified"
        return 0
    else
        log_error "Installation verification failed with $errors errors"
        return 1
    fi
}

# 卸载
uninstall() {
    log_info "Uninstalling PiTradingAgents..."
    
    # 移除命令
    if [[ -f "$PITA_BIN_DIR/pi-trader" ]]; then
        rm -f "$PITA_BIN_DIR/pi-trader"
        log_success "Removed: $PITA_BIN_DIR/pi-trader"
    fi
    
    # 询问是否删除数据和配置
    echo ""
    read -p "Remove all data and configuration? [y/N] " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$PITA_HOME"
        rm -rf "$PITA_DATA_DIR"
        rm -rf "$PITA_CONFIG_DIR"
        log_success "Removed all application files"
    else
        log_info "Keeping data in $PITA_DATA_DIR and config in $PITA_CONFIG_DIR"
        rm -rf "$PITA_HOME"
        log_success "Removed application code only"
    fi
    
    echo ""
    log_success "PiTradingAgents has been uninstalled"
}

# 升级
upgrade() {
    log_info "Upgrading PiTradingAgents..."
    
    if [[ ! -d "$PITA_HOME" ]]; then
        log_error "No existing installation found at $PITA_HOME"
        log_error "Use: ./install.sh (without --upgrade) for fresh install"
        exit 1
    fi
    
    log_info "Backing up configuration..."
    if [[ -f "$PITA_CONFIG_DIR/config.env" ]]; then
        cp "$PITA_CONFIG_DIR/config.env" "$PITA_CONFIG_DIR/config.env.backup.$(date +%Y%m%d)"
    fi
    
    log_info "Removing old code..."
    rm -rf "$PITA_HOME/cli"
    rm -rf "$PITA_HOME/scripts"
    rm -rf "$PITA_HOME/agents"
    rm -rf "$PITA_HOME/bin"
    
    # 重新创建目录结构
    mkdir -p "$PITA_HOME"/{bin,cli,scripts,agents,skills}
    
    log_info "Installing new version..."
    copy_code
    setup_venv
    create_command
    generate_config
    
    log_success "Upgrade completed"
}

# 主流程
main() {
    # 解析参数
    case "${1:-}" in
        --help|-h)
            usage
            exit 0
            ;;
        --uninstall)
            uninstall
            exit 0
            ;;
        --upgrade)
            upgrade
            verify_installation
            print_summary
            exit 0
            ;;
        "")
            # Fresh install
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    
    # 检查是否已安装
    if [[ -d "$PITA_HOME" ]] && [[ "${1:-}" != "--upgrade" ]]; then
        log_error "PiTradingAgents is already installed at $PITA_HOME"
        log_error "Use --upgrade to upgrade, or --uninstall to remove"
        exit 1
    fi
    
    # 执行安装
    echo "=============================================="
    echo "PiTradingAgents Installer v${VERSION}"
    echo "=============================================="
    echo ""
    
    check_dependencies
    check_ashare_data
    create_directories
    copy_code
    setup_venv
    create_command
    generate_config
    verify_installation
    
    print_summary
}

print_summary() {
    echo ""
    echo "=============================================="
    echo "✅ Installation Complete!"
    echo "=============================================="
    echo ""
    echo "📁 Installation Paths:"
    echo "   Application:  $PITA_HOME"
    echo "   Data:         $PITA_DATA_DIR"
    echo "   Config:       $PITA_CONFIG_DIR"
    echo "   Command:      $PITA_BIN_DIR/pi-trader"
    echo ""
    echo "🚀 Quick Start:"
    echo "   pi-trader --help           # Show all commands"
    echo "   pi-trader doctor           # Check system status"
    echo "   pi-trader run 2026-03-24   # Run analysis"
    echo ""
    echo "📖 Documentation:"
    echo "   docs/cli-guide.md          # Complete usage guide"
    echo "   docs/CHANGELOG.md          # Version history"
    echo ""
    
    # 检查 PATH
    if [[ ":$PATH:" != *":$PITA_BIN_DIR:"* ]]; then
        echo "⚠️  Warning: $PITA_BIN_DIR is not in your PATH"
        echo "   Add this to your ~/.bashrc or ~/.zshrc:"
        echo "   export PATH=\"\$PATH:$PITA_BIN_DIR\""
        echo ""
    fi
}

# 执行
main "$@"
