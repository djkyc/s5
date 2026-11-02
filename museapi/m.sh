#!/bin/sh

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

INSTALL_DIR="$HOME/muse2api"

# 检查是否在 Serv00 / FreeBSD 环境
check_env() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}[*] 检测到尚未克隆项目，正在从 GitHub 克隆 muse2api...${NC}"
        git clone https://github.com/czg86389-hub/muse2api.git "$INSTALL_DIR"
    fi
}

# 1. 一键安装与配置
do_install() {
    echo -e "${BLUE}=== 开始安装/配置 muse2api ===${NC}"
    check_env
    
    cd "$INSTALL_DIR" || exit 1

    # 检查 Python 虚拟环境
    if [ ! -d "venv" ]; then
        echo -e "${YELLOW}[*] 创建 Python 3 虚拟环境...${NC}"
        python3 -m venv venv
    fi

    echo -e "${YELLOW}[*] 激活虚拟环境并安装依赖...${NC}"
    . venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt

    # 配置文件处理
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            echo -e "${GREEN}[+] 已自动生成 .env 配置文件，请在配置菜单中修改端口和密钥。${NC}"
        fi
    fi

    echo -e "${GREEN}[✔] 安装与依赖配置完成！${NC}"
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 2. 启动服务（通过 screen 后台运行）
do_start() {
    cd "$INSTALL_DIR" || exit 1
    
    # 检查是否已经在 screen 中运行
    if screen -list | grep -q "muse2api"; then
        echo -e "${YELLOW}[!] 检测到 muse2api 已经在 screen 会话中运行中。${NC}"
    else
        echo -e "${YELLOW}[*] 正在通过 screen 启动服务...${NC}"
        screen -d -m -S muse2api sh -c "cd $INSTALL_DIR && . venv/bin/activate && python app.py"
        echo -e "${GREEN}[✔] 服务已在后台启动（screen 会话名: muse2api）${NC}"
    fi
    
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 3. 停止服务
do_stop() {
    echo -e "${YELLOW}[*] 正在停止后台 muse2api 服务...${NC}"
    if screen -list | grep -q "muse2api"; then
        screen -S muse2api -X quit
        echo -e "${GREEN}[✔] 服务已停止。${NC}"
    else
        echo -e "${YELLOW}[!] 没有找到运行中的 muse2api screen 会话。${NC}"
    fi
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 4. 查看实时日志
do_logs() {
    if screen -list | grep -q "muse2api"; then
        echo -e "${BLUE}=== 正在进入 screen 日志查看界面 (退出请按 Ctrl+A 然后按 D) ===${NC}"
        sleep 2
        screen -r muse2api
    else
        echo -e "${RED}[✘] 当前没有运行中的 muse2api 后台进程。${NC}"
        echo
        read -p "按回车键返回主菜单..." dummy
    fi
}

# 5. 编辑配置文件
do_config() {
    if [ ! -f "$INSTALL_DIR/.env" ]; then
        echo -e "${RED}[✘] 配置文件 .env 不存在，请先执行安装！${NC}"
    else
        echo -e "${YELLOW}[*] 打开 .env 配置文件（使用 nano 编辑）...${NC}"
        sleep 1
        nano "$INSTALL_DIR/.env"
    fi
}

# 6. 更新代码 (git pull)
do_update() {
    cd "$INSTALL_DIR" || exit 1
    echo -e "${YELLOW}[*] 正在从 GitHub 拉取最新代码...${NC}"
    git pull --ff-only
    
    echo -e "${YELLOW}[*] 更新 Python 依赖...${NC}"
    . venv/bin/activate
    pip install -r requirements.txt
    
    echo -e "${GREEN}[✔] 代码更新完成！建议重启服务。${NC}"
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 主菜单循环
while true; do
    clear
    echo "=========================================="
    echo "      Muse2API Serv00 管理交互菜单       "
    echo "=========================================="
    echo " 1. 一键安装 / 配置依赖 (Install)"
    echo " 2. 启动后台服务 (Start)"
    echo " 3. 停止后台服务 (Stop)"
    echo " 4. 查看实时运行日志 (Logs)"
    echo " 5. 修改配置文件 (.env)"
    echo " 6. 在线更新源码 (Git Pull)"
    echo " 0. 退出脚本 (Exit)"
    echo "=========================================="
    printf "请输入选项 [0-6]: "
    read choice

    case "$choice" in
        1) do_install ;;
        2) do_start ;;
        3) do_stop ;;
        4) do_logs ;;
        5) do_config ;;
        6) do_update ;;
        0) echo "再见！"; exit 0 ;;
        *) echo -e "${RED}无效的选项，请重新输入！${NC}"; sleep 1 ;;
    esac
done
