#!/bin/bash
# TeleBox 极轻量版，Serv00 / CT8 通用
# 特点：无 PM2，nohup + 看门狗，后台守护，内存上限 280MB
# 来源：用户提供的 serv00-ct8/telebox-docker/os.sh 轻量版，在此基础上做了以下完善，
# 均针对今天在 s1.ct8.pl 上实际遇到的问题：
# 1. 已装好的 ~/telebox/os.sh 不带参数时不再掉进安装流程，只打印用法
# 2. 管道方式运行（bash <(curl...)）时，os.sh 复制失败会改从仓库下载并校验
# 3. npm start 前台登录被中断时，只有 config.json 已生成才继续走后台，否则明说未完成
# 4. 依赖安装、重建、产物校验失败时直接停下，不再谎报成功
# 5. 后台启动后等 5 秒验进程，验不到就打日志尾部，不打完成提示
# 6. 别名只在写入成功后才提示，并提醒重新登录或 source 才生效
# 7. 看门狗用安装时实际的 $HOME，不再硬编码 /home/$USER，Serv00 与 CT8 通用
# 8. 新增 help 参数，随时可看快捷提示
# 9. 删除/卸载（td / uninstall）会一起清掉：进程、crontab 看门狗、~/telebox（远程下载的全部安装文件）、~/check_telebox.sh、~/.cache/telebox、安装时创建的 node24 软链、以及 .bashrc/.zshrc 里的 TeleBox 别名段；不删 ~/backups 里的备份
TARGET_DIR="$HOME/telebox"
APP_NAME="telebox"
SCRIPT_URL="https://raw.githubusercontent.com/djkyc/serv00-ct8/refs/heads/main/telebox-docker/os.sh"
MEMORY_MB="280"

fail() {
echo "❌ $1"
exit 1
}

print_tips() {
echo "=================================================="
echo "⌨️ 常用极简快捷指令提示（终端随时输入）："
echo " - 查看运行状态: ts (TeleBox Status)"
echo " - 安全重启: tbr (TeleBox Restart)"
echo " - 停止: tp (TeleBox Pause/Stop)"
echo " - 彻底卸载清理: td (TeleBox Delete & Clean)"
echo " - 查看实时日志: tail -f ~/telebox/telebox.log"
echo " - 查看帮助: bash ~/telebox/os.sh help"
echo "=================================================="
}

print_usage() {
echo "用法: bash ~/telebox/os.sh {status|stop|restart|start-daemon|uninstall|help}"
echo "安装（全新）请用一键命令，或：bash os.sh install"
print_tips
}

# ==========================================
# 内部参数分发器
# ==========================================
if [ "$1" = "status" ]; then
ps -U "$USER" -o pid,stat,%mem,rss,command 2>/dev/null | grep -E 'esbuild-register|node' | grep -v grep
print_tips
exit 0
elif [ "$1" = "stop" ]; then
echo "🛑 正在停止 TeleBox 进程..."
killall -9 node esbuild 2>/dev/null || true
echo "✅ 已停止。"
print_tips
exit 0
elif [ "$1" = "restart" ]; then
echo "🔄 正在安全重启 TeleBox..."
killall -9 node esbuild 2>/dev/null || true
sleep 1
cd "$TARGET_DIR" || exit 1
nohup bash "$0" start-daemon >> "$TARGET_DIR/telebox.log" 2>&1 &
echo "✅ TeleBox 已在后台重新启动！"
print_tips
exit 0
elif [ "$1" = "start-daemon" ]; then
cd "$TARGET_DIR" || exit 1
export PATH="$HOME/.bin:/usr/local/bin:/usr/bin:/bin"
export PYTHON=/usr/local/bin/python3
export NODE_ENV=production
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}"
LS_FILE="${TB_LOCALSTORAGE_FILE:-$CACHE_BASE/telebox/node-localstorage}"
mkdir -p "$(dirname "$LS_FILE")" 2>/dev/null || true
# 内存压缩 / 上限：严格限制 V8 堆内存，防止爆 Serv00 / CT8 共享主机限额
export NODE_OPTIONS="--localstorage-file=$LS_FILE --max-old-space-size=$MEMORY_MB --expose-gc"
NODE_BIN="node"
if [ -x "$HOME/.bin/node" ]; then NODE_BIN="$HOME/.bin/node"; fi
exec "$NODE_BIN" -r tsconfig-paths/register -r "$TARGET_DIR/scripts/esbuild-register.cjs" "$TARGET_DIR/src/index.ts"
elif [ "$1" = "uninstall" ]; then
echo "🗑️ 正在彻底卸载清理 TeleBox（目录 + 远程下载的安装文件一起清）..."
killall -9 node esbuild 2>/dev/null || true
if command -v crontab >/dev/null 2>&1; then
  crontab -l 2>/dev/null | grep -v "check_telebox.sh" | crontab - 2>/dev/null || true
  echo " - 已清 crontab 里的 check_telebox.sh 看门狗"
