#!/usr/bin/env bash
# Mail2Telegram Serv00 一键部署脚本（带菜单、一步一步提示）
#
# 运行方法（不要用 bash <(curl...) 这种方式，提示输入会出问题）：
# 1. 把这个文件传到 Serv00 家目录，变成 ~/mail2tg.sh
# 2. chmod +x ~/mail2tg.sh
# 3. ./mail2tg.sh
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
# 各家 IMAP 按官网最新设置：Gmail imap.gmail.com:993、QQ imap.qq.com:993、
# 163 imap.163.com:993、新浪按后缀 imap.sina.com / imap.sina.cn / imap.vip.sina.com /
# imap.vip.sina.cn:993、cock.li mail.cock.li:993、2925 imap.2925.com:993（备选 imap.2925mail.com）。
# Outlook / Hotmail 只走 OAuth：个人账号自 2024-09-16 起密码 IMAP 已停用，
# 只认 OAuth2（outlook.office365.com:993 SSL/TLS，XOAUTH2）。
# 本脚本自带 OAuth 桥接：生成 oauth_helper.py（令牌刷新 + XOAUTH2 登录）
# 和 oauth_outlook.py（设备码授权），并给 main.py 打补丁，只把两处
# server.login(...) 换成 oauth_helper.imap_login(...)，其他邮箱仍走密码登录。
# 兼容补丁：上游用 IDLE + SEARCH 监听，2925 不认 SEARCH、新浪会断 IDLE、
# cock.li 的 LIST 分隔符是 "." 不是 "/"，所以补丁把监听改成每 60 秒轮询
# （SELECT 取邮件数 + FETCH 取新信，不调 SEARCH/IDLE），并按 LIST 行里
# 最后一个带引号的名字解析文件夹。
# Telegram 命令：机器人除了推送，还能回命令。只认 TELEGRAM_CHAT_ID 一个人：
# /ls 看邮箱和文件夹，/show 邮箱号 文件夹号 条数 看最近的信，
# /del 邮箱号 文件夹号 序号 删信（要再发 /delok 确认，5 分钟内有效）。
# 令牌存 ~/mail2tg/oauth_tokens.json（600），access token 约 1 小时过期时
# 自动用 refresh_token 刷新；refresh token 被吊销/过期就用菜单 10 重新授权。
# 授权前要先在 Microsoft Entra 自己注册一个应用（公开客户端，
# 权限 Office 365 Exchange Online > IMAP.AccessAsUser.All + offline_access），
# 拿到 Application (client) ID；不要用别人的 client ID，也不要把令牌发到聊天里。

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
nohup ./run.sh >> "$HOME/mail2tg/mail2tg.log" 2>&1 &
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
nohup ./run.sh >> "$HOME/mail2tg/mail2tg.log" 2>&1 &
fi
EOF
chmod +x "$DIR/run.sh" "$DIR/start.sh" "$DIR/stop.sh" "$WATCHDOG"
echo "后台脚本写好了。"
return 0
}

write_oauth_files() {
echo "写 OAuth 桥接文件 oauth_helper.py / oauth_outlook.py"
cat > "$DIR/oauth_helper.py" <<'OAUTH_HELPER_EOF'
#!/usr/bin/env python3
"""Outlook/Hotmail OAuth helper for Mail2Telegram (Serv00).

Only stdlib is used, so no extra pip package is needed.

What it does:
- Reads refresh/access tokens from oauth_tokens.json next to this file
  (chmod 600, one entry per mailbox, keyed by full email address).
- Refreshes the access token when it is expired or about to expire
  (access tokens live about 1 hour; the refresh token is what keeps
  the background service running unattended).
- Logs in to IMAP with SASL XOAUTH2 instead of a password:
  base64("user=<email>\\x01auth=Bearer <access_token>\\x01\\x01")
  against outlook.office365.com:993.

What it does NOT do:
- It never asks for, stores, or sends the mailbox password.
- It never invents a token. If there is no token entry for the mailbox,
  or the refresh token is rejected by Microsoft (invalid_grant),
  it raises an error and the caller must re-authorise with
  oauth_outlook.py (device-code flow). It must not fall back to a
  password login for an OAuth account: that login is disabled by
  Microsoft and would only hide the real error.

Scope used everywhere (Microsoft Learn, IMAP):
  https://outlook.office.com/IMAP.AccessAsUser.All
plus offline_access (to get a refresh token), openid, profile, email.
Tenant default is "consumers" (personal Outlook/Hotmail/Live only).
Use "common" only if the mailbox is a work/school Microsoft 365 account.
"""

import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

SCOPE = (
    "https://outlook.office.com/IMAP.AccessAsUser.All "
    "offline_access openid profile email"
)
DEFAULT_TENANT = "consumers"
TOKEN_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "oauth_tokens.json"
)
# Refresh a little early so a token does not die mid-IMAP-session.
REFRESH_MARGIN_SECONDS = 300


def _token_url(tenant):
    return "https://login.microsoftonline.com/%s/oauth2/v2.0/token" % (
        tenant or DEFAULT_TENANT
    )


def load_tokens():
    try:
        with open(TOKEN_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return {}
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_tokens(tokens):
    tmp = TOKEN_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(tokens, f, indent=2, sort_keys=True)
        f.write("\n")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, TOKEN_FILE)
    try:
        os.chmod(TOKEN_FILE, 0o600)
    except OSError:
        pass


def xoauth2_string(email, access_token):
    """Return the base64 XOAUTH2 initial response for one mailbox."""
    raw = "user=%s\x01auth=Bearer %s\x01\x01" % (email, access_token)
    return base64.b64encode(raw.encode("utf-8")).decode("ascii")


