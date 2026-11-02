#!/bin/bash

# ---------------- 带动画的执行函数 ----------------
X() {
    local Y=$1
    local CMD=$2
    local O=("▖" "▘" "▝" "▗")
    local i=0

    printf "[ ] %s" "$Y"
    eval "$CMD" > >(tee /tmp/cmd_output.log) 2>&1 &
    local PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        printf "\r[%s] %s" "${O[i]}" "$Y"
        i=$(( (i + 1) % 4 ))
        sleep 0.1
    done

    wait "$PID"
    local EXIT_CODE=$?
    local OUTPUT=$(< /tmp/cmd_output.log)
    rm -f /tmp/cmd_output.log

    printf "\r                       \r"
    if [[ $EXIT_CODE -eq 0 ]]; then
        printf "[\033[0;32mOK\033[0m] %s\n" "$Y"
    else
        printf "[\033[0;31mNO\033[0m] %s\n" "$Y"
        echo "$OUTPUT"
    fi
    return $EXIT_CODE
}

# ---------------- 获取用户名和域名 ----------------
U=$(whoami)
V=$(echo "$U" | tr '[:upper:]' '[:lower:]')

HOSTNAME=$(hostname)
if [[ "$HOSTNAME" == *ct8.pl* ]]; then
    DOMAIN="$V.ct8.pl"
elif [[ "$HOSTNAME" == *serv00.com* ]]; then
    DOMAIN="$V.serv00.net"
else
    echo "🚫 无法识别主机名，默认使用 $V.local"
    DOMAIN="$V.local"
fi

PY_DIR="$HOME/domains/$DOMAIN/public_python"
ENV_FILE="$PY_DIR/.env"

