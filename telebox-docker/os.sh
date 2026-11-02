#!/bin/bash

TARGET_DIR="$HOME/telebox"
APP_NAME="telebox"

# ==========================================
# 内部参数分发器（当你在终端敲击极简快捷指令时由 os.sh 自身响应）
# ==========================================
if [ "$1" = "status" ]; then
    # 检查状态与内存占用
    ps -U $USER -o pid,stat,%mem,rss,command | grep -E 'esbuild-register|node' | grep -v grep
    exit 0
elif [ "$1" = "stop" ]; then
    # 强杀进程
    echo "🛑 正在停止 TeleBox 进程..."
    killall -9 node esbuild 2>/dev/null
    echo "✅ 已停止。"
    exit 0
elif [ "$1" = "restart" ]; then
    # 先停后开（重启）
    echo "🔄 正在安全重启 TeleBox..."
    killall -9 node esbuild 2>/dev/null
    sleep 1
    cd "$TARGET_DIR" || exit 1
    nohup bash "$0" start-daemon >> "$TARGET_DIR/telebox.log" 2>&1 &
    echo "✅ TeleBox 已在后台重新启动！"
    exit 0
elif [ "$1" = "start-daemon" ]; then
    # V8 内存限制防爆 (280MB) 守护启动核心逻辑
    cd "$TARGET_DIR" || exit 1
    export PATH=$HOME/.bin:/usr/local/bin:/usr/bin:/bin
    export PYTHON=/usr/local/bin/python3
    export NODE_ENV=production
    CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}"
    LS_FILE="${TB_LOCALSTORAGE_FILE:-$CACHE_BASE/telebox/node-localstorage}"
    mkdir -p "$(dirname "$LS_FILE")"
    
    # 核心控内存：严格限制 V8 堆内存上限在 280MB 以内，防止爆 Serv00 512M 限额
    export NODE_OPTIONS="--localstorage-file=$LS_FILE --max-old-space-size=280 --expose-gc"
    
    exec node -r tsconfig-paths/register -r "$TARGET_DIR/scripts/esbuild-register.cjs" "$TARGET_DIR/src/index.ts"
fi

# ==========================================
# 首次通过一键命令远程执行时的安装引导逻辑
# ==========================================
echo "=================================================================="
echo "    TeleBox 极轻量防爆内存单脚本版（Serv00 / 纯Linux 专用）      "
echo "                      By:SerokVip引导学习Djkyc再次改编             "
echo "=================================================================="

# 1. 检测是否已经安装过
if [ -d "$TARGET_DIR" ]; then
    echo "⚠️ [检测提示] 发现 ~/telebox 目录已存在！"
    echo "❌ 提示：检测到之前已经安装过 TeleBox。"
    echo "-----------------------------------------"
    read -p "是否需要自动删除旧版本并重新全新安装？[y/N]: " choice
    case "$choice" in 
        [yY]|[yY][eE][sS])
            echo "🧹 正在清理旧进程和目录..."
            killall -9 node esbuild 2>/dev/null
            rm -rf "$TARGET_DIR"
            echo "✅ 清理完成，开始全新安装..."
            ;;
        *)
            echo "❌ 操作已取消。如需保留或重新安装，请手动删除旧目录后重试 rm -rf ~/telebox"
            exit 1
            ;;
    esac
fi

# 2. 确保 Serv00 环境映射与独立权限
echo "==> 正在配置运行环境与独立权限..."
devil binexec on >/dev/null 2>&1 || true
mkdir -p ~/.bin
if [ -f /usr/local/bin/node24 ]; then
    ln -sf /usr/local/bin/node24 ~/.bin/node
    ln -sf /usr/local/bin/npm24 ~/.bin/npm
fi

# 3. 创建目录并克隆项目
echo "==> 正在创建目录并克隆 TeleBox 项目..."
mkdir -p "$TARGET_DIR" && cd "$TARGET_DIR"
git clone https://github.com/TeleBoxOrg/TeleBox.git .

# 4. 智能系统检测与 package.json 适配 (FreeBSD 剥离 canvas)
echo "==> 正在检测系统环境并优化 package.json..."
python3 -c '
import json, platform
with open("package.json", "r", encoding="utf-8") as f:
    data = json.load(f)

if platform.system() == "FreeBSD":
    print("💡 [系统适配] 检测到 FreeBSD (Serv00) 环境，正在自动剥离 canvas 依赖...")
    for key in ["dependencies", "devDependencies"]:
        if key in data and "canvas" in data[key]:
            del data[key]["canvas"]
else:
    print("💡 [系统适配] 检测到 Linux/Debian 环境，保持标准依赖...")