def _post_token(tenant, data):
    body = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(
        _token_url(tenant),
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            err = json.loads(e.read().decode("utf-8"))
        except Exception:
            err = {}
        # Never log token values; only the error code/description.
        raise RuntimeError(
            "Microsoft token endpoint returned %s: %s"
            % (
                err.get("error", "http_%s" % e.code),
                err.get("error_description", "")[:300],
            )
        )


def refresh_access_token(email, entry):
    """Refresh one entry in place and return the new access token."""
    client_id = entry.get("client_id")
    refresh_token = entry.get("refresh_token")
    tenant = entry.get("tenant") or DEFAULT_TENANT
    if not client_id or not refresh_token:
        raise RuntimeError(
            "Outlook OAuth entry for %s has no client_id/refresh_token; "
            "re-authorise with: python3 oauth_outlook.py %s" % (email, email)
        )
    result = _post_token(
        tenant,
        {
            "client_id": client_id,
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "scope": SCOPE,
        },
    )
    if "access_token" not in result:
        raise RuntimeError(
            "Microsoft refresh failed for %s: %s"
            % (email, result.get("error", "no access_token in response"))
        )
    entry["access_token"] = result["access_token"]
    # Microsoft may rotate the refresh token; keep the new one if given.
    if result.get("refresh_token"):
        entry["refresh_token"] = result["refresh_token"]
    entry["expires_at"] = time.time() + int(result.get("expires_in", 3600))
    entry["tenant"] = tenant
    entry["client_id"] = client_id
    tokens = load_tokens()
    tokens[email] = entry
    save_tokens(tokens)
    return entry["access_token"]


def get_access_token(email, tenant=None, client_id=None):
    """Return a usable access token for email, refreshing if needed."""
    tokens = load_tokens()
    entry = tokens.get(email)
    if not entry:
        raise RuntimeError(
            "No Outlook OAuth token for %s. Run first: "
            "python3 oauth_outlook.py %s" % (email, email)
        )
    if client_id:
        entry["client_id"] = client_id
    if tenant:
        entry["tenant"] = tenant
    access_token = entry.get("access_token")
    expires_at = float(entry.get("expires_at") or 0)
    if access_token and expires_at - time.time() > REFRESH_MARGIN_SECONDS:
        return access_token
    return refresh_access_token(email, entry)


def is_oauth_account(email_config):
    return bool(email_config.get("USE_OAUTH"))


def imap_login(server, email_config):
    """Log one IMAP server in, OAuth or password, and say which was used.

    Returns "xoauth2" or "password". Raises on failure; for an OAuth
    account it never falls back to password login.
    """
    email = email_config["EMAIL"]
    if is_oauth_account(email_config):
        token = get_access_token(
            email,
            tenant=email_config.get("OAUTH_TENANT") or DEFAULT_TENANT,
            client_id=email_config.get("OAUTH_CLIENT_ID"),
        )
        auth_str = xoauth2_string(email, token)
        # imaplib/imaplib2: authenticate(mechanism, authobject).
        # The callable receives the server challenge and must return
        # the base64 XOAUTH2 response bytes.
        server.authenticate("XOAUTH2", lambda _resp: auth_str.encode("ascii"))
        return "xoauth2"
    server.login(email, email_config["PASSWORD"])
    return "password"
OAUTH_HELPER_EOF
cat > "$DIR/oauth_outlook.py" <<'OAUTH_OUTLOOK_EOF'
#!/usr/bin/env python3
"""Authorise one Outlook/Hotmail mailbox for Mail2Telegram via OAuth.

Device-code flow (Microsoft identity platform, RFC 8628):
  1. This script asks Microsoft for a device code + short user code.
  2. YOU open https://microsoft.com/devicelogin in your own browser,
     enter that user code, sign in as the Outlook mailbox, and consent
     to the IMAP permission. The code is valid for 15 minutes.
  3. This script polls Microsoft until you finish, then saves the
     access + refresh tokens to oauth_tokens.json (chmod 600, next
     to this file). It never prints the tokens.

Before running this, register your own app once in Microsoft Entra:
  - https://entra.microsoft.com -> App registrations -> New registration
  - Name: anything, e.g. Mail2Telegram
  - Supported account types: Personal Microsoft accounts only
  - Redirect URI: Public client/native (mobile & desktop) -> http://localhost
  - Authentication -> Allow public client flows: Yes
  - API permissions -> Add a permission -> APIs my organization uses
    -> Office 365 Exchange Online -> Delegated permissions
    -> IMAP.AccessAsUser.All -> Add permissions
  - Copy the Application (client) ID. That is the only ID this script
    needs. There is no client secret for a public client; never create
    one for this, and never paste any token/secret into a chat.

Safety: only enter the user code on microsoft.com/devicelogin, in a
browser you opened yourself, and only for the app name you just
registered. A device code is as powerful as a login while it is live.

Usage:
  python3 oauth_outlook.py you@outlook.com
  python3 oauth_outlook.py you@hotmail.com <client-id> [consumers|common]
  python3 oauth_outlook.py you@outlook.com <client-id> --no-test

After success, the mailbox is added to Mail2Telegram by the menu
script (pick_provider option 7), or by hand in config.py:
  {'EMAIL': 'you@outlook.com', 'PASSWORD': '',
   'IMAP_SERVER': 'outlook.office365.com', 'IMAP_SERVER_PORT': 993,
   'USE_OAUTH': True, 'OAUTH_TENANT': 'consumers',
   'OAUTH_CLIENT_ID': '<the same client id>'}
"""

import base64
import imaplib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from oauth_helper import (
    DEFAULT_TENANT,
    SCOPE,
    TOKEN_FILE,
    load_tokens,
    save_tokens,
    xoauth2_string,
)

DEVICE_CODE_URL_TMPL = (
    "https://login.microsoftonline.com/%s/oauth2/v2.0/devicecode"
)
TOKEN_URL_TMPL = "https://login.microsoftonline.com/%s/oauth2/v2.0/token"
IMAP_HOST = "outlook.office365.com"
IMAP_PORT = 993


def _post(url, data):
    body = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            err = json.loads(e.read().decode("utf-8"))
        except Exception:
            err = {}
        raise RuntimeError(
            "Microsoft returned %s: %s"
            % (
                err.get("error", "http_%s" % e.code),
                err.get("error_description", "")[:300],
            )
        )


def test_imap(email, access_token):
    """One real IMAP XOAUTH2 login, to prove the token/scope work."""
    print("正在用新令牌试一次 IMAP 登录（outlook.office365.com:993）……")
    server = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT)
    try:
        auth_str = xoauth2_string(email, access_token)
        server.authenticate("XOAUTH2", lambda _resp: auth_str.encode("ascii"))
        status, _ = server.select("INBOX")
        print("IMAP 测试：登录成功，INBOX 选择结果：%s" % status)
        if status != "OK":
            print("警告：登录通了，但选 INBOX 不是 OK，先看日志再决定要不要转后台。")
    finally:
        try:
            server.logout()
        except Exception:
            pass


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 2
    email = argv[1].strip()
    client_id = argv[2].strip() if len(argv) > 2 else ""
    tenant = DEFAULT_TENANT
    no_test = False
    for arg in argv[2:]:
        if arg == "--no-test":
            no_test = True
        elif arg in ("consumers", "common", "organizations"):
            tenant = arg
    if "@" not in email:
        print("邮箱格式不对：%s" % email)
        return 1
    if not client_id:
        print("先去 Microsoft Entra 注册应用，拿到 Application (client) ID 再来。")
        print("步骤见本文件开头的说明；不要用别人的 client ID，也不要在这里贴令牌。")
        client_id = input("Application (client) ID: ").strip()
    if not client_id:
        print("client ID 没填，停在这里了。")
        return 1
    if tenant not in ("consumers", "common", "organizations"):
        tenant = DEFAULT_TENANT

    print("第 1 步：向 Microsoft 要设备码……")
    dc = _post(
        DEVICE_CODE_URL_TMPL % tenant,
        {"client_id": client_id, "scope": SCOPE},
    )
    if "device_code" not in dc or "user_code" not in dc:
        print("要设备码失败：%s" % dc.get("error", dc))
        return 1
    print("")
    print("第 2 步：在你自己的浏览器里打开：%s" % dc.get("verification_uri", "https://microsoft.com/devicelogin"))
    print("输入这串用户码（15 分钟内有效）：%s" % dc["user_code"])
    print("用 %s 这个账号登录并同意 IMAP 权限，应用名要和你刚注册的一致。" % email)
    print("只在 microsoft.com/devicelogin 输码，别在别的页面输。")
    print("")
    print("第 3 步：等你授权完，本脚本自动去换令牌（按 Ctrl+C 可取消）……")
    device_code = dc["device_code"]
    interval = int(dc.get("interval", 5))
    expires_in = int(dc.get("expires_in", 900))
    deadline = time.time() + expires_in
    while time.time() < deadline:
        time.sleep(interval)
        try:
            result = _post(
                TOKEN_URL_TMPL % tenant,
                {
                    "client_id": client_id,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "device_code": device_code,
                },
            )
        except RuntimeError as e:
            # authorization_pending / slow_down come back as errors.
            msg = str(e)
            if "authorization_pending" in msg:
                continue
            if "slow_down" in msg:
                interval += 5
                continue
            print("换令牌失败：%s" % msg)
            print("如果是 authorization_declined / expired_token，重新跑一次本脚本。")
            return 1
        if "access_token" not in result:
            print("换令牌返回里没有 access_token：%s" % result.get("error", result))
            return 1
        tokens = load_tokens()
        tokens[email] = {
            "client_id": client_id,
            "tenant": tenant,
            "access_token": result["access_token"],
            "refresh_token": result.get("refresh_token", ""),
            "expires_at": time.time() + int(result.get("expires_in", 3600)),
            "scope": SCOPE,
        }
        save_tokens(tokens)
        print("授权成功，令牌已存到 %s（权限 600，令牌本身没有打印出来）。" % TOKEN_FILE)
        if not tokens[email]["refresh_token"]:
            print("警告：这次没拿到 refresh_token（可能缺 offline_access），令牌过期后要重新授权。")
        if no_test:
            print("已跳过 IMAP 测试。跑前台测试时再验证。")
        else:
            try:
                test_imap(email, result["access_token"])
            except Exception as e:
                print("IMAP 测试失败：%s" % e)
                print("令牌已保存，但先别转后台：检查 Entra 应用有没有加 IMAP.AccessAsUser.All，")
                print("以及 Outlook 网页版设置 > 邮件 > 转发和 IMAP 里 IMAP 是不是开着。")
                return 1
        print("完成。回菜单里选 7 把这个邮箱加进 config.py（USE_OAUTH），再选 3 前台测试。")
        return 0
    print("设备码过期了（15 分钟），重新跑一次本脚本。")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