# 脚本自身的绝对路径（要在任何 cd 之前记下来，快捷方式创建时用）
# 注意：用 bash <(curl ...) 这种进程替换方式运行时，$0 是 bash，根本不是脚本文件，
# 所以下面 setup_shortcut 不能只靠 cp "$SCRIPT_PATH"，必须有下载兜底
SCRIPT_PATH="$0"
if [[ "$SCRIPT_PATH" != /* ]]; then
    SCRIPT_PATH="$PWD/$SCRIPT_PATH"
fi
SCRIPT_URL="https://raw.githubusercontent.com/djkyc/s5/refs/heads/main/os.sh"

# ---------------- 菜单 ----------------
menu() {
    echo "———————————————————————"
    echo "此脚本由by:𝑺𝒆𝒓𝒐𝒌𝑽𝒊𝒑 二次改编Djkyc"
    echo "请选择操作："
    echo "1) 一键安装"
    echo "2) 端口管理"
    echo "3) 配置修改"
    echo "4) 查看服务"
    echo "5) 一键卸载"
    echo "6) 重启服务"
    echo "7) 创建 s5 快捷方式"
    echo "0) 退出"
    read -p "输入序号: " choice
}

# ---------------- 一键安装 ----------------
install_service() {
    echo "开始一键安装流程..."
    echo "————————————————————————————————————————————"

    # 删除默认 PHP 域名：只转自己账号的默认域名，不碰其它 php 站点
    # （旧版取"第一个 php 域名"就删，多域名用户会被误删）
    PHP_DOMAIN=$(devil www list 2>/dev/null | awk -v d="$DOMAIN" 'NR>1 && $1==d && $2=="php"{print $1}')
    if [[ -n "$PHP_DOMAIN" ]]; then
        X "删除 默认PHP域名 ($PHP_DOMAIN)" "devil www del \"$PHP_DOMAIN\" || true"
        if [[ -d "$HOME/domains/$PHP_DOMAIN" ]]; then
            X "删除 PHP 域名目录 ($HOME/domains/$PHP_DOMAIN)" "rm -rf \"$HOME/domains/$PHP_DOMAIN\""
        fi
    else
        echo "ℹ️ 默认域名 $DOMAIN 不是 PHP 类型，跳过删除"
    fi

    # 检查 Python 域名是否已存在
    EXIST_DOMAIN=$(devil www list | awk 'NR>1 && $1=="'"$DOMAIN"'" && $2=="python"{print $1}')
    if [[ -n "$EXIST_DOMAIN" ]]; then
        if [[ -d "$PY_DIR" && -f "$PY_DIR/get.py" && -f "$PY_DIR/s5.enc" ]]; then
            echo "✅ 服务已安装，无需重复安装"
            setup_shortcut
            show_service
            return
        else
            echo "⚠️ 域名已存在，但目录或文件不完整，先删除重新创建"
            X "删除已存在 Python 域名 ($DOMAIN)" "devil www del \"$DOMAIN\" || true"
            if [[ -d "$HOME/domains/$DOMAIN" ]]; then
                X "删除域名目录 ($HOME/domains/$DOMAIN)" "rm -rf \"$HOME/domains/$DOMAIN\""
            fi
        fi
    fi

    # 创建 Python 域名
    X "创建 Python 域名" "devil www add \"$DOMAIN\" python /usr/local/bin/python3.11"

    # 检查端口并创建
    PORT_LIST=$(devil port list)
    PORT_COUNT=$(echo "$PORT_LIST" | awk 'NR>1{print $1}' | wc -l)
    if (( PORT_COUNT >= 3 )); then
        echo "🚫 当前已有 3 个端口，不能再创建新端口"
        read -p "按回车返回主菜单..."
        return
    fi

    S5_PORT=$(echo "$PORT_LIST" | awk 'NR>1 && $3=="s5"{print $1}')
    if [[ -n "$S5_PORT" ]]; then
        X "删除 已存在的 s5 端口 ($S5_PORT)" "devil port del tcp $S5_PORT"
    fi

    FAIL_COUNT=0
    while true; do
        PORT=$(( (RANDOM % 62977) + 1024 ))
        OUTPUT=$(devil port add tcp "$PORT" s5 2>&1)
        if echo "$OUTPUT" | grep -q -E "(Port dodany prawidłowo|Port reserved succesfully)"; then
            echo -e "[\033[0;32mOK\033[0m] 端口创建成功: $PORT"
            break
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo -e "[\033[0;31mNO\033[0m] 端口创建失败: $PORT (第 $FAIL_COUNT 次)"
            if (( FAIL_COUNT >= 5 )); then
                echo "🚫 连续 5 次随机端口失败，退出安装"
                read -p "按回车返回主菜单..."
                return
            fi
            sleep 1
        fi
    done

    mkdir -p "$PY_DIR"

    # 生成 .env
    SCRIPT_KEY=71a2af107e0745ae989fdf71cb23c86e2130611d0f33e71e3f3c1b9115788b3b
    read -p "请输入 用户名: " INPUT_U
    S_U=$(echo -n "$INPUT_U" | base64)
    read -p "请输入 密码: " INPUT_P
    S_P=$(echo -n "$INPUT_P" | base64)
    cat > "$ENV_FILE" <<EOF
SCRIPT_KEY=$SCRIPT_KEY
S_U=$S_U
S_P=$S_P
S_PORT=$PORT
DOMAIN=$DOMAIN
EOF
    echo "✅ .env 文件生成成功: $ENV_FILE"

    cd "$PY_DIR" || return

    # 安装依赖
    DEPS=(python-dotenv pycryptodome setproctitle)
    for pkg in "${DEPS[@]}"; do
        if python3 -m pip show "$pkg" > /dev/null 2>&1; then
            echo -e "[\033[0;32mOK\033[0m] 已安装 $pkg，跳过"
        else
            X "安装 $pkg" "pip install $pkg"
        fi
    done

    # 下载文件（失败重试3次）
    for FILE_URL in \
        "https://raw.githubusercontent.com/ryty1/s5/main/get.py" \
        "https://raw.githubusercontent.com/ryty1/s5/main/s5.enc"; do
        FNAME=$(basename "$FILE_URL")
        ATTEMPT=0
        while true; do
            wget -q -O "$FNAME" "$FILE_URL"
            if [[ $? -eq 0 ]]; then
                echo -e "[\033[0;32mOK\033[0m] 下载 $FNAME 成功"
                break
            else
                ATTEMPT=$((ATTEMPT +1))
                echo -e "[\033[0;31mNO\033[0m] 下载 $FNAME 失败 (第 $ATTEMPT 次)"
                if (( ATTEMPT >= 3 )); then
                    echo "🚫 下载 $FNAME 失败，跳过"
                    break
                fi
                sleep 1
            fi
        done
    done

    # 启动后台服务（仅在未运行时启动）
    if ! pgrep -f "python3 $PY_DIR/get.py" >/dev/null 2>&1; then
        X "启动后台服务" "nohup python3 get.py >/dev/null 2>&1 &"
    fi

    sleep 5

    # 装过一次就创建快捷方式，下次直接输入 s5 即可呼出菜单
    setup_shortcut

    # 安装完成后显示服务信息
    show_service
}

# ---------------- 端口管理 ----------------
port_manager() {
    while true; do
        echo "———————————————————————"
        echo "端口管理："
        echo "1) 查看端口"
        echo "2) 更换端口"
        echo "3) 删除端口"
        echo "0) 返回主菜单"
        read -p "输入序号: " p_choice

        case $p_choice in
            1)
                devil port list
                ;;
            2)
                # 删除旧端口
                OLD_PORT=$(devil port list | awk 'NR>1 && $3=="s5"{print $1}')
                if [[ -n "$OLD_PORT" ]]; then
                    X "删除旧端口 ($OLD_PORT)" "devil port del tcp $OLD_PORT"
                fi

                # 创建新端口
                FAIL_COUNT=0
                while true; do
                    NEW_PORT=$(( (RANDOM % 62977) + 1024 ))
                    OUTPUT=$(devil port add tcp "$NEW_PORT" s5 2>&1)
                    if echo "$OUTPUT" | grep -q -E "(Port dodany prawidłowo|Port reserved succesfully)"; then
                        echo -e "[\033[0;32mOK\033[0m] 新端口创建成功: $NEW_PORT"
                        sed -i "s/^S_PORT=.*/S_PORT=$NEW_PORT/" "$ENV_FILE"

                        # 精准重启 systemd-journald 相关 Python 服务
                        PID=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}')
                        if [[ -n "$PID" ]]; then
                            kill -9 $PID
                        fi
                        sleep 3

                        cd "$PY_DIR" || exit
                        nohup python3 get.py >/dev/null 2>&1 </dev/null &
                        disown

                        sleep 5

                        echo "✅ 已重启服务"
                        break
                    else
                        FAIL_COUNT=$((FAIL_COUNT +1))
                        echo -e "[\033[0;31mNO\033[0m] 端口创建失败: $NEW_PORT (第 $FAIL_COUNT 次)"
                        if (( FAIL_COUNT >=5 )); then
                            echo "🚫 连续5次端口创建失败，返回端口菜单"
                            break
                        fi
                        sleep 1
                    fi
                done
                ;;
            3)
                PORTS=($(devil port list | awk 'NR>1{print $1}'))
                if [[ ${#PORTS[@]} -eq 0 ]]; then
                    echo "无可删除端口"
                    continue
                fi
                echo "现有端口列表:"
                for i in "${!PORTS[@]}"; do
                    echo "$((i+1))) ${PORTS[i]}"
                done
                read -p "请输入要删除的序号: " del_idx
                PORT_DEL=${PORTS[$((del_idx-1))]}
                X "删除端口 $PORT_DEL" "devil port del tcp $PORT_DEL"
                ;;
            0)
                break
                ;;
            *)
                echo "无效选择"
                ;;
        esac
    done
}