with open("package.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
'

# 5. 配置加速镜像并安全安装
echo "==> 配置国内 npm 加速镜像..."
npm config set registry https://registry.npmmirror.com
npm cache clean --force

if [ "$(uname)" = "FreeBSD" ]; then
    echo "==> [Serv00/FreeBSD 专属优化] 安全安装所有 JS/TS 依赖..."
    npm install --ignore-scripts --maxsockets 1
    echo "==> [Serv00/FreeBSD 专属优化] 平稳恢复 SQLite 核心模块..."
    npm rebuild better-sqlite3 --update-binary
    
    # 修复 FreeBSD 下 esbuild 文件的执行权限
    chmod -R +x node_modules/@esbuild node_modules/.bin 2>/dev/null || true
else
    echo "==> [Linux/Debian 模式] 执行标准依赖构建..."
    npm install --maxsockets 1
fi

# 预编译插件以节省运行内存
echo "==> 正在预编译插件以节省内存..."
npm run precompile 2>/dev/null || true

echo "=================================================="
echo "🎉 依赖安装完成！即将启动并引导输入 Telegram 凭据..."
echo "=================================================="

# 6. 首次前台启动引导用户输入 api_id 并登录
echo "💡 请在下方按提示输入你的 Telegram 凭据完成登录..."
npm start

# 7. 将当前的 os.sh 复制到 ~/telebox/os.sh，供后台看门狗及后续极简指令复用
cp "$0" "$TARGET_DIR/os.sh"
chmod +x "$TARGET_DIR/os.sh"

# 8. 首次启动后台守护
echo "==> 正在将 TeleBox 托管至后台轻量运行..."
killall -9 node esbuild 2>/dev/null
nohup bash "$TARGET_DIR/os.sh" start-daemon >> "$TARGET_DIR/telebox.log" 2>&1 &

# 9. 生成独立的看门狗脚本挂载进 Crontab（完美兼容 FreeBSD 语法）
cat << EOF > "$HOME/check_telebox.sh"
#!/bin/bash
export HOME="/home/\$USER"
export PATH=\$HOME/.bin:/usr/local/bin:/usr/bin:/bin
export PYTHON=/usr/local/bin/python3

devil binexec on >/dev/null 2>&1

if [ ! -f "\$HOME/telebox/config.json" ]; then
    exit 0
fi

if ! pgrep -f 'esbuild-register.cjs' >/dev/null 2>&1; then
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] TeleBox 掉线，正在自动拉起..." >> \$HOME/telebox/watchdog.log
    nohup bash \$HOME/telebox/os.sh start-daemon >> \$HOME/telebox/telebox.log 2>&1 &
fi
EOF
chmod +x "$HOME/check_telebox.sh"

# 安全写入 Crontab（适配 FreeBSD 的文件导入方式，避免管道报错）
crontab -l 2>/dev/null | grep -v "check_telebox.sh" > /tmp/crontab.tmp
echo "@reboot /bin/bash $HOME/check_telebox.sh >> $HOME/telebox/cron.log 2>&1" >> /tmp/crontab.tmp
echo "*/5 * * * * /bin/bash $HOME/check_telebox.sh >> $HOME/telebox/cron.log 2>&1" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm -f /tmp/crontab.tmp

# 10. 自动写入专属极简快捷别名到终端配置文件 (.bashrc / .zshrc)
# 注意：为避开 FreeBSD 原生 tr 命令冲突，重启指令已变更为 tbr
SHELL_RC="$HOME/.bashrc"
[ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"

if ! grep -q "# TeleBox极简快捷指令" "$SHELL_RC"; then
    echo "" >> "$SHELL_RC"
    echo "# TeleBox极简快捷指令" >> "$SHELL_RC"
    echo "alias ts='bash $TARGET_DIR/os.sh status'" >> "$SHELL_RC"
    echo "alias tbr='bash $TARGET_DIR/os.sh restart'" >> "$SHELL_RC"
    echo "alias tp='bash $TARGET_DIR/os.sh stop'" >> "$SHELL_RC"
    echo "alias td='bash $TARGET_DIR/os.sh stop && crontab -l 2>/dev/null | grep -v \"check_telebox.sh\" | crontab -; rm -rf $TARGET_DIR $HOME/check_telebox.sh; echo \"🗑️ TeleBox 已通过单脚本彻底卸载清理！\"'" >> "$SHELL_RC"
    echo "✅ 已成功为你注册全局极简快捷指令: ts, tbr, tp, td"
fi

source "$SHELL_RC" 2>/dev/null || true

echo "=================================================="
echo "🎯 极轻量单脚本部署全部完成！"
echo "--------------------------------------------------"
echo "💡 【验证方法】：在 Telegram 任意聊天中向自己发送 .ping 或 .help"
echo "   看到 UserBot 正常回复即代表搭建成功！"
echo "--------------------------------------------------"
echo "⌨️ 常用极简快捷指令提示（终端随时输入）："
echo "  - 查看运行状态: ts (TeleBox Status)"
echo "  - 安全重启机器: tbr (TeleBox Restart，避开系统tr冲突)"
echo "  - 停止机器人  : tp (TeleBox Pause/Stop)"
echo "  - 彻底卸载清理: td (TeleBox Delete & Clean)"
echo "  - 查看实时日志: tail -f ~/telebox/telebox.log"
echo "=================================================="
