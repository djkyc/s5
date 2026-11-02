cat << 'EOF' > m.sh
#!/bin/sh

# ====================================================================
#  Muse2API Serv00 / ct8 (FreeBSD) 全自动一键部署与管理脚本By:Djkyc
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

# pydantic v1 兼容补丁：把上游的 v2 专有 API 转成 v1 写法（幂等，可重复执行）
apply_v1_patch() {
    venv/bin/python - <<'PYEOF'
import re
p = 'app.py'
s = open(p).read()
s = s.replace(
    "from pydantic import BaseModel, Field, SecretStr, field_validator",
    "from pydantic import BaseModel, Field, SecretStr, validator")
s = re.sub(r'@field_validator\(([^)]*)\)\n\s*@classmethod', r'@validator(\1)', s)
s = s.replace("req.model_dump(by_alias=True)", "req.dict(by_alias=True)")
open(p, 'w').write(s)
print("v1 patch applied")
PYEOF
    if grep -q "field_validator" app.py; then
        echo -e "${YELLOW}[!] 警告：app.py 中仍有 field_validator 残留，启动可能失败，请把情况告诉我。${NC}"
    fi
}

# 查找正在运行的 muse2api 进程 PID（排除僵尸进程，避免把已死的进程误判为运行中）
muse_pids() {
    for p in $(pgrep -f "uvicorn app:app" 2>/dev/null); do
        ps -o pid,stat -p "$p" 2>/dev/null | awk 'NR==2 && $2 !~ /^Z/ {print $1}'
    done
}

# 按主机名自动识别运行商（Serv00 / ct8），决定默认域名后缀与面板地址
detect_provider() {
    HOSTNAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null)
    case "$HOSTNAME" in
        *ct8.pl*)
            PROVIDER="ct8"; SUFFIX="ct8.pl"; PANEL="https://panel.ct8.pl" ;;
        *serv00.com*)
            PROVIDER="serv00"; SUFFIX="serv00.net"; PANEL="https://panel.serv00.com" ;;
        *)
            PROVIDER="serv00"; SUFFIX="serv00.net"; PANEL="https://panel.serv00.com"
            echo -e "${YELLOW}[!] 无法识别主机（$HOSTNAME），默认按 Serv00 处理。${NC}" ;;
    esac
}

