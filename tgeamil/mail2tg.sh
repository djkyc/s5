#!/usr/bin/env bash
# Mail2Telegram Serv00 一键部署脚本（带菜单、一步一步提示）
#
# 运行方法（不要用 bash <(curl...) 这种方式，提示输入会出问题）：
# 1. 把这个文件传到 Serv00 家目录，变成 ~/mail2tg.sh
# 2. chmod +x ~/mail2tg.sh
# 3../mail2tg.sh
# 4. 选 1 一键部署，按提示一步一步填
#
# 本脚本在主机上会产生的效果：
# - ~/mail2tg/：从 GitHub 克隆 Mail2Telegram（已存在则跳过克隆，不覆盖你的配置）
# - ~/mail2tg-venv/：Python 虚拟环境，并装 requirements.txt
# - ~/mail2tg/config.py：你填的机器人 Token、聊天 ID、邮箱和授权码，权限 600，只写在这里，不打印出来
# - ~/mail2tg/run.sh、start.sh、stop.sh：后台启动/停止脚本（代替 Docker / systemd）
# - ~/check_mail2tg.sh：看门狗
# - crontab：@reboot 和每 5 分钟各一条看门狗，服务掉了会自动拉起来
# - 后台进程：mail2tg/main.py，日志在 ~/mail2tg/mail2tg.log 和 ~/mail2tg/log/email_checker.log
#
# 只读说明：本脚本只配 IMAP，不配 SMTP，不改 Mail2Telegram 的发信逻辑。
# Outlook / Hotmail 在这个项目里目前直接连不上，菜单里选它时会先警告，
# 建议在 Outlook 网页版里转发到 Gmail / QQ / 163 其中一家再收。

REPO="https://github.com/Heavrnl/Mail2Telegram.git"
DIR="$HOME/mail2tg"
VENV="$HOME/mail2tg-venv"
WATCHDOG="$HOME/check_mail2tg.sh"
CONFIG="$DIR/config.py"

pause() {
read -r -p "按回车返回主菜单..." _dummy || true
echo ""
}

is_running() {
pgrep -f "mail2tg/main.py" >/dev/null 2>&1
}

# 把单引号转成 Python 字符串里安全的写法，避免密码里有 ' 把 config.py 写坏
py_escape() {
printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

ask_yes_no() {
# $1=提示，默认 No；返回 0 表示 yes
local ans=""
read -r -p "$1 [y/N] " ans || true
case "$ans" in
y|Y|yes|YES) return 0;;
*) return 1;;
esac
}

step_binexec() {
echo "第 1 步：开启 Serv00 运行自有程序的权限"
if command -v devil >/dev/null 2>&1; then
if devil binexec on; then
echo "devil binexec 已开启。如果是刚开的，退出重登一次 SSH 再继续，后面步骤才生效。"
else
echo "devil binexec on 失败了，先去 Serv00 面板确认这台账号有没有开这个权限，再重跑这一步。"
return 1
fi
else
echo "找不到 devil 命令，跳过这一步，直接继续；如果后面启动失败，再回来看这一步。"
fi
return 0
}

step_python() {
echo "第 2 步：检查 Python"
if ! command -v python3 >/dev/null 2>&1; then
echo "找不到 python3，停在这里了。"
return 1
fi
python3 --version
echo "Mail2Telegram 用默认的 Python 3.11 就够，不用特意换 3.13/3.14/3.15。"
return 0
}

step_install() {
echo "第 3 步：拉代码、建虚拟环境、装依赖"
if [ -d "$DIR" ] && [ -f "$DIR/main.py" ]; then
echo "已经有 $DIR，而且 main.py 在，跳过克隆，不覆盖你现有的配置。"
else
echo "正在克隆 $REPO 到 $DIR..."
if ! git clone "$REPO" "$DIR"; then
echo "克隆失败了，停在这里了。请检查网络和 git，再重跑。"
return 1
fi
fi
if [ ! -x "$VENV/bin/python" ]; then
echo "正在建虚拟环境 $VENV..."
if ! python3 -m venv "$VENV"; then
echo "建虚拟环境失败了，停在这里了。"
return 1
fi
else
echo "已经有虚拟环境 $VENV，跳过新建。"
fi
echo "正在装依赖（requirements.txt），要下载一会儿，别关终端..."
if ! "$VENV/bin/pip" install -r "$DIR/requirements.txt"; then
echo "装依赖失败了，停在这里了。不要往下走，先把上面最后几行报错贴出来看。"
return 1
fi
echo "依赖装好了。"
return 0
}

