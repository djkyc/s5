cat << 'EOF' > m.sh
#!/bin/sh

# ====================================================================
#  Muse2API Serv00 (FreeBSD) 专用一键管理脚本
# ====================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="$HOME/muse2api"
BIN_PATH="$HOME/bin/muse"
PORT=28610  # 修改为你Serv00分配的安全端口

setup_shortcut() {
    [ ! -d "$HOME/bin" ] && mkdir -p "$HOME/bin"
    CURRENT_SCRIPT="$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null)"
    if [ -f "$CURRENT_SCRIPT" ] && [ "$CURRENT_SCRIPT" != "$BIN_PATH" ]; then
        cp "$CURRENT_SCRIPT" "$BIN_PATH"
        chmod +x "$BIN_PATH"
    elif [ ! -f "$BIN_PATH" ] && [ -f "./m.sh" ]; then
        cp "./m.sh" "$BIN_PATH"
        chmod +x "$BIN_PATH"
    fi
    if ! echo "$PATH" | grep -q "$HOME/bin"; then
        for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            [ -f "$rc" ] && ! grep -q 'export PATH="$HOME/bin:$PATH"' "$rc" && echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
        done
    fi
}

do_install() {
    echo -e "${BLUE}=== 开始安装 / 配置 muse2api ===${NC}"
    [ ! -d "$INSTALL_DIR" ] && git clone https://github.com/czg86389-hub/muse2api.git "$INSTALL_DIR"
    cd "$INSTALL_DIR" || exit 1
    [ ! -d "venv" ] && python3.11 -m venv venv
    . venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    [ ! -f ".env" ] && [ -f ".env.example" ] && cp .env.example .env
    setup_shortcut
    echo -e "${GREEN}[✔] 安装与依赖配置完成！${NC}\n"
    read -p "按回车键返回主菜单..." dummy
}

do_start() {
    cd "$INSTALL_DIR" || exit 1
    if pgrep -f "python -m uvicorn app:app" > /dev/null; then
        echo -e "${YELLOW}[!] 检测到 muse2api 已经在后台运行中。${NC}"
    else
        echo -e "${YELLOW}正在通过 nohup 启动后台服务 (监听 127.0.0.1:$PORT)...${NC}"
        nohup venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port $PORT > muse.log 2>&1 &
        sleep 2
        if pgrep -f "python -m uvicorn app:app" > /dev/null; then
            echo -e "${GREEN}[✔] 服务已成功在后台启动！${NC}"
        else
            echo -e "${RED}[✘] 启动失败，请检查日志：${NC}"
            tail -n 15 muse.log
        fi
    fi
    echo
    read -p "按回车键返回主菜单..." dummy
}

do_stop() {
    OLD_PID=$(pgrep -f "python -m uvicorn app:app")
    if [ -n "$OLD_PID" ]; then
        kill -9 $OLD_PID
        echo -e "${GREEN}[✔] 服务已安全停止 (PID: $OLD_PID)。${NC}"
    else
        echo -e "${YELLOW}[!] 没有找到运行中的进程。${NC}"
    fi
    echo
    read -p "按回车键返回主菜单..." dummy
}

do_logs() {
    cd "$INSTALL_DIR" || exit 1
    [ -f "muse.log" ] && tail -n 30 muse.log || echo -e "${RED}[✘] 没有找到日志文件。${NC}"
    echo
    read -p "按回车键返回主菜单..." dummy
}

do_config() {
    [ ! -f "$INSTALL_DIR/.env" ] && echo -e "${RED}[✘] .env 不存在！${NC}" || nano "$INSTALL_DIR/.env"
}

do_update() {
    cd "$INSTALL_DIR" || exit 1
    git pull --ff-only
    . venv/bin/activate
    pip install -r requirements.txt
    echo -e "${GREEN}[✔] 更新完成！${NC}"
    read -p "按回车键返回主菜单..." dummy
}

do_uninstall() {
    printf "确认卸载？[y/N]: "
    read confirm
    case "$confirm" in
        [yY])
            OLD_PID=$(pgrep -f "python -m uvicorn app:app")
            [ -n "$OLD_PID" ] && kill -9 $OLD_PID
            [ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
            [ -f "$BIN_PATH" ] && rm -f "$BIN_PATH"
            echo -e "${GREEN}[✔] 已完全清理！${NC}"
            exit 0
            ;;
    esac
}

setup_shortcut >/dev/null 2>&1

while true; do
    clear
    echo "=========================================================="
    echo "            Muse2API Serv00 管理控制面板              "
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
    case "$choice" in
        1) do_install ;;
        2) do_start ;;
        3) do_stop ;;
        4) do_logs ;;
        5) do_config ;;
        6) do_update ;;
        7) do_uninstall ;;
        0) echo "再见！"; exit 0 ;;
        *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
    esac
done
EOF