OAUTH_OUTLOOK_EOF
chmod +x "$DIR/oauth_outlook.py"
if ! "$VENV/bin/python" -m py_compile "$DIR/oauth_helper.py" "$DIR/oauth_outlook.py" 2>/dev/null && ! python3 -m py_compile "$DIR/oauth_helper.py" "$DIR/oauth_outlook.py"; then
echo "OAuth 文件语法检查没过，别继续，先看上面报错。"
return 1
fi
echo "OAuth 桥接文件写好了。"
return 0
}

patch_main_py() {
echo "给 main.py 打补丁：OAuth 登录 + 兼容轮询（不用 SEARCH/IDLE）+ Telegram 命令"
if [ ! -f "$DIR/main.py" ]; then echo "没有 $DIR/main.py，先拉代码。"; return 1; fi
if grep -q "oauth_helper.imap_login" "$DIR/main.py" 2>/dev/null && grep -q "_selected_count" "$DIR/main.py" 2>/dev/null && grep -q "run_command_bot" "$DIR/main.py" 2>/dev/null; then echo "补丁已经打过了，跳过。"; return 0; fi
local bak="$DIR/main.py.bak.$(date +%Y%m%d%H%M%S)"
cp "$DIR/main.py" "$bak" || { echo "备份 main.py 失败，补丁没打。"; return 1; }
if ! python3 - "$DIR" <<'PYEOF'
import os, sys
# DIR 是 shell 变量，没有 export，子进程 python 看不到 os.environ["DIR"]，
# 所以改成命令行参数传进来（s13 上就是在这里报 KeyError: 'DIR'）。
path = os.path.join(sys.argv[1], "main.py")
src = open(path, encoding="utf-8").read()

# 1) OAuth：两处密码登录改成 oauth_helper.imap_login（已打过就跳过这步）
old = "server.login(email_config['EMAIL'], email_config['PASSWORD'])"
count = src.count(old)
if count == 2:
    src = src.replace(old, "oauth_helper.imap_login(server, email_config)")
elif count != 0:
    print("补丁停：main.py 里找到 %d 处密码登录，预期 2 处或 0 处，一处都没改。" % count)
    sys.exit(1)
anchor = "from tools.extract_verification_code import extract_verification_code"
if "import oauth_helper" not in src:
    if anchor not in src:
        print("补丁停：找不到 import 锚点，一处都没改。")
        sys.exit(1)
    src = src.replace(anchor, anchor + "\nimport oauth_helper  # Serv00 补丁：Outlook 走 XOAUTH2，其他邮箱仍走密码登录", 1)

# 2) 兼容：LIST 文件夹名解析只认 "/"，cock.li 的分隔符是 "."，
#    会把整行当文件夹名去 select。改成取 LIST 行里最后一个带引号的名字。
old_parse = "folder_name = folder.decode().split(' \"/\" ')[-1].strip('\"')"
if old_parse in src:
    src = src.replace(old_parse, "folder_name = _parse_list_folder_name(folder)")
elif "_parse_list_folder_name(folder)" not in src:
    print("补丁停：找不到 LIST 解析行，一处都没改。")
    sys.exit(1)

# 3) 插入两个小工具函数，放在 def monitor_email 前面
if "def _parse_list_folder_name" not in src:
    helpers = '''def _parse_list_folder_name(folder):
    # LIST 行分隔符可能是 / . :，上游只认 "/" 会把整行当文件夹名。
    # 不管分隔符是什么，取行里最后一个带引号的名字。
    text = folder.decode(errors="replace") if isinstance(folder, bytes) else str(folder)
    quoted = re.findall(r'"([^"]*)"', text)
    if quoted:
        return quoted[-1]
    return text.rsplit(" ", 1)[-1].strip('"')


def _selected_count(server, folder):
    # 只用 SELECT 取邮件数，不用 SEARCH（2925 不认 SEARCH）。
    # select 返回如 [b'6 EXISTS']；拿不到数时再试 STATUS。
    status, data = server.select(folder)
    if status != "OK":
        raise Exception(f"无法选择文件夹 {folder}: {data}")
    for item in data or []:
        raw = item if isinstance(item, bytes) else str(item).encode()
        m = re.search(rb"(\\d+)\\s+EXISTS", raw)
        if m:
            return int(m.group(1))
    status, data = server.status(folder, "(MESSAGES)")
    if status == "OK" and data:
        raw = data[0] if isinstance(data[0], bytes) else str(data[0]).encode()
        m = re.search(rb"MESSAGES\\s+(\\d+)", raw)
        if m:
            return int(m.group(1))
    raise Exception(f"无法从 select/STATUS 取邮件数: {data}")


'''
    if "def monitor_email" not in src:
        print("补丁停：找不到 def monitor_email，一处都没改。")
        sys.exit(1)
    src = src.replace("def monitor_email", helpers + "def monitor_email", 1)

# 4) 兼容：把 IDLE+SEARCH 的监听改成轮询。
#    2925 不支持 SEARCH，新浪会断 IDLE，轮询只用 SELECT 取数 + FETCH 取信，
#    每 60 秒查一次，连接断了就重连。
if "轮询查新邮件" not in src:
    start = src.find("def idle_mail_listener")
    end = src.find("\ndef main():", start)
    if start < 0 or end < 0:
        print("补丁停：找不到 idle_mail_listener/main 边界，一处都没改。")
        sys.exit(1)
    listener = '''def idle_mail_listener(email_config, folder):
    # 兼容版：轮询查新邮件，不用 IDLE、不用 SEARCH。
    # 2925 的 IMAP 不认 SEARCH，新浪会把 IDLE 连接断开，
    # 所以每 60 秒 SELECT 一次取邮件数，多了就 FETCH 新信；连接断了就重连。
    config = load_config()
    RETRY_LIMIT = config.RETRY_LIMIT
    RETRY_DELAY = config.RETRY_DELAY
    RETRY_PAUSE = config.RETRY_PAUSE
    POLL_INTERVAL = getattr(config, "POLL_INTERVAL", 60)
    retry_count = 0
    email_provider = 'gmail' if 'gmail.com' in email_config['EMAIL'] else 'other'

    while True:
        server = None
        try:
            server = imaplib2.IMAP4_SSL(email_config['IMAP_SERVER'], email_config['IMAP_SERVER_PORT'])
            oauth_helper.imap_login(server, email_config)
            logger.info(f"成功登录邮箱 {email_config['EMAIL']}")

            _, folders = server.list()
            actual_folder = get_folder_name(folders, folder, email_provider) or folder
            last_count = _selected_count(server, actual_folder)
            logger.info(f"成功选择文件夹: {actual_folder}，当前 {last_count} 封")

            if email_config['EMAIL'] not in LOGIN_SUCCESS:
                language = os.environ.get('LANGUAGE', 'Chinese')
                if language == 'English':
                    message = 'Successfully logged into mailbox ' + email_config['EMAIL']
                else:
                    message = '成功登录邮箱 ' + email_config['EMAIL']
                LOGIN_SUCCESS.append(email_config['EMAIL'])
                asyncio.run(send_telegram_message(message))

            while True:
                time.sleep(POLL_INTERVAL)
                count = _selected_count(server, actual_folder)
                retry_count = 0
                if count > last_count:
                    for num in range(last_count + 1, count + 1):
                        try:
                            fetch_email(server, str(num), email_config, actual_folder)
                        except Exception as e:
                            logger.error(f"取第 {num} 封信失败（跳过这封）: {e}")
                    last_count = count
                elif count < last_count:
                    last_count = count
        except Exception as e:
            logger.error(f"{email_config['EMAIL']} 的 {folder} 文件夹轮询出错: {e}")
            retry_count += 1
        finally:
            if server:
                try:
                    server.logout()
                except Exception:
                    pass

        if retry_count >= RETRY_LIMIT:
            final_message = f"{email_config['EMAIL']} 的 {folder} 文件夹重试次数达到上限。等待 {RETRY_PAUSE // 60} 分钟后重试。"
            logger.error(final_message)
            asyncio.run(send_telegram_message(final_message))
            time.sleep(RETRY_PAUSE)
            retry_count = 0
        elif retry_count:
            time.sleep(RETRY_DELAY)

'''
    src = src[:start] + listener + src[end:]

# 5) Telegram 命令：查看其它文件夹 / 删除邮件。
#    上游机器人只会推送，没有任何命令。这里加一个命令机器人，和监听线程一起跑。
#    只认 TELEGRAM_CHAT_ID 一个人；删信要先 /del 再 /delok 两步确认，5 分钟内有效。
if "CommandHandler" not in src:
    old_imp = "from telegram.ext import ApplicationBuilder"
    if old_imp not in src:
        print("补丁停：找不到 telegram 导入行，一处都没改。")
        sys.exit(1)
    src = src.replace(old_imp, "from telegram.ext import ApplicationBuilder, CommandHandler", 1)

if "def run_command_bot" not in src:
    commands = r'''# ---- Telegram 命令：查看其它文件夹 / 删除邮件，只认主人 TELEGRAM_CHAT_ID ----
_PENDING_DELS = {}


def _cmd_mailbox(arg):
    config = load_config()
    try:
        idx = int(arg) - 1
    except Exception:
        return None, "邮箱号要是数字，用 /ls 看编号。"
    if idx < 0 or idx >= len(config.EMAILS):
        return None, "没有这个编号的邮箱，用 /ls 看编号。"
    return config.EMAILS[idx], None


def _cmd_open(email_config):
    # 每次命令新开一个 IMAP 连接，用完就关，不动监听线程的连接
    server = imaplib2.IMAP4_SSL(email_config['IMAP_SERVER'], email_config['IMAP_SERVER_PORT'])
    oauth_helper.imap_login(server, email_config)
    return server


def _cmd_folders(server):
    status, folders = server.list()
    if status != "OK":
        raise Exception("取文件夹列表失败")
    names = []
    for f in folders or []:
        name = _parse_list_folder_name(f)
        if name and name not in names:
            names.append(name)
    return names


def _cmd_resolve_folder(server, arg):
    # 文件夹可以传编号（/ls 里看到的序号）或名字
    names = _cmd_folders(server)
    try:
        idx = int(arg) - 1
        if 0 <= idx < len(names):
            return names[idx], None
    except Exception:
        pass
    if arg in names:
        return arg, None
    return None, "没有这个文件夹，用 /ls 邮箱号 看编号。"


async def _cmd_check_owner(update):
    if not update.message:
        return False
    config = load_config()
    try:
        if str(update.effective_chat.id) == str(config.TELEGRAM_CHAT_ID):
            return True
    except Exception:
        pass
    try:
        await update.message.reply_text("不是主人，不理你。")
    except Exception:
        pass
    return False


def _cmd_fetch_header(server, seq):
    # 只取信头，不取正文
    typ, data = server.fetch(str(seq), "(BODY[HEADER.FIELDS (SUBJECT DATE FROM)])")
    if typ != "OK" or not data or not isinstance(data[0], tuple):
        return None, None, None
    msg = email.message_from_bytes(data[0][1])
    subject = decode_header_string(msg.get("Subject") or "(无主题)")
    sender = decode_header_string(msg.get("From") or "")
    date = msg.get("Date") or ""
    return subject, sender, date


def _cmd_close(server):
    if server:
        try:
            server.logout()
        except Exception:
            pass


async def cmd_start(update, context):
    if not await _cmd_check_owner(update):
        return
    await update.message.reply_text(
        "能用的命令：\n"
        "/ls 看邮箱列表；/ls 1 看 1 号邮箱的文件夹\n"
        "/show 1 1 5 看 1 号邮箱 1 号文件夹最新 5 封\n"
        "/del 1 1 7 删 1 号邮箱 1 号文件夹第 7 封（要再发 /delok 确认）\n"
        "/delok 1 1 7 确认删除")


async def cmd_ls(update, context):
    if not await _cmd_check_owner(update):
        return
    config = load_config()
    args = context.args
    if not args:
        lines = ["邮箱列表（/ls 1 看文件夹）："]
        for i, e in enumerate(config.EMAILS, 1):
            lines.append(f"{i}. {e['EMAIL']}")
        await update.message.reply_text("\n".join(lines))
        return
    email_config, err = _cmd_mailbox(args[0])
    if err:
        await update.message.reply_text(err)
        return
    server = None
    try:
        server = _cmd_open(email_config)
        names = _cmd_folders(server)
        lines = [f"{email_config['EMAIL']} 的文件夹："]
        for i, name in enumerate(names, 1):
            lines.append(f"{i}. {name}")
        lines.append("看信：/show 邮箱号 文件夹号 条数，例如 /show 1 1 5")
        await update.message.reply_text("\n".join(lines))
    except Exception as e:
        await update.message.reply_text(f"列文件夹失败：{e}")
    finally:
        _cmd_close(server)


async def cmd_show(update, context):
    if not await _cmd_check_owner(update):
        return
    args = context.args
    if len(args) < 2:
        await update.message.reply_text("用法：/show 邮箱号 文件夹号 [条数]，例如 /show 1 1 5")
        return
    email_config, err = _cmd_mailbox(args[0])
    if err:
        await update.message.reply_text(err)
        return
    try:
        count_n = int(args[2]) if len(args) > 2 else 5
    except Exception:
        count_n = 5
    count_n = max(1, min(count_n, 10))
    server = None
    try:
        server = _cmd_open(email_config)
        folder, err = _cmd_resolve_folder(server, args[1])
        if err:
            await update.message.reply_text(err)
            return
        total = _selected_count(server, folder)
        if total == 0:
            await update.message.reply_text(f"{folder} 里没有信。")
            return
        start = max(1, total - count_n + 1)
        lines = [f"{email_config['EMAIL']} / {folder}（共 {total} 封，最新 {total - start + 1} 封）："]
        for num in range(total, start - 1, -1):
            subject, sender, date = _cmd_fetch_header(server, num)
            if subject is None:
                lines.append(f"{num}. 取不出来")
            else:
                lines.append(f"{num}. {subject}\n   {sender} | {date}")
        lines.append("删信：/del 邮箱号 文件夹号 序号，例如 /del 1 1 7")
        await update.message.reply_text("\n".join(lines))
    except Exception as e:
        await update.message.reply_text(f"看信失败：{e}")
    finally:
        _cmd_close(server)


async def cmd_del(update, context):
    if not await _cmd_check_owner(update):
        return
    args = context.args
    if len(args) < 3:
        await update.message.reply_text("用法：/del 邮箱号 文件夹号 序号，例如 /del 1 1 7")
        return
    email_config, err = _cmd_mailbox(args[0])
    if err:
        await update.message.reply_text(err)
        return
    try:
        seq = int(args[2])
    except Exception:
        await update.message.reply_text("序号要是数字。")
        return
    server = None
    try:
        server = _cmd_open(email_config)
        folder, err = _cmd_resolve_folder(server, args[1])
        if err:
            await update.message.reply_text(err)
            return
        total = _selected_count(server, folder)
        if seq < 1 or seq > total:
            await update.message.reply_text(f"序号不对，这个文件夹现在共 {total} 封。")
            return
        subject, sender, date = _cmd_fetch_header(server, seq)
        if subject is None:
            subject, sender = "(取不到标题)", ""
        key = (str(update.effective_chat.id), args[0], args[1], str(seq))
        _PENDING_DELS[key] = (time.time(), folder, subject)
        await update.message.reply_text(
            f"要删这封吗？\n{email_config['EMAIL']} / {folder} 第 {seq} 封\n标题：{subject}\n发件人：{sender}\n"
            f"确认请在 5 分钟内发：/delok {args[0]} {args[1]} {seq}\n不删就不用管，5 分钟后作废。")
    except Exception as e:
        await update.message.reply_text(f"删信失败：{e}")
    finally:
        _cmd_close(server)


async def cmd_delok(update, context):
    if not await _cmd_check_owner(update):
        return
    args = context.args
    if len(args) < 3:
        await update.message.reply_text("用法：/delok 邮箱号 文件夹号 序号，例如 /delok 1 1 7")
        return
    key = (str(update.effective_chat.id), args[0], args[1], args[2])
    pending = _PENDING_DELS.pop(key, None)
    if not pending:
        await update.message.reply_text("没有等确认的删除，先发 /del 选一封。")
        return
    created, folder_saved, subject = pending
    if time.time() - created > 300:
        await update.message.reply_text("确认超时了（超过 5 分钟），没删，重新发 /del。")
        return
    email_config, err = _cmd_mailbox(args[0])
    if err:
        await update.message.reply_text(err)
        return
    try:
        seq = int(args[2])
    except Exception:
        await update.message.reply_text("序号要是数字。")
        return
    server = None
    try:
        server = _cmd_open(email_config)
        folder, err = _cmd_resolve_folder(server, args[1])
        if err:
            await update.message.reply_text(err)
            return
        total = _selected_count(server, folder)
        if seq < 1 or seq > total:
            await update.message.reply_text(f"序号变了，现在共 {total} 封，没删。重新发 /del。")
            return
        server.store(str(seq), "+FLAGS", r"(\Deleted)")
        server.expunge()
        logger.info(f"主人删信：{email_config['EMAIL']} / {folder} 第 {seq} 封：{subject}")
        await update.message.reply_text(f"删了：{email_config['EMAIL']} / {folder} 第 {seq} 封\n标题：{subject}")
    except Exception as e:
        await update.message.reply_text(f"删信失败：{e}")
    finally:
        _cmd_close(server)


def run_command_bot():
    # Telegram 命令机器人，和 IMAP 监听线程一起跑；断了 30 秒后自己重连。
    while True:
        try:
            config = load_config()
            app = ApplicationBuilder().token(config.TELEGRAM_BOT_TOKEN).build()
            app.add_handler(CommandHandler("start", cmd_start))
            app.add_handler(CommandHandler("help", cmd_start))
            app.add_handler(CommandHandler("ls", cmd_ls))
            app.add_handler(CommandHandler("show", cmd_show))
            app.add_handler(CommandHandler("del", cmd_del))
            app.add_handler(CommandHandler("delok", cmd_delok))
            logger.info("Telegram 命令机器人启动了（/help 看命令）。")
            app.run_polling()
        except Exception as e:
            logger.error(f"命令机器人出错，30 秒后重试：{e}")
            time.sleep(30)


'''
    if "def main():" not in src:
        print("补丁停：找不到 def main()，一处都没改。")
        sys.exit(1)
    src = src.replace("def main():", commands + "\ndef main():", 1)
    anchor = "    while any(thread.is_alive() for thread in email_threads):"
    if "bot_thread = threading.Thread(target=run_command_bot" not in src:
        if anchor not in src:
            print("补丁停：找不到 main() 里等监听线程的那行，一处都没改。")
            sys.exit(1)
        src = src.replace(anchor, "    bot_thread = threading.Thread(target=run_command_bot, daemon=True)\n    bot_thread.start()\n" + anchor, 1)
open(path, "w", encoding="utf-8").write(src)
print("补丁已打：OAuth 登录 + 兼容轮询（SELECT 数信 + FETCH 取信，不用 SEARCH/IDLE）+ Telegram 命令（/ls /show /del）")
PYEOF
then
echo "补丁失败，已恢复备份 $bak，main.py 没动。"
cp "$bak" "$DIR/main.py" 2>/dev/null || true
return 1
fi
if ! "$VENV/bin/python" -m py_compile "$DIR/main.py" 2>/dev/null && ! python3 -m py_compile "$DIR/main.py"; then
echo "补丁后 main.py 语法检查没过，已恢复备份，补丁没打。"
cp "$bak" "$DIR/main.py" 2>/dev/null || true
return 1
fi
if [ "$(grep -c "oauth_helper.imap_login" "$DIR/main.py")" -ne 3 ] || grep -q "server.login(email_config\['EMAIL'\], email_config\['PASSWORD'\])" "$DIR/main.py"; then
echo "补丁后核对没过（应有 3 处新登录：监听、轮询、命令各 1 处，0 处旧登录），已恢复备份。"
cp "$bak" "$DIR/main.py" 2>/dev/null || true
return 1
fi
if ! grep -q "_selected_count" "$DIR/main.py" || ! grep -q "run_command_bot" "$DIR/main.py" || grep -q "server\.idle(" "$DIR/main.py" || grep -q "server\.search(" "$DIR/main.py"; then
echo "补丁后核对没过（轮询函数缺失，或还剩 IDLE/SEARCH），已恢复备份。"
cp "$bak" "$DIR/main.py" 2>/dev/null || true
return 1
fi
echo "补丁打好了，备份在 $bak。"
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

# 给一个 Outlook/Hotmail 邮箱做设备码 OAuth 授权。
# $1=邮箱地址；成功后设置全局 O_CLIENT_ID / O_TENANT，失败返回 1。
# 授权前必须先在 Entra 注册好自己的应用，client ID 在主机终端里填，不要发到聊天里。
setup_outlook_oauth() {
local email="$1" client_id="" tenant=""
if [ ! -f "$DIR/oauth_outlook.py" ] || [ ! -f "$DIR/oauth_helper.py" ]; then
write_oauth_files || return 1
fi
patch_main_py || return 1
echo "先在 Microsoft Entra 注册应用（只做一次）："
echo " entra.microsoft.com > App registrations > New registration，个人账号，"
echo " Redirect URI 选 Public client/native (mobile & desktop) > http://localhost，"
echo " Authentication 里 Allow public client flows 选 Yes，"
echo " API permissions > Office 365 Exchange Online > Delegated > IMAP.AccessAsUser.All，"
echo " 再复制 Application (client) ID。"
read -r -p "Application (client) ID（输入时会显示）: " client_id || true
if [ -z "$client_id" ]; then echo "client ID 没填，授权没做。"; return 1; fi
read -r -p "账号类型：个人 Outlook/Hotmail 直接回车（consumers），公司/学校填 common： " tenant || true
[ -z "$tenant" ] && tenant="consumers"
O_CLIENT_ID="$client_id"; O_TENANT="$tenant"
local py="python3"
[ -x "$VENV/bin/python" ] && py="$VENV/bin/python"
(cd "$DIR" && "$py" oauth_outlook.py "$email" "$client_id" "$tenant")
}

reauthorize_outlook() {
if [ ! -d "$DIR" ]; then echo "还没有 $DIR，先选 1 一键部署。"; return 1; fi
write_oauth_files || return 1
patch_main_py || return 1
local email=""
read -r -p "要重新授权的 Outlook/Hotmail 完整地址: " email || true
case "$email" in
*@*.*);;
*) echo "邮箱格式不对。"; return 1;;
esac
setup_outlook_oauth "$email"
}