write_helpers() {
echo "第 4 步：写后台脚本 run.sh / start.sh / stop.sh / 看门狗"
cat > "$DIR/run.sh" <<'EOF'
#!/bin/sh
# Serv00 用：代替 docker-compose / systemd
cd "$(dirname "$0")" || exit 1
export LANGUAGE=Chinese
export TIMEZONE=Asia/Shanghai
export ENABLE_LOGGING=true
# 关键：这个项目里 ENABLE_EVC 默认是 true，不关会去调验证码提取服务，Serv00 上直接关掉
export ENABLE_EVC=false
if [ -x "$HOME/mail2tg-venv/bin/python" ]; then
PY="$HOME/mail2tg-venv/bin/python"
else
PY="python3"
fi
exec "$PY" main.py
EOF
cat > "$DIR/start.sh" <<'EOF'
#!/bin/sh
if pgrep -f "mail2tg/main.py" >/dev/null 2>&1; then
echo "mail2tg already running"
exit 0
fi
cd "$HOME/mail2tg" || exit 1
nohup./run.sh >> "$HOME/mail2tg/mail2tg.log" 2>&1 &
echo "mail2tg started, log: $HOME/mail2tg/mail2tg.log"
EOF
cat > "$DIR/stop.sh" <<'EOF'
#!/bin/sh
# 注意：先把 crontab 里的 check_mail2tg.sh 那两行去掉，不然 5 分钟后看门狗又会把它拉起来
pkill -f "mail2tg/main.py"
echo "mail2tg stopped"
EOF
cat > "$WATCHDOG" <<'EOF'
#!/bin/sh
# Serv00 看门狗：代替 systemd，crontab 每 5 分钟和 @reboot 各跑一次
if ! pgrep -f "mail2tg/main.py" >/dev/null 2>&1; then
cd "$HOME/mail2tg" || exit 1
nohup./run.sh >> "$HOME/mail2tg/mail2tg.log" 2>&1 &
fi
EOF
chmod +x "$DIR/run.sh" "$DIR/start.sh" "$DIR/stop.sh" "$WATCHDOG"
echo "后台脚本写好了。"
return 0
}

setup_crontab() {
echo ""
local tmp=""
tmp="$(mktemp)" || { echo "建临时文件失败，crontab 没改。"; return 1;}
crontab -l 2>/dev/null | grep -v "check_mail2tg.sh" > "$tmp" || true
printf '%s\n' "@reboot sleep 30; /bin/sh \$HOME/check_mail2tg.sh" >> "$tmp"
printf '%s\n' "*/5 * * * * /bin/sh \$HOME/check_mail2tg.sh" >> "$tmp"
if ! crontab "$tmp"; then
echo "写 crontab 失败了，看门狗没装上，先手动检查 crontab -l。"
rm -f "$tmp"
return 1
fi
rm -f "$tmp"
if crontab -l 2>/dev/null | grep -q "check_mail2tg.sh"; then
echo "crontab 看门狗装好了：@reboot 一条，每 5 分钟一条。"
return 0
else
echo "crontab 写完后查不到看门狗那两行，算失败，别当成装好了。"
return 1
fi
}

remove_crontab() {
local tmp=""
tmp="$(mktemp)" || return 1
crontab -l 2>/dev/null | grep -v "check_mail2tg.sh" > "$tmp" || true
crontab "$tmp" 2>/dev/null || true
rm -f "$tmp"
}

