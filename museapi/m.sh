#!/bin/sh

# ====================================================================
#  Muse2API 多系统通用一键管理与部署脚本 (Serv00/Ubuntu/Debian)
#  Author: djkyc
# ====================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

INSTALL_DIR="$HOME/muse2api"
BIN_PATH="$HOME/bin/muse"

# 1. 自动检测系统并注册全局快捷命令 'muse'
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

    # 自动将 ~/bin 写入系统环境变量 PATH 中
    if ! echo "$PATH" | grep -q "$HOME/bin"; then
        for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            if [ -f "$rc" ]; then
                if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$rc"; then
                    echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
                fi
            fi
        done
    fi
}

# 2. 环境智能初始化检查
check_env() {
    if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}[*] 检测到 Linux (Ubuntu/Debian) 非 root 环境，将采用用户态部署...${NC}"
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}[*] 正在从 GitHub 官方仓库克隆 muse2api...${NC}"
        git clone https://github.com/czg86389-hub/muse2api.git "$INSTALL_DIR"
    fi
}

# 3. 一键安装与配置依赖（智能化）
do_install() {
    echo -e "${BLUE}=== 开始智能安装 / 配置 muse2api ===${NC}"
    check_env
    
    cd "$INSTALL_DIR" || exit 1

    # Python 虚拟环境智能检测与创建
    if [ ! -d "venv" ]; then
        echo -e "${YELLOW}[*] 创建 Python 3 虚拟环境...${NC}"
        python3 -m venv venv
    fi

    echo -e "${YELLOW}[*] 激活虚拟环境并安装/更新 Python 依赖库...${NC}"
    . venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt

    # 配置文件初始化
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            echo -e "${GREEN}[+] 已自动生成 .env 配置文件！${NC}"
        fi
    fi

    # 注册全局快捷指令
    setup_shortcut

    echo -e "${GREEN}[✔] 安装与依赖配置完成！${NC}"
    echo -e "${GREEN}[✔] 全局快捷命令 'muse' 已成功注册，以后随时输入 muse 即可调出菜单。${NC}"
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 4. 后台启动服务（兼容 screen 守护）
do_start() {
    cd "$INSTALL_DIR" || exit 1
    
    if screen -list | grep -q "muse2api"; then
        echo -e "${YELLOW}[!] 检测到 muse2api 已经在后台运行中。${NC}"
    else
        echo -e "${YELLOW}[*] 正在通过 screen 启动后台服务...${NC}"
        screen -d -m -S muse2api sh -c "cd $INSTALL_DIR && . venv/bin/activate && python app.py"
        echo -e "${GREEN}[✔] 服务已成功在后台启动（screen 会话名: muse2api）${NC}"
    fi
    
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 5. 停止服务
do_stop() {
    echo -e "${YELLOW}[*] 正在停止后台 muse2api 服务...${NC}"
    if screen -list | grep -q "muse2api"; then
        screen -S muse2api -X quit
        echo -e "${GREEN}[✔] 服务已安全停止。${NC}"
    else
        echo -e "${YELLOW}[!] 没有找到运行中的 muse2api screen 会话。${NC}"
    fi
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 6. 查看实时日志
do_logs() {
    if screen -list | grep -q "muse2api"; then
        echo -e "${BLUE}=== 进入实时日志查看界面 (退出日志请按 Ctrl+A 然后按 D) ===${NC}"
        sleep 2
        screen -r muse2api
    else
        echo -e "${RED}[✘] 当前没有运行中的 muse2api 后台进程。${NC}"
        echo
        read -p "按回车键返回主菜单..." dummy
    fi
}

# 7. 编辑配置文件
do_config() {
    if [ ! -f "$INSTALL_DIR/.env" ]; then
        echo -e "${RED}[✘] 配置文件 .env 不存在，请先执行选项 1 安装！${NC}"
    else
        echo -e "${YELLOW}[*] 打开 .env 配置文件进行编辑（使用 nano）...${NC}"
        sleep 1
        nano "$INSTALL_DIR/.env"
    fi
}

# 8. 更新代码 (Git Pull)
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

# 9. 一键完全卸载与清理程序
do_uninstall() {
    echo -e "${RED}==========================================${NC}"
    echo -e "${RED}          警告：即将完全卸载程序           ${NC}"
    echo -e "${RED}==========================================${NC}"
    echo -e "此操作将彻底清理以下内容："
    echo -e " 1. 安全终止后台运行的 screen 会话"
    echo -e " 2. 彻底删除整个项目主目录 ($INSTALL_DIR)"
    echo -e " 3. 移除全局快捷命令 (muse)"
    echo
    printf "确认要彻底卸载并删除所有数据吗？[y/N]: "
    read confirm

    case "$confirm" in
        [yY][eE][sS]|[yY])
            # 终止后台进程
            if screen -list | grep -q "muse2api"; then
                screen -S muse2api -X quit
                echo -e "${GREEN}[✔] 已终止后台 screen 进程。${NC}"
            fi

            # 删除项目目录
            if [ -d "$INSTALL_DIR" ]; then
                rm -rf "$INSTALL_DIR"
                echo -e "${GREEN}[✔] 已清除项目目录 ($INSTALL_DIR)。${NC}"
            fi

            # 删除全局快捷指令
            if [ -f "$BIN_PATH" ]; then
                rm -f "$BIN_PATH"
                echo -e "${GREEN}[✔] 已移除全局快捷命令 'muse'。${NC}"
            fi

            echo
            echo -e "${GREEN}==========================================${NC}"
            echo -e "${GREEN}       muse2api 已完全从系统中清理！      ${NC}"
            echo -e "${GREEN}==========================================${NC}"
            exit 0
            ;;
        *)
            echo -e "${YELLOW}[*] 卸载操作已取消。${NC}"
            ;;
    esac

    echo
    read -p "按回车键返回主菜单..." dummy
}

# 后台静默绑定快捷指令
setup_shortcut >/dev/null 2>&1

# 主菜单循环
while true; do
    clear
    echo "=========================================================="
    echo "                  Muse2API 管理控制面板                   "
    echo "         多系统通用一键部署 (Serv00/Ubuntu/Debian)        "
    echo "         快捷指令：muse  | Author: SerokVip指导djkyc二编  "
    echo "=========================================================="
    echo " 1. 智能化一键安装 / 配置依赖 (Install)"
    echo " 2. 启动后台服务 (Start)"
    echo " 3. 停止后台服务 (Stop)"
    echo " 4. 查看实时运行日志 (Logs)"
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
        *) echo -e "${RED}无效的选项，请重新输入！${NC}"; sleep 1 ;;
    esac
done