# 全自动安装/重装
do_install() {
    echo -e "${BLUE}=== 开始全自动拉取与配置 muse2api ===${NC}"
    
    # 如果目录存在但坏了，自动清理重建
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}[*] 检测到旧目录，正在清理旧版本...${NC}"
        PIDS=$(muse_pids)
        [ -n "$PIDS" ] && kill -9 $PIDS
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
    pip install --upgrade pip
    if [ "$(uname -s)" = "FreeBSD" ]; then
        # FreeBSD/Serv00 专用路线：PyPI 没有 pydantic-core 的 FreeBSD 预编译包，
        # 而 Serv00 上从源码编译 Rust（maturin/pydantic-core）必定耗尽进程数或内存，
        # 已多次验证失败，因此直接使用纯 Python 组合，彻底跳过 Rust 编译：
        #   - pydantic 1.10.13（纯 Python，无 Rust 组件）
        #   - fastapi 0.121.0（最后一个兼容 pydantic v1 的版本；更新版强制要求 pydantic>=2.9）
        # 已核查全仓库仅 app.py 一处用到 pydantic v2 专有 API，打一个单行兼容补丁即可。
        echo -e "${YELLOW}[*] FreeBSD 环境，采用纯 Python 依赖组合（跳过 Rust 编译）...${NC}"
        pip install "pydantic==1.10.13" || { echo -e "${RED}[✘] pydantic 安装失败，请把报错贴给我看。${NC}"; read -p "按回车键返回主菜单..." dummy; return 1; }
        apply_v1_patch
        printf 'fastapi==0.121.0\nuvicorn>=0.32\nrequests>=2.32\nwebsocket-client>=1.8\npython-multipart>=0.0.9\n' > requirements.freebsd.txt
        if pip install -r requirements.freebsd.txt; then
            echo -e "${GREEN}[✔] 依赖安装成功（纯 Python 组合）。${NC}"
        else
            echo -e "${RED}[✘] 依赖安装失败，请把上面的报错信息贴给我看。${NC}"
            read -p "按回车键返回主菜单..." dummy
            return 1
        fi
    else
        if ! pip install -r requirements.txt; then
            echo -e "${RED}[✘] 依赖安装失败，请把上面的报错信息贴给我看。${NC}"
            read -p "按回车键返回主菜单..." dummy
            return 1
        fi
        echo -e "${GREEN}[✔] 依赖安装成功。${NC}"
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

    # 端口优先使用 .env 中的 MUSE2API_PORT（选项2向导写入），回退到脚本默认值
    ENV_PORT=$(grep -E '^MUSE2API_PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d ' \r')
    [ -n "$ENV_PORT" ] && PORT="$ENV_PORT"

    RUN_PID=$(muse_pids)
    if [ -n "$RUN_PID" ]; then
        echo -e "${YELLOW}[!] 检测到 muse2api 已经在后台运行中 (PID: $RUN_PID)。${NC}"
    else
        echo -e "${YELLOW}[*] 正在通过 nohup 启动后台服务 (监听 127.0.0.1:$PORT)...${NC}"
        nohup venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port $PORT > muse.log 2>&1 &
        sleep 2
        
        if [ -n "$(muse_pids)" ]; then
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
    OLD_PID=$(muse_pids)
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

# 一键配置向导：Serv00 端口 + 反向代理域名 + 密钥，自动写入 .env
do_setup() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[✘] 请先选择 1 安装！${NC}"
        read -p "按回车键返回主菜单..." dummy
        return
    fi
    cd "$INSTALL_DIR" || exit 1
    LOGIN=$(whoami)
    detect_provider

    echo -e "${BLUE}=== 一键配置向导 ===${NC}"
    echo -e "${GREEN}已识别服务器：$PROVIDER（面板 $PANEL）${NC}"

    # ---- 1. 端口：优先复用已预留的 TCP 端口，没有则自动申请 ----
    echo -e "${YELLOW}[1/5] 检测 $PROVIDER 预留 TCP 端口...${NC}"
    TCP_PORT=$(devil port list 2>/dev/null | grep -i "tcp" | head -1 | grep -o '[0-9]\+' | head -1)
    if [ -z "$TCP_PORT" ]; then
        echo -e "${YELLOW}未发现预留端口，正在自动申请...${NC}"
        for _ in $(seq 1 8); do
            P=$((RANDOM % 40001 + 20000))
            OUT=$(devil port add $P tcp muse2api 2>&1)
            echo "$OUT" | grep -qi "ok\|success" && { TCP_PORT=$P; break; }
            OUT=$(devil port add tcp $P muse2api 2>&1)
            echo "$OUT" | grep -qi "ok\|success" && { TCP_PORT=$P; break; }
        done
    fi
    if [ -z "$TCP_PORT" ]; then
        printf "自动申请失败，请输入已在面板预留的 TCP 端口: "
        read TCP_PORT
    fi
    echo -e "${GREEN}使用 TCP 端口: $TCP_PORT${NC}"

    # ---- 2. 反向代理域名 ----
    echo -e "${YELLOW}[2/5] 配置反向代理域名...${NC}"
    DOMAIN="muse.$LOGIN.$SUFFIX"
    printf "域名（回车使用默认 %s）: " "$DOMAIN"
    read IN_DOMAIN
    [ -n "$IN_DOMAIN" ] && DOMAIN="$IN_DOMAIN"
    DOMAIN_OK=0
    if devil www list 2>/dev/null | grep -q "$DOMAIN"; then
        echo -e "${GREEN}域名 $DOMAIN 已存在，跳过创建。${NC}"
        DOMAIN_OK=1
    else
        OUT=$(devil www add "$DOMAIN" proxy localhost "$TCP_PORT" 2>&1)
        RC=$?
        if [ $RC -eq 0 ] || echo "$OUT" | grep -qi "ok\|success\|added"; then
            echo -e "${GREEN}已创建代理域名: $DOMAIN -> 127.0.0.1:$TCP_PORT${NC}"
            devil www options "$DOMAIN" sslonly on >/dev/null 2>&1 && echo -e "${GREEN}已开启强制 HTTPS。${NC}"
            DOMAIN_OK=1
        else
            echo -e "${RED}[!] 域名自动创建失败：${NC}"
            echo "$OUT" | head -5
            echo -e "${YELLOW}请稍后在 Serv00 面板手动添加 Proxy 类型网站：域名 $DOMAIN，目标 127.0.0.1:$TCP_PORT${NC}"
        fi
    fi

    # ---- SSL 证书：muse.xxx.serv00.net 这类两级子域名盖不住 Serv00 的共享通配符证书，
    #      没有专属证书浏览器会一直报不安全；已有则跳过，没有就自动签一张 Let's Encrypt（免费、自动续期）
    if [ "$DOMAIN_OK" = "1" ]; then
        echo -e "${YELLOW}[*] 检查 $DOMAIN 的 SSL 证书...${NC}"
        if devil ssl www list 2>/dev/null | grep -q "$DOMAIN"; then
            echo -e "${GREEN}域名 $DOMAIN 已有专属 SSL 证书，跳过签发。${NC}"
        else
            # 刚创建的域名 DNS 可能还没生效，等待重试最多约 1 分钟
            CERT_IP=""
            for _try in $(seq 1 6); do
                CERT_IP=$(python3 -c "import socket;print(socket.gethostbyname('$DOMAIN'))" 2>/dev/null)
                [ -n "$CERT_IP" ] && break
                echo -e "${YELLOW}等待域名 DNS 生效，重试 $_try/6...${NC}"
                sleep 10
            done
            if [ -z "$CERT_IP" ]; then
                echo -e "${YELLOW}[!] 域名 $DOMAIN 解析失败，跳过自动签发（可稍后在面板 SSL → WWW websites 中手动签发）。${NC}"
            else
                echo -e "${YELLOW}[*] 正在为 $DOMAIN 签发专属证书...${NC}"
                OUT=$(devil ssl www add "$CERT_IP" le le "$DOMAIN" 2>&1)
                if echo "$OUT" | grep -qi "ok\|success"; then
                    echo -e "${GREEN}[+] SSL 证书签发成功，1-2 分钟后浏览器将显示绿锁。${NC}"
                else
                    echo -e "${YELLOW}[!] 自动签发失败，可稍后在面板 SSL → WWW websites 中手动签发：${NC}"
                    echo "$OUT" | head -3
                fi
            fi
        fi
    fi

    # ---- 3. API 密钥 ----
    echo -e "${YELLOW}[3/5] API 密钥 (MUSE2API_KEY)...${NC}"
    echo "  g      = 现在就自动生成一个高强度密钥（推荐）"
    echo "  回车    = 留空，首次启动时由程序自动生成并打印到日志"
    echo "  或直接输入你的密钥（需以 m2a_ 开头）"
    printf "请选择 [g/回车/输入密钥]: "
    read API_KEY
    KEY_GEN=0
    case "$API_KEY" in
        [gG])
            API_KEY="m2a_$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))' 2>/dev/null || od -An -tx1 -N24 /dev/urandom 2>/dev/null | tr -d ' \n')"
            KEY_GEN=1
            echo -e "${GREEN}已生成密钥: $API_KEY${NC}"
            ;;
        ""|m2a_*) ;;
        *)
            echo -e "${YELLOW}[!] 密钥建议以 m2a_ 开头，仍将按原样写入。${NC}"
            ;;
    esac

    # ---- 4. 写入 .env ----
    echo -e "${YELLOW}[4/5] 写入 .env 配置文件...${NC}"
    [ -f .env ] && cp .env ".env.bak.$(date +%Y%m%d%H%M%S)"
    PUBLIC_BASE=""
    [ "$DOMAIN_OK" = "1" ] && PUBLIC_BASE="https://$DOMAIN"
    cat > .env <<CFGEOF