# 选邮箱服务商，输出 host、port、密码提示到全局变量 P_HOST P_PORT P_HINT P_USE_OAUTH，失败返回 1
pick_provider() {
P_USE_OAUTH=0; O_CLIENT_ID=""; O_TENANT="consumers"
echo "选邮箱服务商："
echo " 1) Gmail"
echo " 2) QQ 邮箱"
echo " 3) 163 邮箱"
echo " 4) 新浪 sina"
echo " 5) cock.li"
echo " 6) 2925.com"
echo " 7) Outlook / Hotmail（OAuth，不走密码 IMAP）"
echo " 8) 自建 / 自定义 IMAP（按标准示例填）"
echo " 0) 不加了，结束添加"
local choice=""
read -r -p "输入序号: " choice || true
case "$choice" in
0) return 2;;
1) P_HOST="imap.gmail.com"; P_PORT="993"; P_HINT="Gmail 16 位应用专用密码（不是登录密码；先开两步验证再生成，填时去掉空格。个人账号 IMAP 默认已开）";;
2) P_HOST="imap.qq.com"; P_PORT="993"; P_HINT="QQ 16 位授权码（网页设置里开 IMAP/SMTP 后生成，不是 QQ 密码）";;
3) P_HOST="imap.163.com"; P_PORT="993"; P_HINT="163 16 位客户端授权密码（网页设置里开 IMAP/SMTP 后生成，不是登录密码）";;
4)
echo " 新浪后缀选一个：1) sina.com 2) sina.cn 3) vip.sina.com 4) vip.sina.cn"
local s=""
read -r -p "输入序号: " s || true
case "$s" in
1) P_HOST="imap.sina.com";;
2) P_HOST="imap.sina.cn";;
3) P_HOST="imap.vip.sina.com";;
4) P_HOST="imap.vip.sina.cn";;
*) echo "没选对，跳过这一个。"; return 1;;
esac
P_PORT="993"; P_HINT="新浪 16 位授权码（网页设置里开客户端 POP/IMAP/SMTP 后生成，不是登录密码）"
;;
5) P_HOST="mail.cock.li"; P_PORT="993"; P_HINT="cock.li 账号密码。官网写的服务器就是 mail.cock.li（IMAP/POP），不是 imap.cock.li；993 SSL";;
6) P_HOST="imap.2925.com"; P_PORT="993"; P_HINT="2925 主邮箱密码（登录名填主邮箱完整地址，子邮箱不能直接登录客户端）。如果这台连不上，再试 imap.2925mail.com:993";;
7)
echo "Outlook / Hotmail 走 OAuth，不走密码 IMAP："
echo " 官网设置：outlook.office365.com:993，SSL/TLS，个人账号（@outlook.com / @hotmail.com / @live.com）"
echo " 自 2024-09-16 起只认 OAuth2，密码 IMAP 已停用，填密码必定登录失败。"
echo " 本脚本已带 OAuth 桥接：设备码授权拿令牌，令牌存 oauth_tokens.json（600），"
echo " 过期自动用 refresh_token 刷新，IMAP 用 XOAUTH2 登录。"
echo " 不想现在授权就选 0 跳过，或先用 Outlook 网页版转发到 Gmail/QQ/163。"
if ! ask_yes_no "现在就给一个 Outlook/Hotmail 邮箱做 OAuth 授权吗？"; then
echo "跳过 Outlook，回到选服务商。"
return 1
fi
P_HOST="outlook.office365.com"; P_PORT="993"; P_USE_OAUTH=1
P_HINT="OAuth 令牌（不填密码，填完邮箱地址后走设备码授权，令牌自动存 oauth_tokens.json）"
;;
8)
echo "自建 / 小众邮箱标准示例：IMAP 服务器 imap.example.com，端口 993，加密 SSL/TLS，用户名填完整邮箱地址。"
echo "按你服务商官网给的客户端设置填，别按猜的填。"
read -r -p "IMAP 服务器（例如 imap.example.com 或 mail.example.com）: " P_HOST || true
read -r -p "IMAP 端口（回车默认 993）: " P_PORT || true
[ -z "$P_PORT" ] && P_PORT="993"
P_HINT="这个服务商官网给的密码或授权码（按它官网的客户端设置填）"
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
echo "一步一步填，Token 和密码输入时会显示在屏幕上，填完后汇总里不会打印出来"
echo "第 1 步：Telegram 机器人"
echo " 先去 @BotFather 建机器人，拿到 Token；再去机器人私聊里发 /start，不然它给你发不了消息。"
local token="" chat_id="" junk_id=""
read -r -p "Bot Token（输入时会显示，输完按回车）: " token || true
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
if [ "${P_USE_OAUTH:-0}" -eq 1 ]; then
echo "OAuth 提示：$P_HINT"
if ! setup_outlook_oauth "$email"; then echo "OAuth 授权没做成，这个邮箱没加。"; continue; fi
entries="$entries
{
'EMAIL': '$(py_escape "$email")',
'PASSWORD': '',
'IMAP_SERVER': '$(py_escape "$P_HOST")',
'IMAP_SERVER_PORT': $P_PORT,
'USE_OAUTH': True,
'OAUTH_TENANT': '$(py_escape "${O_TENANT:-consumers}")',
'OAUTH_CLIENT_ID': '$(py_escape "$O_CLIENT_ID")',
},"
summary="$summary
- $email ($P_HOST:$P_PORT, OAuth)"
count=$((count + 1))
echo "已加入第 $count 个：$email（OAuth）"
if ! ask_yes_no "还要再加一个邮箱吗？"; then
break
fi
continue
fi
echo "密码提示：$P_HINT"
read -r -p "密码 / 授权码（输入时会显示，输完按回车）: " pw || true
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
write_oauth_files || return 1
patch_main_py || return 1
echo "正在启动后台服务..."
(cd "$DIR" && ./start.sh)
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
if is_running; then
echo "已经有一个 mail2tg 在跑了（后台或另一个前台），再开一个会让同一封信推两次。"
if ! ask_yes_no "确定还要再开一个前台测试吗？"; then echo "先停掉在跑的那个（菜单 5，或 Ctrl+C 停掉另一个前台）再测。"; return 1; fi
fi
if [ ! -f "$CONFIG" ]; then
echo "还没有 $CONFIG，先选 2 走配置向导。"
return 1
fi
write_oauth_files || return 1
patch_main_py || return 1
local py="python3"
[ -x "$VENV/bin/python" ] && py="$VENV/bin/python"
echo "前台测试开始：TG 收到“登录成功”就说明通了，再给邮箱发封测试信看推不推。"
echo "想停就按 Ctrl+C，停了不会进后台。"
(cd "$DIR" && LANGUAGE=Chinese TIMEZONE=Asia/Shanghai ENABLE_LOGGING=true ENABLE_EVC=false "$py" main.py)
echo "前台测试已退出。"
return 0
}