# 选邮箱服务商，输出 host、port、密码提示到全局变量 P_HOST P_PORT P_HINT，失败返回 1
pick_provider() {
echo "选邮箱服务商："
echo " 1) Gmail"
echo " 2) QQ 邮箱"
echo " 3) 163 邮箱"
echo " 4) 新浪 sina"
echo " 5) cock.li"
echo " 6) 2925.com"
echo " 7) Outlook / Hotmail（先看警告）"
echo " 8) 自定义 IMAP"
echo " 0) 不加了，结束添加"
local choice=""
read -r -p "输入序号: " choice || true
case "$choice" in
0) return 2;;
1) P_HOST="imap.gmail.com"; P_PORT="993"; P_HINT="Gmail 应用专用密码（不是登录密码，先开 2FA 再生成）";;
2) P_HOST="imap.qq.com"; P_PORT="993"; P_HINT="QQ 授权码（网页设置里开 IMAP/SMTP 后生成的，不是 QQ 密码）";;
3) P_HOST="imap.163.com"; P_PORT="993"; P_HINT="163 客户端授权密码（网页设置里开 IMAP/SMTP 后设置的）";;
4)
echo " 新浪后缀选一个：1) sina.com 2) sina.cn 3) vip.sina.com"
local s=""
read -r -p "输入序号: " s || true
case "$s" in
1) P_HOST="imap.sina.com";;
2) P_HOST="imap.sina.cn";;
3) P_HOST="imap.vip.sina.com";;
*) echo "没选对，跳过这一个。"; return 1;;
esac
P_PORT="993"; P_HINT="新浪邮箱密码或客户端授权码（以后台给的为准）"
;;
5) P_HOST="mail.cock.li"; P_PORT="993"; P_HINT="cock.li 密码。注意：服务器是 mail.cock.li，不是 imap.cock.li";;
6) P_HOST="imap.2925.com"; P_PORT="993"; P_HINT="2925 主邮箱密码（子邮箱不能直接登录客户端，登录名填主邮箱完整地址）。如果这台连不上，再试 imap.2925mail.com";;
7)
echo "警告：项目作者已注明，微软改了连接方式后 Outlook 在这个项目里直接连不上。"
echo "建议：先在 Outlook 网页版里转发到 Gmail / QQ / 163 其中一家，再由那家推到 Telegram。"
if ! ask_yes_no "你还是一定要把 Outlook / Hotmail 加进去试试吗？"; then
echo "跳过 Outlook，回到选服务商。"
return 1
fi
P_HOST="outlook.office365.com"; P_PORT="993"; P_HINT="Outlook 密码（大概率会登录失败，先有心理准备）"
;;
8)
read -r -p "IMAP 服务器（例如 imap.example.com）: " P_HOST || true
read -r -p "IMAP 端口（回车默认 993）: " P_PORT || true
[ -z "$P_PORT" ] && P_PORT="993"
P_HINT="这个服务商的密码或授权码"
if [ -z "$P_HOST" ]; then echo "服务器没填，跳过。"; return 1; fi
case "$P_PORT" in
''|*[!0-9]*) echo "端口不是数字，跳过。"; return 1;;
esac
;;
*) echo "没选对，跳过这一个。"; return 1;;
esac
return 0
}

configure_wizard() {
echo "一步一步填，密码不会回显，也不会打印出来"
echo "第 1 步：Telegram 机器人"
echo " 先去 @BotFather 建机器人，拿到 Token；再去机器人私聊里发 /start，不然它给你发不了消息。"
local token="" chat_id="" junk_id=""
read -r -s -p "Bot Token（输入时不显示，输完按回车）: " token || true
echo ""
if [ -z "$token" ]; then echo "Token 没填，配置没写，停在这里了。"; return 1; fi
case "$token" in
*:*)
;;
*)
echo "提醒：Bot Token 一般是 数字:字母 的样子，你填的好像没有冒号。"
if ! ask_yes_no "还要继续用这个 Token 吗？"; then echo "配置没写，回去重填。"; return 1; fi
;;
esac
read -r -p "第 2 步：Telegram 聊天 ID（收邮件的那个数字 ID，例如你自己的用户 ID）: " chat_id || true
case "$chat_id" in
''|*[!0-9-]*) echo "聊天 ID 不是数字，配置没写。"; return 1;;
esac
read -r -p "第 3 步：垃圾邮件聊天 ID（不想收垃圾就直接回车跳过）: " junk_id || true
if [ -n "$junk_id" ]; then
case "$junk_id" in
''|*[!0-9-]*) echo "垃圾邮件 ID 不是数字，配置没写。"; return 1;;
esac
fi