fi
rm -rf "$TARGET_DIR"
echo " - 已删 $TARGET_DIR（含远程克隆的 TeleBox、node_modules、telebox.log、config.json、插件）"
rm -f "$HOME/check_telebox.sh"
echo " - 已删 $HOME/check_telebox.sh"
rm -rf "$HOME/.cache/telebox"
echo " - 已清 ~/.cache/telebox（本地存储）"
rm -f /tmp/crontab.tmp
for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$RC" ]; then
    grep -v "TeleBox极简快捷指令" "$RC" | grep -v "alias ts=" | grep -v "alias tbr=" | grep -v "alias tp=" | grep -v "alias td=" > "$RC.tmp" 2>/dev/null || true
    mv "$RC.tmp" "$RC" 2>/dev/null || true
    echo " - 已清 $RC 里的 TeleBox 别名"
  fi
done
for LINK in "$HOME/.bin/node" "$HOME/.bin/npm"; do
  if [ -L "$LINK" ]; then
    DEST="$(readlink "$LINK" 2>/dev/null || echo "")"
    case "$DEST" in
      */node24|*/npm24) rm -f "$LINK"; echo " - 已删安装时创建的 $LINK（指向 $DEST）" ;;
      *) echo " - 保留 $LINK（不是安装时创建的 node24 软链，未动）" ;;
    esac
  fi
done
echo "✅ TeleBox 已彻底卸载清理！（~/backups 里的备份未动，如需恢复请手动拷回 config.json）"
echo "ℹ️ 当前终端的 ts/tbr/tp/td 别名请重新登录或新开终端后即失效。"
exit 0
elif [ "$1" = "help" ]; then
print_tips
exit 0
fi

# 已装好的 os.sh 本身被调用时，不带参数或带未知参数都只打印用法，绝不进安装。
# 只有管道方式（一键命令，$0 不是 ~/telebox/os.sh）或显式 install 参数才继续安装。
if [ "$0" = "$TARGET_DIR/os.sh" ]; then
print_usage
exit 1
fi
if [ -n "$1" ] && [ "$1" != "install" ]; then
echo "❌ 未知参数: $1"
print_usage
exit 1
fi

# ==========================================
# 安装引导逻辑（Serv00 / CT8 通用，FreeBSD 与 Linux 分支）
# ==========================================
echo "=================================================================="
echo " TeleBox 极轻量防爆内存单脚本版（Serv00 / CT8 通用）"
echo " By:SerokVip引导学习Djkyc再次改编"
echo "=================================================================="
echo "ℹ️ 主机: $(uname -s) $(uname -m)，HOME: $HOME，内存上限: ${MEMORY_MB}MB"

if ! command -v node >/dev/null 2>&1; then
fail "未找到 node，请先在主机上安装 Node 再运行本脚本。"
fi
NODE_VER="$(node -v 2>/dev/null || echo unknown)"
echo "ℹ️ 当前 Node：$NODE_VER（TeleBox 0.2.9 要求 node 24.x，22.x 只会报 EBADENGINE 警告，不一定直接导致失败）"

# 1. 检测是否已经安装过
if [ -d "$TARGET_DIR" ]; then
echo "⚠️ [检测提示] 发现 ~/telebox 目录已存在！"
echo "❌ 提示：检测到之前已经安装过 TeleBox。"
echo "-----------------------------------------"
echo "注意：选 y 会删除整个 ~/telebox，包括 config.json 与插件，请先备份 config.json 再选 y。"
read -r -p "是否需要自动删除旧版本并重新全新安装？[y/N]: " choice
case "$choice" in
[yY]|[yY][eE][sS])
echo "🧹 正在清理旧进程和目录..."
killall -9 node esbuild 2>/dev/null || true
rm -rf "$TARGET_DIR"
echo "✅ 清理完成，开始全新安装..."
;;
*)
echo "❌ 操作已取消。如需保留或重新安装，请手动删除旧目录后重试 rm -rf ~/telebox"
exit 1
;;
esac
fi