# ---------------- 配置修改 ----------------
config_modify() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "❌ 服务未安装，先运行一键安装"
        read -p "按回车返回主菜单..."
        return
    fi

    echo "当前配置："
    cat "$ENV_FILE"

    read -p "是否修改 账号, 密码? (y/n): " modify
    if [[ "$modify" == "y" ]]; then
        read -p "请输入新的 账号: " INPUT_U
        S_U=$(echo -n "$INPUT_U" | base64)
        sed -i '' "s|^S_U=.*|S_U=$S_U|" "$ENV_FILE"

        read -p "请输入新的 密码: " INPUT_P
        S_P=$(echo -n "$INPUT_P" | base64)
        sed -i '' "s|^S_P=.*|S_P=$S_P|" "$ENV_FILE"

        # 精准重启 systemd-journald 相关 Python 服务
        PID=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}')
        if [[ -n "$PID" ]]; then
            kill -9 $PID
        fi

        sleep 3

        cd "$PY_DIR" || exit
        nohup python3 get.py >/dev/null 2>&1 </dev/null &
        disown
        echo "✅ 已重启服务"
    fi

    sleep 5

    read -p "按回车返回主菜单..."
}

# ---------------- 创建 s5 快捷方式 ----------------
setup_shortcut() {
    local DST="$HOME/s5.sh"
    mkdir -p "$HOME/bin"

    # 1) 先拿到一份真实的脚本存到 $HOME/s5.sh
    #    情况 A：正常文件运行（bash s5.sh、./s5.sh、或已通过 s5 呼出），直接复制
    #    情况 B：bash <(curl ...) 进程替换运行，$0 根本不是文件，复制必然失败，
    #            必须重新从仓库下载一份，否则会像之前那样假装成功、实际没有 s5.sh
    if [[ -f "$SCRIPT_PATH" && "$SCRIPT_PATH" != "$DST" ]]; then
        cp "$SCRIPT_PATH" "$DST" 2>/dev/null || true
    fi
    if [[ ! -s "$DST" ]]; then
        echo "ℹ️ 当前不是文件运行，正在从仓库下载脚本到 $DST ..."
        if command -v curl >/dev/null 2>&1; then
            curl -Ls "$SCRIPT_URL" -o "$DST" 2>/dev/null || true
        fi
        if [[ ! -s "$DST" ]] && command -v wget >/dev/null 2>&1; then
            wget -q -O "$DST" "$SCRIPT_URL" 2>/dev/null || true
        fi
    fi
    chmod +x "$DST" 2>/dev/null || true

    # 2) 校验：没有真实文件就不要谎报成功
    if [[ ! -s "$DST" ]]; then
        echo "❌ 快捷方式创建失败：无法获取脚本文件，请检查网络或手动下载后选 7 重试"
        return 1
    fi

    # ~/bin/s5 -> $HOME/s5.sh，s5 本身就是可执行脚本
    ln -sf "$DST" "$HOME/bin/s5"

    # 让以后登录的 shell 都能找到 ~/bin
    # bash 登录 shell 只读第一个找到的 .bash_profile/.bash_login/.profile，
    # 所以只写 .bashrc + .profile 不够，必须把 .bash_profile 也写上
    for RC in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        touch "$RC" 2>/dev/null || continue
        if ! grep -q 'HOME/bin' "$RC" 2>/dev/null; then
            printf '\nexport PATH="$HOME/bin:$PATH"\n' >> "$RC"
        fi
    done
    export PATH="$HOME/bin:$PATH"

    if [[ -x "$HOME/bin/s5" ]]; then
        echo "✅ 快捷方式已创建：$HOME/bin/s5 -> $DST"
        echo "✅ 下次登录后直接输入 s5 即可呼出菜单"
    else
        echo "❌ 快捷方式创建失败：$HOME/bin/s5 不可执行"
        return 1
    fi
    echo "ℹ️ 子脚本改不了父终端的 PATH，所以本次当前终端如还提示找不到 s5，请先执行 source ~/.bashrc 或重新登录一次"
}

