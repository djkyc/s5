cat << 'EOF' > install.sh
#!/bin/bash

# 获取当前用户名
USERNAME=$(whoami)
DOMAIN="muse.${USERNAME}.serv00.net"
APP_DIR="$HOME/muse2api"

echo "=== [1/5] 正在检查/创建工作目录 ==="
mkdir -p "$APP_DIR"
cd "$APP_DIR"

echo "=== [2/5] 正在寻找一个未被占用的空闲端口 ==="
# 从 18600 到 19000 随机挑选或顺序寻找一个空闲端口
PORT=18610
while netstat -an 2>/dev/null | grep -q ":$PORT "; do
    PORT=$((PORT + 1))
done
echo ">>> 已自动分配空闲端口: $PORT"

echo "=== [3/5] 正在配置 Python 虚拟环境 ==="
if [ ! -d "venv" ]; then
    python3.11 -m venv venv || python3 -m venv venv
fi
. venv/bin/activate
pip install --upgrade pip
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
else
    pip install fastapi uvicorn pydantic requests playwright
fi

echo "=== [4/5] 正在清理旧进程并后台启动服务 ==="
pkill -f "uvicorn app:app"
nohup venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port "$PORT" > muse.log 2>&1 &
echo ">>> 服务已在后台启动，PID: $!"

echo "=== [5/5] 正在通过 Serv00 API/CLI 自动绑定面板反向代理 ==="
# 调用 Serv00 面板工具 (devil www) 自动添加网站反代
# 参数格式: devil www add <domain> proxy <local_ip> <local_port>
devil www add "$DOMAIN" proxy 127.0.0.1 "$PORT" 2>/dev/null || devil www 2>/dev/null

echo ""
echo "=================================================="
echo "🎉 部署全部完成！"
echo "👉 你的专属访问域名: http://$DOMAIN"
echo "👉 后端本地监听端口: $PORT"
echo "👉 查看运行日志命令: tail -f $APP_DIR/muse.log"
echo "=================================================="
EOF

# 赋予执行权限并运行
chmod +x install.sh
./install.sh
