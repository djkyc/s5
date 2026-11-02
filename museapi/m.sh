cat << 'EOF' > m.sh
#!/bin/sh

# ====================================================================
#  Muse2API Serv00 (FreeBSD) 全自动一键部署与管理脚本
# ====================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="$HOME/muse2api"
BIN_PATH="$HOME/bin/muse"
PORT=28610  # 修改为你 Serv00 分配的端口

# 注册全局快捷指令
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

# 全自动安装/重装
do_install() {
    echo -e "${BLUE}=== 开始全自动拉取与配置 muse2api ===${NC}"
    
    # 如果目录存在但坏了，自动清理重建
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}[*] 检测到旧目录，正在清理旧版本...${NC}"
        OLD_PID=$(pgrep -f "python -m uvicorn app:app")
        [ -n "$OLD_PID" ] && kill -9 $OLD_PID
        rm -rf "$INSTALL_DIR"
    fi

    echo -e "${YELLOW}[*] 正在从 GitHub 官方仓库克隆源码...${NC}"
    git clone https://github.com/czg86389-hub/muse2api.git "$INSTALL_DIR"
    
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[✘] 克隆失败！请检查网络或代理连接。${NC}"
        return 1
    fi

    cd "$INSTALL_DIR" || exit 1

    # Serv00/FreeBSD 兼容：uvicorn[standard] 中的 uvloop 不支持 FreeBSD，去掉 extras
    [ -f requirements.txt ] && sed -i '' 's/uvicorn\[standard\]/uvicorn/' requirements.txt

    echo -e "${YELLOW}[*] 创建 Python 3.11 虚拟环境...${NC}"
    python3.11 -m venv venv

    echo -e "${YELLOW}[*] 正在安装 Python 依赖库...${NC}"
    . venv/bin/activate
    # Serv00 进程数受限，且 FreeBSD 没有 pydantic-core 预编译包，必须从源码编译 Rust：
    # 限制并行度，否则编译中途会报 Resource temporarily unavailable
    export CARGO_BUILD_JOBS=1
    export MAKEFLAGS="-j1"
    echo -e "${YELLOW}[!] Rust 源码编译较慢（约 30~60 分钟），请耐心等待，不要中断。${NC}"
    pip install --upgrade pip
    if pip install -r requirements.txt; then
        echo -e "${GREEN}[✔] 依赖安装成功。${NC}"
    else
        echo -e "${YELLOW}[!] 常规安装失败（Serv00 上编译 Rust 容易超出资源限制），切换到纯 Python 备用方案...${NC}"
        # 备用方案：pydantic v1 是纯 Python 包，无需 Rust 编译；
        # 已核查全仓库仅 app.py 一处用到 v2 专有 API，打一个单行兼容补丁即可
        pip install "pydantic==1.10.13"
        sed -i '' 's/req\.model_dump(by_alias=True)/req.dict(by_alias=True)/' app.py
        grep -v "^pydantic" requirements.txt > requirements.freebsd.txt
        if pip install -r requirements.freebsd.txt; then
            echo -e "${GREEN}[✔] 依赖安装成功（纯 Python 备用方案）。${NC}"
        else
            echo -e "${RED}[✘] 依赖安装失败，请把上面的报错信息贴给我看。${NC}"
            read -p "按回车键返回主菜单..." dummy
            return 1
        fi
    fi
    # 真实校验：能 import 才算成功，避免"假成功"
    if ! venv/bin/python -c "import fastapi, pydantic, uvicorn, requests; print('deps ok, pydantic', pydantic.VERSION)"; then
        echo -e "${RED}[✘] 依赖校验未通过，请把报错贴给我看。${NC}"
        read -p "按回车键返回主菜单..." dummy
        return 1
    fi

    if [ ! -f ".env" ] && [ -f ".env.example" ]; then
        cp .env.example .env
        echo -e "${GREEN}[+] 已自动生成 .env 配置文件！${NC}"
    fi

    setup_shortcut
    export PATH="$HOME/bin:$PATH"

    echo -e "${GREEN}[✔] 全自动安装与依赖配置大功告成！${NC}"
    echo -e "${GREEN}[✔] 全局快捷命令 'muse' 已成功注册。${NC}"
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 后台启动服务
do_start() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[✘] 未检测到 muse2api 目录，请先选择 1 进行安装！${NC}"
        read -p "按回车键返回主菜单..." dummy
        return
    fi

    cd "$INSTALL_DIR" || exit 1
    
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

# 停止服务
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

# 查看日志
do_logs() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[✘] 目录不存在。${NC}"
    else
        cd "$INSTALL_DIR" || exit 1
        [ -f "muse.log" ] && tail -n 30 muse.log || echo -e "${RED}[✘] 暂无日志文件。${NC}"
    fi
    echo
    read -p "按回车键返回主菜单..." dummy
}

# 编辑配置
do_config() {
    if [ ! -f "$INSTALL_DIR/.env" ]; then
        echo -e "${RED}[✘] .env 配置文件不存在！${NC}"
    else
        nano "$INSTALL_DIR/.env"
    fi
}

# 更新代码
do_update() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[✘] 目录不存在，请先安装！${NC}"
    else
        cd "$INSTALL_DIR" || exit 1
        # 记住当前走的是哪条依赖路线（v1 纯 Python 还是常规 v2），更新后保持一致
        PYDANTIC_V1=0
        if venv/bin/python -c "import pydantic, sys; sys.exit(0 if pydantic.VERSION.startswith('1.') else 1)" 2>/dev/null; then
            PYDANTIC_V1=1
        fi
        git checkout -- requirements.txt app.py 2>/dev/null
        git pull --ff-only
        # 更新后重新应用 FreeBSD 兼容修改（uvloop 不支持 FreeBSD）
        [ -f requirements.txt ] && sed -i '' 's/uvicorn\[standard\]/uvicorn/' requirements.txt
        . venv/bin/activate
        export CARGO_BUILD_JOBS=1
        export MAKEFLAGS="-j1"
        if [ "$PYDANTIC_V1" = "1" ]; then
            # 纯 Python 路线：重新打单行兼容补丁，跳过 pydantic>=2.9，避免再次触发 Rust 编译
            sed -i '' 's/req\.model_dump(by_alias=True)/req.dict(by_alias=True)/' app.py
            grep -v "^pydantic" requirements.txt > requirements.freebsd.txt
            pip install -r requirements.freebsd.txt
        else
            pip install -r requirements.txt
        fi
        echo -e "${GREEN}[✔] 代码更新完成！${NC}"
    fi
    read -p "按回车键返回主菜单..." dummy
}

# 卸载清理
do_uninstall() {
    printf "确认要彻底卸载清理吗？[y/N]: "
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
    read -p "按回车键返回主菜单..." dummy
}

setup_shortcut >/dev/null 2>&1
export PATH="$HOME/bin:$PATH"

while true; do
    clear
    echo "=========================================================="
    echo "       Muse2API Serv00 全自动一键管理控制面板             "
    echo "=========================================================="
    echo " 1. 全自动拉取源码、创建环境与安装依赖 (Install)"
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

# 赋予执行权限并同步更新全局命令
mkdir -p "$HOME/bin"
chmod +x m.sh
cp -f m.sh "$HOME/bin/muse"
chmod +x "$HOME/bin/muse"
export PATH="$HOME/bin:$PATH"

# 生成完毕，直接启动管理面板（FreeBSD 自带 sh 不支持 read -p，必须用 bash）
echo "管理脚本已就绪，正在启动控制面板..."
exec bash ./m.sh