# ---------------- 重启服务 ----------------
restart_service() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "❌ 服务未安装，先运行一键安装"
        read -p "按回车返回主菜单..."
        return
    fi

    if [[ ! -f "$PY_DIR/get.py" ]]; then
        echo "❌ 找不到 $PY_DIR/get.py，先运行一键安装"
        read -p "按回车返回主菜单..."
        return
    fi

    echo "正在重启服务..."

    # 先杀掉旧进程：先按原脚本的 systemd-journald 伪装名找，找不到再按 get.py 路径找
    OLD_PIDS=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}')
    if [[ -z "$OLD_PIDS" ]]; then
        OLD_PIDS=$(pgrep -f "python3 $PY_DIR/get.py" || true)
    fi

    if [[ -n "$OLD_PIDS" ]]; then
        for OLD_PID in $OLD_PIDS; do
            kill -9 "$OLD_PID" 2>/dev/null || true
        done
        sleep 3
    else
        echo "ℹ️ 未检测到正在运行的旧进程，直接启动"
    fi

    # 用 return 而不是 exit：进不去目录也只回主菜单，不会把整个脚本退掉
    cd "$PY_DIR" || {
        echo "❌ 无法进入 $PY_DIR"
        read -p "按回车返回主菜单..."
        return
    }
    nohup python3 get.py >/dev/null 2>&1 </dev/null &
    disown

    sleep 5

    # 校验：新进程确实起来了才算成功
    NEW_PID=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}' | head -n1)
    if [[ -z "$NEW_PID" ]]; then
        NEW_PID=$(pgrep -f "python3 $PY_DIR/get.py" | head -n1 || true)
    fi

    if [[ -n "$NEW_PID" ]]; then
        echo "✅ 重启成功，运行中 (PID: $NEW_PID)"
    else
        echo "❌ 重启失败，进程未检测到，请检查 $PY_DIR/get.py 和 $ENV_FILE"
    fi

    read -p "按回车返回主菜单..."
}