# 2. 环境映射与独立权限（Serv00 与 CT8 的 devil 均为尽力而为，失败不中断）
echo "==> 正在配置运行环境与独立权限..."
devil binexec on >/dev/null 2>&1 || true
mkdir -p ~/.bin
if [ -f /usr/local/bin/node24 ]; then
echo "💡 检测到 /usr/local/bin/node24，已指向 ~/.bin/node"
ln -sf /usr/local/bin/node24 ~/.bin/node
ln -sf /usr/local/bin/npm24 ~/.bin/npm 2>/dev/null || true
else
echo "ℹ️ 未检测到 /usr/local/bin/node24，继续使用系统默认 node。"
fi
export PATH="$HOME/.bin:/usr/local/bin:/usr/bin:/bin"
export PYTHON=/usr/local/bin/python3
if ! grep -q 'export PATH=$HOME/.bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH=$HOME/.bin:/usr/local/bin:/usr/bin:/bin' >> "$HOME/.bashrc"
  echo 'export PYTHON=/usr/local/bin/python3' >> "$HOME/.bashrc"
fi
echo "ℹ️ 安装阶段当前 Node：$(node -v 2>/dev/null || echo unknown)（应为 v24.x，若仍为 v22，说明 ~/.bin 未生效，EBADENGINE 警告会继续）"

# 3. 创建目录并克隆项目
echo "==> 正在创建目录并克隆 TeleBox 项目..."
mkdir -p "$TARGET_DIR" || fail "创建 $TARGET_DIR 失败。"
cd "$TARGET_DIR" || fail "进入 $TARGET_DIR 失败。"
git clone https://github.com/TeleBoxOrg/TeleBox.git . || fail "克隆 TeleBox 失败，请检查网络后重试。"
[ -f "package.json" ] || fail "克隆后没有找到 package.json，克隆不完整，请删除 $TARGET_DIR 后重试。"

# 4. 系统检测与 package.json 适配（FreeBSD 剥离 canvas，Serv00 / CT8 均为 FreeBSD）
echo "==> 正在检测系统环境并优化 package.json..."
python3 -c 'import json, platform; d=json.load(open("package.json")); [d[k].pop("canvas", None) for k in ("dependencies", "devDependencies") if platform.system()=="FreeBSD" and k in d ]; json.dump(d, open("package.json", "w"), indent=2)' || fail "处理 package.json 失败。"

# 5. 配置加速镜像并安全安装（失败直接停下，不谎报成功）
echo "==> 配置国内 npm 加速镜像..."
npm config set registry https://registry.npmmirror.com || fail "设置 npm 镜像失败。"
npm cache clean --force 2>/dev/null || echo "⚠️ npm cache 清理失败，继续安装（不致命）。"

if [ "$(uname)" = "FreeBSD" ]; then
echo "==> [FreeBSD 专属优化] 安全安装所有 JS/TS 依赖..."
npm install --ignore-scripts --maxsockets 1 || fail "第一阶段依赖安装失败，脚本已停止，没有继续启动。请查看上面 npm 的报错。"
echo "==> [FreeBSD 专属优化] 平稳恢复 SQLite 核心模块..."
if ! npm rebuild better-sqlite3 --update-binary; then
echo "⚠️ 第一次 rebuild 失败，10 秒后重试一次..."
sleep 10
npm rebuild better-sqlite3 --update-binary || fail "better-sqlite3 重建失败，脚本已停止，不要直接重跑本脚本（会删除 $TARGET_DIR），先在 $TARGET_DIR 里单独跑 npm rebuild better-sqlite3 --update-binary，成功后再决定如何继续启动。"
fi
chmod -R +x node_modules/@esbuild node_modules/.bin 2>/dev/null || true
else
echo "==> [Linux 模式] 执行标准依赖构建..."
npm install --maxsockets 1 || fail "依赖安装失败，脚本已停止，没有继续启动。请查看上面 npm 的报错。"
fi

