#!/bin/sh

# ====================================================================
#  Muse2API Serv00 (FreeBSD) 专用一键管理脚本
# ====================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

INSTALL_DIR="$HOME/muse2api"
BIN_PATH="$HOME/bin/muse"
PORT=28610  # 修改为你Serv00分配的安全高位端口

# 1. 自动检测并注册全局快捷命令 'muse'
setup_shortcut() {
    if [ ! -d "$HOME/bin" ]; then
        mkdir -p "$HOME/bin"
    fi

    CURRENT_SCRIPT="$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null)"
    
    if [ -f "$CURRENT_SCRIPT" ] && [ "$CURRENT_SCRIPT" != "$BIN_PATH" ]; then
        cp "$CURRENT_SCRIPT" "$BIN_PATH"
        chmod +x "$BIN_PATH"
    elif [ ! -f "$BIN_PATH" ] && [ -f "./m.sh" ]; then
        cp "./m.sh" "$BIN_PATH"
        chmod +x "$BIN_PATH"
    fi

    if ! echo "$PATH" \vert{} grep -q "$HOME/bin"; then
        for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            if [ -f "$rc" ]; then
                if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$rc"; then
                    echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
                fi
            fi
        done
    fi
}

# 2. 一键安装与配置依赖
do_install() {
    echo -e "${BLUE}=== 开始安装 / 配置 muse2api ===${NC}"
    
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}[*] 正在从 GitHub 官方仓库克隆 muse2api...${NC}"
        git clone https://github.com/czg86389-hub/muse2api.git "$INSTALL_DIR"
    fi
    
    cd "$INSTALL_DIR" || exit 1

    if [ ! -d "venv" ]; then
        echo -e "${YELLOW}[*] 创建 Python 虚拟环境...${NC}"
        python3.11 -m venv venv
    fi

    echo -e "${YELLOW}[*] 激活虚拟环境并安装/更新 Python 依赖库...${NC}"
    . venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt

    if [ ! -f ".env" ] && [ -f ".env.example" ]; then
        cp .env.example .env
        echo -e "${GREEN}[+] 已自动生成 .env 配置文件！${NC}"
    fi

    setup_shortcut

    echo -e "${GREEN}[✔] 安装与依赖配置完成！${NC}"
    echo -e "${GREEN}[✔] 全局快捷命令 'muse' 已成功注册。${NC}"
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 3. 后台启动服务（完美适配 Serv00 的 nohup 守护，避开 screen 兼容问题）
do_start() {
    cd "$INSTALL_DIR" || exit 1
    
    # 检查进程是否已经在运行
    if pgrep -f "python -m uvicorn app:app" > /dev/null; then
        echo -e "${YELLOW}[!] 检测到 muse2api 已经在后台运行中。${NC}"
    else
        echo -e "${YELLOW}[*] 正在通过 nohup 启动后台服务 (监听 127.0.0.1:$PORT)...${NC}"
        nohup venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port $PORT > muse.log 2>&1 &
        sleep 2
        
        if pgrep -f "python -m uvicorn app:app" > /dev/null; then
            echo -e "${GREEN}[✔] 服务已成功在后台启动！日志已写入 muse.log${NC}"
        else
            echo -e "${RED}[✘] 启动失败！请检查 muse.log 日志内容：${NC}"
            tail -n 15 muse.log
        fi
    fi
    
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 4. 停止服务
do_stop() {
    echo -e "${YELLOW}[*] 正在停止后台 muse2api 服务...${NC}"
    OLD_PID=$(pgrep -f "python -m uvicorn app:app")
    if [ -n "$OLD_PID" ]; then
        kill -9 $OLD_PID
        echo -e "${GREEN}[✔] 服务已安全停止 (PID: $OLD_PID)。${NC}"
    else
        echo -e "${YELLOW}[!] 没有找到运行中的 muse2api 进程。${NC}"
    fi
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 5. 查看实时日志
do_logs() {
    cd "$INSTALL_DIR" || exit 1
    if [ -f "muse.log" ]; then
        echo -e "${BLUE}=== 查看最新 30 行运行日志 (按 Ctrl+C 退出) ===${NC}"
        tail -n 30 muse.log
    else
        echo -e "${RED}[✘] 没有找到 muse.log 日志文件。${NC}"
    fi
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 6. 编辑配置文件
do_config() {
    if [ ! -f "$INSTALL_DIR/.env" ]; then
        echo -e "${RED}[✘] 配置文件 .env 不存在，请先执行选项 1 安装！${NC}"
    else
        nano "$INSTALL_DIR/.env"
    fi
}

# 7. 更新代码 (Git Pull)
do_update() {
    cd "$INSTALL_DIR" || exit 1
    echo -e "${YELLOW}[*] 正在从 GitHub 拉取最新源码 (git pull)...${NC}"
    git pull --ff-only
    
    echo -e "${YELLOW}[*] 正在更新 Python 依赖...${NC}"
    . venv/bin/activate
    pip install -r requirements.txt
    
    echo -e "${GREEN}[✔] 代码更新完成！建议随后重启服务。${NC}"
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 8. 彻底卸载清理
do_uninstall() {
    printf "确认要彻底卸载并删除所有数据吗？[y/N]: "
    read confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            OLD_PID=$(pgrep -f "python -m uvicorn app:app")
            [ -n "$OLD_PID" ] && kill -9 $OLD_PID
            [ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
            [ -f "$BIN_PATH" ] && rm -f "$BIN_PATH"
            echo -e "${GREEN}[✔] 已完全清理！${NC}"
            exit 0
            ;;
        *)
            echo -e "${YELLOW}[*] 卸载已取消。${NC}"
            ;;
    esac
    read -p "按回车键返回主菜单..." dummy
}

setup_shortcut >/dev/null 2>&1

# 主菜单循环
while true; do
    clear
    echo "=========================================================="
    echo "            Muse2API Serv00 管理控制面板              "
    echo "            快捷指令：muse  | 适配 FreeBSD 环境           "
    echo "=========================================================="
    echo " 1. 智能化一键安装 / 配置依赖 (Install)"
    echo " 2. 后台启动服务 (Start)"
    echo " 3. 停止后台服务 (Stop)"
    echo " 4. 查看最新运行日志 (Logs)"
    echo " 5. 修改配置文件 (.env)"
    echo " 6. 检查并拉取最新源码 (Git Pull)"
    echo " 7. 一键完全卸载与清理 (Uninstall)"
    echo " 0. 退出脚本 (Exit)"
    echo "=========================================================="
    printf "请输入选项 [0-7]: "
    read choice