# ---------------- 查看服务 ----------------
show_service() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "❌ 服务未安装"
        read -p "按回车返回主菜单..."
        return
    fi

    # 小工具函数，读取 .env 中的值（保留 Base64 的 '='）
    env_get() {
        sed -n "s/^$1=//p" "$ENV_FILE" | head -n1
    }

    # 检查服务是否运行 (匹配 systemd-journald 的伪装进程)
    PID=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}')
    if [[ -n "$PID" ]]; then
        echo "✅ 服务状态：运行中 (PID: $PID)"
    else
        echo "❌ 服务状态：未运行"
    fi

    # 获取公网 IP
    PUBLIC_IP=$(curl -s ip.sb)

    # 从 .env 获取端口、账号、密码并解码
    PORT="$(env_get S_PORT)"
    USER="$(env_get S_U | base64 --decode | tr -d '\r\n')"
    PASS="$(env_get S_P | base64 --decode | tr -d '\r\n')"

    echo "———————————————————————"
    echo "你的服务："
    echo "地址：$PUBLIC_IP"
    echo "端口：$PORT"
    echo "账号：$USER"
    echo "密码：$PASS"
    echo "———————————————————————"
    echo "一键复制格式："
    echo "Telegram 代理链接："
    echo "https://t.me/socks?server=$PUBLIC_IP&port=$PORT&user=$USER&pass=$PASS"
    echo "———————————————————————"
    read -p "按回车返回主菜单..."
}

