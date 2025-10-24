#!/bin/bash

# 应用管理脚本 - 用于后台启动和关闭app.py程序，包含自动依赖安装
# 作者: 自动生成
# 日期: $(date +%Y-%m-%d)

APP_NAME="xueqiu_etf_monitor"
APP_PY="app.py"
REQUIREMENTS_FILE="requirements.txt"
PID_FILE="logs/app.pid"
LOG_FILE="logs/app.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查并安装依赖
install_dependencies() {
    print_info "检查Python依赖..."
    
    # 检查Python环境
    if ! command -v python3 &> /dev/null; then
        print_error "未找到python3命令，请确保Python已安装"
        exit 1
    fi
    
    # 检查虚拟环境
    if [ -d "./venv" ]; then
        print_info "检测到虚拟环境，正在激活..."
        source ./venv/bin/activate
        PIP_CMD="./venv/bin/pip"
    else
        PIP_CMD="pip3"
        print_warning "未检测到虚拟环境，将使用系统Python环境"
    fi
    
    # 检查requirements.txt文件是否存在
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        print_error "依赖文件 $REQUIREMENTS_FILE 不存在"
        exit 1
    fi
    
    # 检查并安装缺失的包
    MISSING_PACKAGES=()
    while IFS= read -r package; do
        # 跳过空行和注释
        if [[ -z "$package" || "$package" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # 提取包名（去掉版本号）
        package_name=$(echo "$package" | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1)
        
        # 检查包是否已安装
        if ! $PIP_CMD show "$package_name" &> /dev/null; then
            MISSING_PACKAGES+=("$package")
        fi
    done < "$REQUIREMENTS_FILE"
    
    if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
        print_success "所有依赖包已安装"
    else
        print_info "发现 ${#MISSING_PACKAGES[@]} 个缺失的依赖包，正在安装..."
        
        # 安装缺失的包
        for package in "${MISSING_PACKAGES[@]}"; do
            print_info "安装: $package"
            if ! $PIP_CMD install "$package"; then
                print_error "安装失败: $package"
                exit 1
            fi
        done
        
        print_success "所有依赖包安装完成"
    fi
}

# 检查日志目录是否存在
check_logs_dir() {
    if [ ! -d "logs" ]; then
        print_warning "日志目录不存在，正在创建..."
        mkdir -p logs
        if [ $? -eq 0 ]; then
            print_success "日志目录创建成功"
        else
            print_error "无法创建日志目录"
            exit 1
        fi
    fi
}

# 启动应用
start_app() {
    print_info "正在启动 $APP_NAME..."
    
    # 检查是否已经在运行
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            print_warning "$APP_NAME 已经在运行 (PID: $PID)"
            return 0
        else
            print_warning "发现旧的PID文件，正在清理..."
            rm -f "$PID_FILE"
        fi
    fi
    
    # 安装依赖
    install_dependencies
    
    check_logs_dir
    
    # 切换到脚本所在目录
    cd "$SCRIPT_DIR"
    
    # 检查虚拟环境
    if [ -d ".venv" ]; then
        print_info "激活虚拟环境..."
        source .venv/bin/activate
    fi
    
    # 后台启动应用
    print_info "启动应用进程..."
    nohup python3 "$APP_PY" >> "$LOG_FILE" 2>&1 &
    APP_PID=$!
    
    # 保存PID到文件
    echo $APP_PID > "$PID_FILE"
    
    # 等待一下确保进程启动
    sleep 2
    
    # 检查进程是否在运行
    if ps -p $APP_PID > /dev/null 2>&1; then
        print_success "$APP_NAME 启动成功 (PID: $APP_PID)"
        print_info "日志文件: $LOG_FILE"
        print_info "PID文件: $PID_FILE"
    else
        print_error "$APP_NAME 启动失败"
        # 检查日志文件中的错误信息
        if [ -f "$LOG_FILE" ]; then
            print_info "最后10行日志:"
            tail -10 "$LOG_FILE"
        fi
        rm -f "$PID_FILE"
        exit 1
    fi
}

# 停止应用
stop_app() {
    print_info "正在停止 $APP_NAME..."
    
    if [ ! -f "$PID_FILE" ]; then
        print_warning "未找到PID文件，$APP_NAME 可能未运行"
        return 0
    fi
    
    PID=$(cat "$PID_FILE")
    
    if ps -p $PID > /dev/null 2>&1; then
        # 优雅停止
        kill $PID
        sleep 3
        
        # 检查是否停止成功
        if ps -p $PID > /dev/null 2>&1; then
            print_warning "优雅停止失败，尝试强制停止..."
            kill -9 $PID
            sleep 1
        fi
        
        if ps -p $PID > /dev/null 2>&1; then
            print_error "无法停止进程 (PID: $PID)"
            return 1
        else
            rm -f "$PID_FILE"
            print_success "$APP_NAME 已停止"
        fi
    else
        print_warning "进程不存在 (PID: $PID)，清理PID文件"
        rm -f "$PID_FILE"
    fi
}

# 重启应用
restart_app() {
    print_info "正在重启 $APP_NAME..."
    stop_app
    sleep 2
    start_app
}

# 查看应用状态
status_app() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            print_success "$APP_NAME 正在运行 (PID: $PID)"
            # 显示进程信息
            ps -p $PID -o pid,user,pcpu,pmem,etime,command
            # 显示日志文件大小
            if [ -f "$LOG_FILE" ]; then
                LOG_SIZE=$(du -h "$LOG_FILE" | cut -f1)
                print_info "日志文件大小: $LOG_SIZE"
            fi
        else
            print_warning "$APP_NAME PID文件存在但进程未运行"
            rm -f "$PID_FILE"
        fi
    else
        print_warning "$APP_NAME 未运行"
    fi
}

# 查看应用日志
logs_app() {
    if [ -f "$LOG_FILE" ]; then
        print_info "显示最后50行日志:"
        tail -50 "$LOG_FILE"
    else
        print_warning "日志文件不存在: $LOG_FILE"
    fi
}

# 实时查看日志
tail_logs() {
    if [ -f "$LOG_FILE" ]; then
        print_info "实时查看日志 (Ctrl+C 退出):"
        tail -f "$LOG_FILE"
    else
        print_warning "日志文件不存在: $LOG_FILE"
    fi
}

# 仅安装依赖
install_only() {
    install_dependencies
}

# 显示使用说明
usage() {
    echo "用法: $0 {start|stop|restart|status|logs|tail|install|help}"
    echo ""
    echo "命令说明:"
    echo "  start    - 启动应用（后台运行，自动安装依赖）"
    echo "  stop     - 停止应用"
    echo "  restart  - 重启应用"
    echo "  status   - 查看应用状态"
    echo "  logs     - 查看应用日志（最后50行）"
    echo "  tail     - 实时查看应用日志"
    echo "  install  - 仅安装依赖包"
    echo "  help     - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 install  # 安装所有依赖包"
    echo "  $0 start    # 启动应用（自动检查依赖）"
    echo "  $0 status   # 查看状态"
}

# 主函数
main() {
    case "$1" in
        start)
            start_app
            ;;
        stop)
            stop_app
            ;;
        restart)
            restart_app
            ;;
        status)
            status_app
            ;;
        logs)
            logs_app
            ;;
        tail)
            tail_logs
            ;;
        install)
            install_only
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_error "未知命令: $1"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# 检查参数
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

# 执行主函数
main "$@"