for MOD in esbuild tsconfig-paths; do
if [ ! -d "node_modules/$MOD" ]; then
fail "依赖不完整：缺少 node_modules/$MOD，说明 npm install 没有装全，不能继续启动。"
fi
done
if ! ls node_modules/better-sqlite3/build/Release/*.node >/dev/null 2>&1; then
fail "依赖不完整：better-sqlite3 编译产物不存在，不能继续启动。"
fi

echo "==> 正在预编译插件以节省内存..."
if ! npm run precompile; then
echo "⚠️ 预编译失败：启动时将改用实时编译继续运行，安装继续，但请留意内存占用。"
fi

echo "=================================================="
echo "🎉 依赖安装完成！即将启动并引导输入 Telegram 凭据..."
echo "=================================================="

# 6. 首次前台启动引导用户输入 api_id 并登录
# 注意：前台登录被 Ctrl+C 中断时，只有 config.json 已生成才继续走后台，否则明说未完成。
echo "💡 请在下方按提示输入你的 Telegram 凭据完成登录..."
echo "💡 登录完成后按 Ctrl+C，脚本会自动继续转后台，不要直接关终端。"
trap 'echo ""; echo "ℹ️ 已中断前台启动，继续检查登录结果..."' INT
npm start
START_CODE=$?
trap - INT
if [ ! -f "$TARGET_DIR/config.json" ]; then
fail "未检测到 $TARGET_DIR/config.json，说明登录未完成，脚本已停止，没有转后台。请重新运行登录流程，不要直接用 tbr 重启。"
fi
if [ "$START_CODE" -ne 0 ] && [ "$START_CODE" -ne 130 ] && [ "$START_CODE" -ne 129 ]; then
echo "⚠️ 前台启动退出码 $START_CODE，但 config.json 已存在，继续尝试转后台；若后台也起不来，请查看 telebox.log。"
fi

# 7. 将 os.sh 复制到 ~/telebox/os.sh，供后台看门狗及后续极简指令复用
# 管道运行时 $0 不是真实文件，直接 cp 会失败，必须改从仓库下载并校验。
if [ -f "$0" ]; then
cp "$0" "$TARGET_DIR/os.sh" || fail "复制 os.sh 到 $TARGET_DIR/os.sh 失败，后台守护无法启动。"
else
echo "ℹ️ 当前不是文件运行，正在从仓库下载 os.sh 到 $TARGET_DIR/os.sh..."
if command -v curl >/dev/null 2>&1; then
curl -Ls "$SCRIPT_URL" -o "$TARGET_DIR/os.sh" 2>/dev/null || true
fi
if [ ! -s "$TARGET_DIR/os.sh" ] && command -v wget >/dev/null 2>&1; then
wget -q -O "$TARGET_DIR/os.sh" "$SCRIPT_URL" 2>/dev/null || true
fi
fi
if [ ! -s "$TARGET_DIR/os.sh" ]; then
fail "获取 $TARGET_DIR/os.sh 失败：既不是文件运行，也无法从仓库下载，后台守护无法启动，请勿继续。"
fi
bash -n "$TARGET_DIR/os.sh" || fail "下载/复制的 $TARGET_DIR/os.sh 语法检查失败，后台守护无法启动。"
chmod +x "$TARGET_DIR/os.sh" || fail "给 $TARGET_DIR/os.sh 加可执行权限失败。"

# 8. 首次启动后台守护，并验进程
echo "==> 正在将 TeleBox 托管至后台轻量运行..."
killall -9 node esbuild 2>/dev/null || true
nohup bash "$TARGET_DIR/os.sh" start-daemon >> "$TARGET_DIR/telebox.log" 2>&1 &
sleep 5
if ! pgrep -f 'esbuild-register.cjs' >/dev/null 2>&1; then
echo "❌ 后台守护未检测到运行，telebox.log 最近输出："
tail -50 "$TARGET_DIR/telebox.log" 2>/dev/null || echo "(无日志)"
fail "后台守护启动失败，脚本已停止，不再打印部署完成。请查看上面日志，修复后再手动启动。"
fi

# 9. 生成看门狗并挂载进 Crontab（Serv00 / CT8 通用：用安装时实际的 $HOME，不硬编码 /home/$USER）
cat > "$HOME/check_telebox.sh" << WATCHDOG_EOF
#!/bin/bash
export HOME="$HOME"
export PATH="\$HOME/.bin:/usr/local/bin:/usr/bin:/bin"
export PYTHON=/usr/local/bin/python3
devil binexec on >/dev/null 2>&1 || true
if [ ! -f "\$HOME/telebox/config.json" ]; then
exit 0
fi
if ! pgrep -f 'esbuild-register.cjs' >/dev/null 2>&1; then
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] TeleBox 掉线，正在自动拉起..." >> "\$HOME/telebox/watchdog.log"
nohup bash "\$HOME/telebox/os.sh" start-daemon >> "\$HOME/telebox/telebox.log" 2>&1 &
fi
WATCHDOG_EOF
chmod +x "$HOME/check_telebox.sh"
crontab -l 2>/dev/null | grep -v "check_telebox.sh" > /tmp/crontab.tmp || true
echo "@reboot /bin/bash $HOME/check_telebox.sh >> $HOME/telebox/cron.log 2>&1" >> /tmp/crontab.tmp
echo "*/5 * * * * /bin/bash $HOME/check_telebox.sh >> $HOME/telebox/cron.log 2>&1" >> /tmp/crontab.tmp
if ! crontab /tmp/crontab.tmp; then
echo "⚠️ 写入 crontab 失败，看门狗不会自动拉起，请手动检查 crontab。"
else
if crontab -l 2>/dev/null | grep -q "check_telebox.sh"; then
echo "✅ 看门狗已写入 crontab（@reboot 与每 5 分钟检查）。"
else
echo "⚠️ crontab 里未找到 check_telebox.sh，看门狗可能未生效，请手动检查 crontab -l。"
fi
fi
rm -f /tmp/crontab.tmp