setup_shortcut() {
local quiet=0
[ "$1" = "quiet" ] && quiet=1
local src=""
if [ -f "$HOME/mail2tg.sh" ]; then src="$HOME/mail2tg.sh";
elif [ -f "$0" ]; then src="$0"; fi
if [ -z "$src" ]; then [ "$quiet" -eq 0 ] && echo "找不到 mail2tg.sh 文件，快捷键 tge 没装上。"; return 1; fi
mkdir -p "$HOME/bin" 2>/dev/null || return 1
ln -sf "$src" "$HOME/bin/tge" 2>/dev/null || return 1
chmod +x "$src" 2>/dev/null || true
local rc=""
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
touch "$rc" 2>/dev/null || continue
if ! grep -Fq 'export PATH="$HOME/bin:$PATH"' "$rc" 2>/dev/null; then
echo 'export PATH="$HOME/bin:$PATH"' >> "$rc" || true
fi
done
if [ -f "$HOME/.zshrc" ] && ! grep -Fq 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null; then
echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc" || true
fi
if [ "$quiet" -eq 0 ]; then
echo -e "快捷键已装好：退出后输入 \033[1;32mtge\033[0m 就能再进菜单。"
echo -e "注意：当前这个终端要重登一次 SSH，或先跑 export PATH=\"\$HOME/bin:\$PATH\"，\033[1;32mtge\033[0m 才直接生效；也可以直接跑 ~/bin/tge。"
fi
return 0
}