MUSE2API_KEY=$API_KEY
MUSE2API_HOST=127.0.0.1
MUSE2API_PORT=$TCP_PORT
MUSE2API_PUBLIC_BASE=$PUBLIC_BASE
MUSE2API_CHROMIUM=/usr/bin/chromium
MUSE2API_CDP_PORT=19210
MUSE2API_IMAGE_TIMEOUT=240
MUSE2API_VIDEO_TIMEOUT=600
MUSE2API_CHAT_TIMEOUT=300
MUSE2API_CONCURRENCY=2
MUSE2API_KEEPALIVE_DISABLED_ACCOUNTS=0
MUSE2API_REF_IMAGE_LOCAL_FILES=0
MUSE2API_REF_IMAGE_PRIVATE_FETCH=0
CFGEOF
    echo -e "${GREEN}[+] .env 已生成（旧文件已备份为 .env.bak.*）。${NC}"

    # 记录本次向导创建/使用的资源，供选项7彻底卸载时清理
    {
        [ "$DOMAIN_OK" = "1" ] && echo "DOMAIN=$DOMAIN"
        echo "PORT=$TCP_PORT"
    } > "$HOME/.muse2api_meta"

    # ---- 5. binexec（Chromium 这类自带二进制需要） ----
    echo -e "${YELLOW}[5/5] 开启二进制执行权限...${NC}"
    devil binexec on >/dev/null 2>&1 \
        && echo -e "${GREEN}[+] binexec 已开启。${NC}" \
        || echo -e "${YELLOW}[!] binexec 开启失败，可稍后在面板手动开启。${NC}"

    echo
    echo -e "${GREEN}=== 配置完成 ===${NC}"
    [ "$DOMAIN_OK" = "1" ] && echo -e "  访问地址: https://$DOMAIN"
    echo -e "  监听端口: 127.0.0.1:$TCP_PORT"
    if [ "$KEY_GEN" = "1" ]; then
        echo -e "  API 密钥: $API_KEY（已写入 .env，请妥善保存，调用 API 时需要它）"
    elif [ -z "$API_KEY" ]; then
        echo -e "  API 密钥: 首次启动后自动生成，请用选项 5 查看日志获取"
    fi
    if [ -n "$(muse_pids)" ]; then
        echo -e "  ${YELLOW}服务正在运行，新配置需重启生效（选 4 停止，再选 3 启动）。${NC}"
    else
        if [ "$DOMAIN_OK" = "1" ]; then
            echo -e "  ${RED}下一步: 先选择 3 启动服务，启动成功后再用浏览器打开 https://$DOMAIN${NC}"
        else
            echo -e "  ${RED}下一步: 先选择 3 启动服务${NC}"
        fi
    fi
    echo
    printf "需要手动微调 .env 吗？[y/N]: "
    read TWEAK
    case "$TWEAK" in
        [yY]*) nano .env ;;
    esac
    read -p "按回车键返回主菜单..." dummy
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
            # 纯 Python 路线：重新打 v1 兼容补丁；fastapi 钉在 0.121.0（最后一个兼容 pydantic v1 的版本）
            apply_v1_patch
            printf 'fastapi==0.121.0\nuvicorn>=0.32\nrequests>=2.32\nwebsocket-client>=1.8\npython-multipart>=0.0.9\n' > requirements.freebsd.txt
            pip install -r requirements.freebsd.txt
        else
            pip install -r requirements.txt
        fi
        echo -e "${GREEN}[✔] 代码更新完成！${NC}"
    fi
    read -p "按回车键返回主菜单..." dummy
}