# 10. 写入快捷别名（修复版：不再只看标记就跳过，逐条补齐；按当前 shell 写，bash 就写 .bashrc，不因 .zshrc 存在就写错地方）
for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$RC" ]; then
    touch "$RC" 2>/dev/null || true
  fi
done
SHELL_RC="$HOME/.bashrc"
case "$SHELL" in
  *zsh*) SHELL_RC="$HOME/.zshrc" ;;
  *) SHELL_RC="$HOME/.bashrc" ;;
esac
if ! grep -q "# TeleBox极简快捷指令" "$SHELL_RC" 2>/dev/null; then
  echo "" >> "$SHELL_RC"
  echo "# TeleBox极简快捷指令" >> "$SHELL_RC"
fi
for ALIAS_LINE in "alias ts='bash $TARGET_DIR/os.sh status'" "alias tbr='bash $TARGET_DIR/os.sh restart'" "alias tp='bash $TARGET_DIR/os.sh stop'" "alias td='bash $TARGET_DIR/os.sh uninstall'"; do
  ALIAS_NAME="$(echo "$ALIAS_LINE" | cut -d' ' -f2 | cut -d= -f1)"
  if ! grep -q "^$ALIAS_NAME=" "$SHELL_RC" 2>/dev/null; then
    echo "$ALIAS_LINE" >> "$SHELL_RC"
  fi
done
if grep -q "alias ts=" "$SHELL_RC" && grep -q "alias tbr=" "$SHELL_RC" && grep -q "alias tp=" "$SHELL_RC" && grep -q "alias td=" "$SHELL_RC"; then
  echo "✅ 快捷别名已写入 $SHELL_RC（ts/tbr/tp/td 四条齐全）。"
else
  echo "⚠️ 快捷别名写入不全，请手动检查 $SHELL_RC，缺哪条补哪条。"
  grep -n "alias t" "$SHELL_RC" 2>/dev/null || true
fi
echo "ℹ️ 别名在当前终端不一定立刻生效，请重新登录，或运行：source $SHELL_RC"
echo "ℹ️ 验别名：source $SHELL_RC 后运行 type tbr，应显示 alias。"
source "$SHELL_RC" 2>/dev/null || true

echo "=================================================="
echo "🎯 极轻量单脚本部署全部完成！"
echo "--------------------------------------------------"
echo "💡 【验证方法】：在 Telegram 任意聊天中向自己发送 .ping 或 .help"
echo " 看到 UserBot 正常回复即代表搭建成功！"
echo "--------------------------------------------------"
print_tips
echo "=================================================="