echo "第 4 步：加邮箱，可以加多个，加完选 0 结束"
echo " 建议第一次先加 1-2 个已经拿到授权码的，跑通了再回来加剩下的。"
local entries="" count=0 summary=""
while true; do
pick_provider
local rc=$?
if [ "$rc" -eq 2 ]; then
break
fi
if [ "$rc" -ne 0 ]; then
continue
fi
local email="" pw=""
read -r -p "邮箱完整地址: " email || true
case "$email" in
*@*.*);;
*) echo "邮箱格式不对，跳过这一个。"; continue;;
esac
echo "密码提示：$P_HINT"
read -r -s -p "密码 / 授权码（输入时不显示，输完按回车）: " pw || true
echo ""
if [ -z "$pw" ]; then echo "密码没填，跳过这一个。"; continue; fi
entries="$entries
{
'EMAIL': '$(py_escape "$email")',
'PASSWORD': '$(py_escape "$pw")',
'IMAP_SERVER': '$(py_escape "$P_HOST")',
'IMAP_SERVER_PORT': $P_PORT,
},"
summary="$summary
- $email ($P_HOST:$P_PORT)"
count=$((count + 1))
echo "已加入第 $count 个：$email"
if ! ask_yes_no "还要再加一个邮箱吗？"; then
break
fi
done

if [ "$count" -eq 0 ]; then
echo "一个邮箱都没加，配置没写。"
return 1
fi

if [ -f "$CONFIG" ]; then
cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S)" && echo "旧 config.py 已备份到同目录的.bak 文件。"
fi
cat > "$CONFIG" <<EOF
EMAILS = [$entries
]

TELEGRAM_BOT_TOKEN = '$(py_escape "$token")'
TELEGRAM_CHAT_ID = '$chat_id'
TELEGRAM_JUNK_CHAT_ID = '$junk_id'

RETRY_LIMIT = 5
RETRY_DELAY = 5
RECONNECT_INTERVAL = 1800
RETRY_PAUSE = 600
EOF
chmod 600 "$CONFIG"
if ! "$VENV/bin/python" -m py_compile "$CONFIG" 2>/dev/null && ! python3 -m py_compile "$CONFIG" 2>/dev/null; then
echo "config.py 写完后语法检查没过，别启动，先检查上面那一步是不是有特殊字符。"
return 1
fi
echo "配置写好了，共 $count 个邮箱，Token 和密码都没有打印出来：$summary"
echo "聊天 ID：$chat_id"
return 0
}

start_service() {
if is_running; then
echo "已经在跑了，不用重复启动。"
return 0
fi
if [ ! -f "$CONFIG" ]; then
echo "还没有 $CONFIG，先选 2 走配置向导。"
return 1
fi
if [ ! -x "$DIR/start.sh" ]; then
echo "还没有启动脚本，先选 1 走一键部署，或者先写后台脚本。"
return 1
fi
echo "正在启动后台服务..."
(cd "$DIR" &&./start.sh)
sleep 3
if is_running; then
echo "启动成功，正在跑了。日志：$DIR/mail2tg.log"
return 0
else
echo "启动后查不到进程，算失败，看日志最后 20 行："
tail -20 "$DIR/mail2tg.log" 2>/dev/null || echo "还没有 mail2tg.log"
tail -20 "$DIR/log/email_checker.log" 2>/dev/null || true
return 1
fi
}

stop_service() {
if ! is_running; then
echo "本来就没在跑。"
else
pkill -f "mail2tg/main.py" || true
sleep 2
if is_running; then
echo "停是停了命令发了，但进程还在，手动再看一下 pgrep -f mail2tg/main.py。"
return 1
fi
echo "已经停掉了。"
fi
if ask_yes_no "要不要同时把 crontab 看门狗也去掉？（去掉后它就不会在 5 分钟后又被拉起来）"; then
remove_crontab
echo "看门狗 crontab 已去掉。"
else
echo "看门狗还留着，5 分钟后它会再把服务拉起来，这就是你选的‘只停一次’。"
fi
return 0
}

show_status() {
echo "---- 状态 ----"
echo "目录：$DIR（存在：$( [ -d "$DIR" ] && echo 是 || echo 否)）"
echo "虚拟环境：$VENV（存在：$( [ -x "$VENV/bin/python" ] && echo 是 || echo 否)）"
echo "配置：$CONFIG（存在：$( [ -f "$CONFIG" ] && echo 是 || echo 否)，权限：$( ls -l "$CONFIG" 2>/dev/null | awk '{print $1}' || echo -)）"
if is_running; then
echo "进程：在跑"
pgrep -af "mail2tg/main.py" || true
else
echo "进程：没在跑"
fi
echo "crontab 看门狗："
crontab -l 2>/dev/null | grep "check_mail2tg.sh" || echo "（没有）"
echo "---- 最近日志（mail2tg.log 最后 20 行）----"
tail -20 "$DIR/mail2tg.log" 2>/dev/null || echo "（还没有 mail2tg.log）"
return 0
}