one_click_deploy() {
echo "================ 一键部署 ================"
echo "按顺序走：权限 → Python → 拉代码装依赖 → 写后台脚本 → 填配置 → 启动"
step_binexec || { echo "一键部署停在第 1 步了。"; return 1;}
step_python || { echo "一键部署停在第 2 步了。"; return 1;}
step_install || { echo "一键部署停在第 3 步了。"; return 1;}
write_helpers || { echo "一键部署停在写后台脚本了。"; return 1;}
write_oauth_files || { echo "一键部署停在写 OAuth 桥接文件了。"; return 1;}
patch_main_py || { echo "一键部署停在打 main.py 补丁了。"; return 1;}
setup_shortcut || echo "快捷键 tge 没装上，不影响部署，退出后用 ./mail2tg.sh 也能进菜单。"
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
echo "一键卸载会：停服务、去掉看门狗 crontab、删掉 ~/mail2tg、~/mail2tg-venv、~/check_mail2tg.sh、~/bin/tge，以及本脚本 ~/mail2tg.sh 本身。"
echo "注意：删完要重装，得重新下载 GitHub 那条。backups、s5.sh、muse2api 这些不相关的文件和目录不会动。"
read -r -p "确认卸载请输入 yes： " ans || true
if [ "$ans" != "yes" ]; then
echo "没输入 yes，取消卸载。"
return 0
fi
pkill -f "mail2tg/main.py" 2>/dev/null || true
remove_crontab
rm -rf "$DIR" "$VENV" "$WATCHDOG"
rm -f "$HOME/bin/tge"
rm -f "$HOME/mail2tg.sh"
UNINSTALLED=1
echo "卸载完了，连本脚本 ~/mail2tg.sh 和快捷键 tge 也已删掉。Outlook 的 OAuth 令牌在 ~/mail2tg/oauth_tokens.json 里，也一起删了，重装后要重新授权。如果以后不用这些邮箱授权码了，记得去各邮箱后台吊销授权码 / 应用专用密码，删本地文件不等于吊销。"
return 0
}

