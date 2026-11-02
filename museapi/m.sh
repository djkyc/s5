cat << 'EOF' > install.sh
#!/bin/bash

# 颜色定义
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

USERNAME=$(whoami)
HOSTNAME=$(hostname)
APP_DIR="$HOME/muse2api"

# 自动识别平台 (Serv00 或 ct8)
if [[ "$HOSTNAME" == *"ct8"* ]] || [ -d "/home/ct8" ] || command -v ct8 &>/dev/null; then
    PLATFORM="ct8"
    DOMAIN="muse.${USERNAME}.ct8.pl"
else
    PLATFORM="serv00"
    DOMAIN="muse.${USERNAME}.serv00.net"
fi

show_banner() {
    clear
    echo -e "${CYAN}==================================================${RESET}"
    echo -e "${CYAN}       Muse2API 管理面板 (Bykyc 专属定制版)       ${RESET}"
    echo -e "${CYAN}==================================================${RESET}"
    echo -e " 当前平台: ${GREEN}${PLATFORM^^}${RESET} | 用户: ${GREEN}${USERNAME}${RESET}"
    echo -e " 专属域名: ${YELLOW}http://$DOMAIN${RESET}"
    echo -e "${CYAN}--------------------------------------------------${RESET}"
    echo " 1. 全新安装 / 覆盖重置并启动服务 (清理旧文件)"
    echo " 2. 启动 / 重启服务"
    echo " 3. 停止服务"
    echo " 4. 查看实时运行日志 (muse.log)"
    echo " 5. 卸载并彻底清除所有文件"
    echo " 0. 退出脚本"
    echo -e "${CYAN}==================================================${RESET}"
}

clean_old_files() {
    echo -e "${YELLOW}>>> 正在检测并清理旧版本残留及进程...${RESET}"
    pkill -f "uvicorn app:app" 2>/dev/null
    if [ -d "$APP_DIR" ]; then
        # 保留用户可能的配置或直接全清（这里按要求清除旧文件重来）
        rm -rf "$APP_DIR"
        echo ">>> 旧目录 $APP_DIR 及残留文件已彻底清除。"
    fi
}

do_install() {
    clean_old_files
    
    echo -e "${GREEN}>>> [1/5] 正在创建全新工作目录...${RESET}"
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"

    echo -e "${GREEN}>>> [2/5] 正在寻找未被占用的空闲端口...${RESET}"
    PORT=18610
    while netstat -an 2>/dev/null | grep -q ":$PORT "; do
        PORT=$((PORT + 1))
    done
    echo ">>> 已自动分配空闲端口: $PORT"

    echo -e "${GREEN}>>> [3/5] 正在配置 Python 3.11 虚拟环境...${RESET}"
    python3.11 -m venv venv || python3 -m venv venv
    . venv/bin/activate
    pip install --upgrade pip
    pip install fastapi uvicorn pydantic requests playwright

    echo -e "${GREEN}>>> [4/5] 正在启动后端服务 (Bykyc 守护中)...${RESET}"
    nohup venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port "$PORT" > muse.log 2>&1 &
    echo ">>> 服务已在后台成功运行，PID: $!"

    echo -e "${GREEN}>>> [5/5] 正在自动配置 $PLATFORM 面板反向代理...${RESET}"
    devil www add "$DOMAIN" proxy 127.0.0.1 "$PORT" 2>/dev/null

    echo -e "\n${GREEN}🎉 [Bykyc] 安装与部署全部完成！${RESET}"
    echo -e "👉 访问地址: ${YELLOW}http://$DOMAIN${RESET}"
    echo -e "👉 监听端口: ${YELLOW}$PORT${RESET}"
    read -p "按回车键返回主菜单..."
}

do_start() {
    if [ ! -d "$APP_DIR" ]; then
        echo -e "${RED}❌ 未检测到安装目录，请先选择 1 进行全新安装！${RESET}"
        read -p "按回车键返回主菜单..."
        return
    fi
    cd "$APP_DIR"
    pkill -f "uvicorn app:app" 2>/dev/null
    
    # 读取或者寻找端口
    PORT=18610
    if [ -f "muse.log" ]; then
        # 尝试从日志中提取上次的端口或重新扫
        PORT=18610
    fi
    while netstat -an 2>/dev/null | grep -q ":$PORT "; do
        PORT=$((PORT + 1))
    done

    . venv/bin/activate
    nohup venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port "$PORT" > muse.log 2>&1 &
    echo -e "${GREEN}🚀 服务已启动！端口: $PORT，日志文件: muse.log${RESET}"
    read -p "按回车键返回主菜单..."
}

do_stop() {
    pkill -f "uvicorn app:app" 2>/dev/null
    echo -e "${YELLOW}🛑 后端服务已停止。${RESET}"
    read -p "按回车键返回主菜单..."
}

do_logs() {
    if [ ! -f "$APP_DIR/muse.log" ]; then
        echo -e "${RED}❌ 暂无日志文件。${RESET}"
        read -p "按回车键返回主菜单..."
        return
    }
    echo -e "${CYAN}--- 正在查看实时日志 (按 Ctrl+C 退出查看) ---${RESET}"
    tail -f "$APP_DIR/muse.log"
}

do_uninstall() {
    echo -e "${RED}⚠️ 警告：这会彻底删除 muse2api 的所有文件、日志及配置！${RESET}"
    read -p "确认要卸载并清除吗？(y/n): " confirm
    if [ "$confirm" == "y" ]; then
        pkill -f "uvicorn app:app" 2>/dev/null
        rm -rf "$APP_DIR"
        # 尝试在面板中删除域名反代
        devil www del "$DOMAIN" 2>/dev/null
        echo -e "${GREEN}🗑️ 已彻底卸载并清除干净。${RESET}"
    fi
    read -p "按回车键返回主菜单..."
}

# 主循环
while true; do
    show_banner
    read -p "请选择操作编号 [0-5]: " choice
    case $choice in
        1) do_install ;;
        2) do_start ;;
        3) do_stop ;;
        4) do_logs ;;
        5) do_uninstall ;;
        0) echo "再见！"; exit 0 ;;
        *) echo -e "${RED}无效输入，请重新选择！${RESET}"; sleep 1 ;;
    esac
done
EOF

chmod +x install.sh
./install.sh