# 卸载清理（含向导创建的域名与端口）
do_uninstall() {
    echo -e "${YELLOW}[!] 将删除：程序目录、浏览器配置(muse2api-profiles，含账号登录态)、相关脚本。${NC}"
    printf "确认要彻底卸载清理吗？[y/N]: "
    read confirm
    case "$confirm" in
        [yY]) ;;
        *) read -p "按回车键返回主菜单..." dummy; return ;;
    esac

    # 向导创建的代理域名与预留端口（记录在 ~/.muse2api_meta；无记录时回退探测）
    detect_provider
    DEL_DOMAIN=""; DEL_PORT=""
    if [ -f "$HOME/.muse2api_meta" ]; then
        . "$HOME/.muse2api_meta"
        DEL_DOMAIN="$DOMAIN"; DEL_PORT="$PORT"
    else
        DEF_DOMAIN="muse.$(whoami).$SUFFIX"
        devil www list 2>/dev/null | grep -q "$DEF_DOMAIN" && DEL_DOMAIN="$DEF_DOMAIN"
        [ -f "$INSTALL_DIR/.env" ] && DEL_PORT=$(grep -E '^MUSE2API_PORT=' "$INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d ' \r')
    fi
    if [ -n "$DEL_DOMAIN" ] || [ -n "$DEL_PORT" ]; then
        echo -e "${YELLOW}检测到向导创建的资源：${NC}"
        [ -n "$DEL_DOMAIN" ] && echo -e "  代理域名: $DEL_DOMAIN"
        [ -n "$DEL_PORT" ] && echo -e "  预留端口: $DEL_PORT (TCP)"
        printf "是否一并删除？[y/N]: "
        read del_confirm
        case "$del_confirm" in
            [yY])
                if [ -n "$DEL_DOMAIN" ]; then
                    devil www del "$DEL_DOMAIN" >/dev/null 2>&1 \
                        && echo -e "${GREEN}已删除代理域名 $DEL_DOMAIN${NC}" \
                        || echo -e "${YELLOW}域名删除失败或不存在。${NC}"
                fi
                if [ -n "$DEL_PORT" ]; then
                    devil port del tcp "$DEL_PORT" >/dev/null 2>&1 \
                        && echo -e "${GREEN}已释放 TCP 端口 $DEL_PORT${NC}" \
                        || echo -e "${YELLOW}端口释放失败或不存在。${NC}"
                fi
                ;;
        esac
        rm -f "$HOME/.muse2api_meta"
    fi

    PIDS=$(muse_pids)
    [ -n "$PIDS" ] && kill -9 $PIDS
    [ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
    [ -f "$BIN_PATH" ] && rm -f "$BIN_PATH"
    [ -f "$HOME/m.sh" ] && rm -f "$HOME/m.sh"
    [ -f "$HOME/setup-muse.sh" ] && rm -f "$HOME/setup-muse.sh"
    [ -d "$HOME/muse2api-profiles" ] && rm -rf "$HOME/muse2api-profiles"
    echo -e "${GREEN}[✔] 已完全清理！${NC}"
    exit 0
}

setup_shortcut >/dev/null 2>&1
export PATH="$HOME/bin:$PATH"

while true; do
    clear
    echo "=========================================================="
    echo "       Muse2API Serv00/ct8 全自动一键管理控制面板By:Djkyc   "
    echo "=========================================================="
    echo " 1. 全自动拉取源码、创建环境与安装依赖 (Install)"
    echo " 2. 一键配置：端口/代理域名/密钥 (.env 向导)"
    echo " 3. 后台启动服务 (Start)"
    echo " 4. 停止后台服务 (Stop)"
    echo " 5. 查看最新运行日志 (Logs)"
    echo " 6. 检查并拉取最新源码 (Git Pull)"
    echo " 7. 一键完全卸载与清理 (Uninstall)"
    echo " 0. 退出脚本 (Exit)"
    echo "=========================================================="
    printf "请输入选项 [0-7]: "
    read choice
    case "$choice" in
        1) do_install ;;
        2) do_setup ;;
        3) do_start ;;
        4) do_stop ;;
        5) do_logs ;;
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