foreground_test() {
if [ ! -f "$CONFIG" ]; then
echo "还没有 $CONFIG，先选 2 走配置向导。"
return 1
fi
local py="python3"
[ -x "$VENV/bin/python" ] && py="$VENV/bin/python"
echo "前台测试开始：TG 收到“登录成功”就说明通了，再给邮箱发封测试信看推不推。"
echo "想停就按 Ctrl+C，停了不会进后台。"
(cd "$DIR" && LANGUAGE=Chinese TIMEZONE=Asia/Shanghai ENABLE_LOGGING=true ENABLE_EVC=false "$py" main.py)
echo "前台测试已退出。"
return 0
}

one_click_deploy() {
echo "================ 一键部署 ================"
echo "按顺序走：权限 → Python → 拉代码装依赖 → 写后台脚本 → 填配置 → 启动"
step_binexec || { echo "一键部署停在第 1 步了。"; return 1;}
step_python || { echo "一键部署停在第 2 步了。"; return 1;}
step_install || { echo "一键部署停在第 3 步了。"; return 1;}
write_helpers || { echo "一键部署停在写后台脚本了。"; return 1;}
configure_wizard || { echo "一键部署停在配置向导了，依赖和脚本已经在了，改好再选 2 重填就行。"; return 1;}
echo "配置好了，下面选怎么启动："
echo " 1) 先前台测试（推荐第一次，Ctrl+C 停）"
echo " 2) 直接启动后台 + 装看门狗"
echo " 3) 先不启动，只保存配置"
local s=""
read -r -p "输入序号: " s || true
case "$s" in
1)
foreground_test
if ask_yes_no "前台测试通了吗？通了就现在转后台 + 装看门狗？"; then
setup_crontab || return 1
start_service || return 1
else
echo "先不转后台，配置已保存，修好再选 4 启动。"
fi
;;
2)
setup_crontab || return 1
start_service || return 1
;;
3)
echo "只保存了配置，没启动。以后选 4 启动，选 8 装看门狗。"
;;
*)
echo "没选对，默认只保存配置，没启动。"
;;
esac
echo "一键部署走到头了。用菜单 7 查状态、看日志确认。"
return 0
}

uninstall_service() {
echo "一键卸载会：停服务、去掉看门狗 crontab、删掉 ~/mail2tg、~/mail2tg-venv、~/check_mail2tg.sh。"
echo "注意：这个脚本文件本身不会被删，想删手动 rm ~/mail2tg.sh。"
read -r -p "确认卸载请输入 yes： " ans || true
if [ "$ans"!= "yes" ]; then
echo "没输入 yes，取消卸载。"
return 0
fi
pkill -f "mail2tg/main.py" 2>/dev/null || true
remove_crontab
rm -rf "$DIR" "$VENV" "$WATCHDOG"
echo "卸载完了。如果以后不用这些邮箱授权码了，记得去各邮箱后台吊销授权码 / 应用专用密码，删本地文件不等于吊销。"
return 0
}

while true; do
echo ""
echo "================ Mail2Telegram Serv00 一键部署 ================"
echo " 1) 一键部署（一步一步提示：权限 → 依赖 → 机器人 → 邮箱 → 启动）"
echo " 2) 只填 / 改配置（重新走机器人 + 邮箱向导，旧配置会自动备份）"
echo " 3) 前台测试运行（Ctrl+C 停止，不进后台）"
echo " 4) 启动后台服务"
echo " 5) 停止服务"
echo " 6) 重启服务"
echo " 7) 查看状态和日志"
echo " 8) 设置 / 检查看门狗 crontab"
echo " 9) 一键卸载"
echo " 0) 退出"
read -r -p "输入序号: " choice || break
case "$choice" in
1) one_click_deploy; pause;;
2)
if [ ! -d "$DIR" ]; then echo "还没有 $DIR，先选 1 一键部署。"; else
if [ ! -x "$VENV/bin/python" ]; then echo "还没有虚拟环境，先选 1 一键部署。"; else
configure_wizard
fi
fi
pause
;;
3) foreground_test; pause;;
4) start_service; pause;;
5) stop_service; pause;;
6) stop_service; start_service; pause;;
7) show_status; pause;;
8) setup_crontab; pause;;
9) uninstall_service; pause;;
0) echo "退出。"; break;;
*) echo "没这个序号，重新选。";;
esac
done