setup_shortcut quiet || true
UNINSTALLED=0
while true; do
echo ""
echo "================ Mail2Telegram Serv00 一键部署 ================"
if [ "$UNINSTALLED" -eq 1 ]; then
echo "提示：已删除清理，欢迎再次使用拉取命令重装"
else
echo -e "提示：退出后输入 \033[1;32mtge\033[0m 可再次呼出菜单"
fi
echo " 1) 一键部署（一步一步提示：权限 → 依赖 → 机器人 → 邮箱 → 启动）"
echo " 2) 只填 / 改配置（重新走机器人 + 邮箱向导，旧配置会自动备份）"
echo " 3) 前台测试运行（Ctrl+C 停止，不进后台）"
echo " 4) 启动后台服务"
echo " 5) 停止服务"
echo " 6) 重启服务"
echo " 7) 查看状态和日志"
echo " 8) 设置 / 检查看门狗 crontab"
echo " 9) 一键卸载"
echo " 10) Outlook OAuth 重新授权（令牌过期/被吊销时用）"
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
10) reauthorize_outlook; pause;;
0)
if [ "$UNINSTALLED" -eq 1 ]; then
echo "退出。已经删除清理了，欢迎再次使用："
echo "curl -Ls https://raw.githubusercontent.com/djkyc/serv00-ct8/refs/heads/main/tgeamil/mail2tg.sh -o ~/mail2tg.sh && chmod +x ~/mail2tg.sh && ./mail2tg.sh"
else
echo -e "退出。以后输入 \033[1;32mtge\033[0m 可再次呼出菜单。"
fi
break;;
*) echo "没这个序号，重新选。";;
esac
done