# ---------------- 一键卸载 ----------------
uninstall_service() {
    echo "开始卸载服务..."
    echo "———————————————————————"

    # 只删本脚本自己创建的资源：python 域名 $DOMAIN、备注为 s5 的端口、
    # $PY_DIR 下的进程、~/bin/s5 快捷链接、~/s5.sh 脚本本体。
    # 域名目录动手前必须验明正身（有 get.py/s5.enc/.env 任一特征文件），
    # 防止目录被挪作他用后仍被 rm -rf。

    DEL_DOMAIN=0
    if devil www list 2>/dev/null | awk -v d="$DOMAIN" 'NR>1 && $1==d && $2=="python"{found=1} END{exit !found}'; then
        DEL_DOMAIN=1
    fi

    IS_OURS=0
    if [[ -f "$PY_DIR/get.py" || -f "$PY_DIR/s5.enc" || -f "$ENV_FILE" ]]; then
        IS_OURS=1
    fi

    S5_PORT=$(devil port list 2>/dev/null | awk 'NR>1 && $3=="s5"{print $1}')

    echo "将要删除（仅限本脚本创建的资源）："
    [[ $DEL_DOMAIN -eq 1 ]] && echo "  域名: $DOMAIN (python)"
    [[ $DEL_DOMAIN -eq 1 && $IS_OURS -eq 1 && -d "$PY_DIR" ]] && echo "  目录: $PY_DIR"
    [[ -n "$S5_PORT" ]] && echo "  端口: $S5_PORT (tcp)"
    [[ -e "$HOME/bin/s5" ]] && echo "  快捷方式: $HOME/bin/s5"
    [[ -f "$HOME/s5.sh" ]] && echo "  脚本本体: $HOME/s5.sh"

    if [[ $DEL_DOMAIN -eq 0 && -z "$S5_PORT" && ! -e "$HOME/bin/s5" ]]; then
        echo "ℹ️ 没有检测到本脚本创建的资源，无需卸载"
        read -p "按回车返回主菜单..."
        return
    fi

    read -p "确认卸载？(y/n): " cf
    if [[ "$cf" != "y" && "$cf" != "Y" ]]; then
        echo "已取消"
        read -p "按回车返回主菜单..."
        return
    fi

    if [[ $DEL_DOMAIN -eq 1 ]]; then
        X "删除 Python 域名 ($DOMAIN)" "devil www del \"$DOMAIN\" || true"
        if [[ $IS_OURS -eq 1 && -d "$PY_DIR" ]]; then
            X "删除域名目录 ($PY_DIR)" "rm -rf \"$PY_DIR\""
        elif [[ -d "$PY_DIR" ]]; then
            echo "⚠️ $PY_DIR 下没有 s5 的特征文件（get.py/s5.enc/.env），疑似被挪作他用，已跳过删除"
        fi
    else
        echo "ℹ️ 域名 $DOMAIN 不存在或不是 python 类型，跳过域名与目录删除"
    fi

    if [[ -n "$S5_PORT" ]]; then
        X "删除 s5 端口 ($S5_PORT)" "devil port del tcp $S5_PORT"
    fi

    # 只杀本脚本的进程：确认是自家安装才按伪装名杀，避免误伤同名进程
    PID=""
    if [[ $IS_OURS -eq 1 ]]; then
        PID=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}')
    fi
    if [[ -z "$PID" && -f "$PY_DIR/get.py" ]]; then
        PID=$(pgrep -f "python3 $PY_DIR/get.py" 2>/dev/null || true)
    fi
    if [[ -n "$PID" ]]; then
        kill -9 $PID 2>/dev/null || true
        echo "✅ 已杀掉 PID $PID"
    else
        echo "ℹ️ 未检测到本脚本的运行进程"
    fi

    # 快捷方式和脚本本体一起删，卸载后不留任何 s5 相关文件。
    # 注意：bash 执行中的脚本删文件不影响当前这次运行（读的是已打开的文件描述符）。
    if [[ -e "$HOME/bin/s5" ]]; then
        rm -f "$HOME/bin/s5"
        echo "✅ 已删除 s5 快捷方式（$HOME/bin/s5）"
    fi
    if [[ -f "$HOME/s5.sh" ]]; then
        rm -f "$HOME/s5.sh"
        echo "✅ 已删除脚本本体（$HOME/s5.sh）"
    fi

    echo "✅ 卸载完成"
    read -p "按回车返回主菜单..."
}

# ---------------- 主循环 ----------------
while true; do
    menu
    case $choice in
        1) install_service ;;
        2) port_manager ;;
        3) config_modify ;;
        4) show_service ;;
        5) uninstall_service ;;
        6) restart_service ;;
        7) setup_shortcut; read -p "按回车返回主菜单..." ;;
        0) echo "👋 已退出"; break ;;
        *) echo "无效选择" ;;
    esac
done
