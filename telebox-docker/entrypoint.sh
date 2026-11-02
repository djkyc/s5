#!/bin/sh
set -e

echo "[entrypoint] TeleBox container starting..."

# 必要目录
mkdir -p /app/data /app/my_session

ENV_FILE="/app/.env"

# 🔥 防御：如果 .env 被错误创建成目录，直接修复
if [ -d "$ENV_FILE" ]; then
  echo "[entrypoint] WARN: $ENV_FILE is a directory, removing it"
  rm -rf "$ENV_FILE"
fi

# 如果 .env 不存在，则生成
if [ ! -f "$ENV_FILE" ]; then
  echo "[entrypoint] Generating $ENV_FILE from environment variables"
  {
    echo "API_ID=${API_ID}"
    echo "API_HASH=${API_HASH}"
    echo "BOT_TOKEN=${BOT_TOKEN}"
    echo "NODE_ENV=${NODE_ENV:-production}"
  } > "$ENV_FILE"
else
  echo "[entrypoint] Using existing $ENV_FILE"
fi

# 加载环境变量
echo "[entrypoint] Loading environment variables from $ENV_FILE"
set -a
. "$ENV_FILE"
set +a

echo "[entrypoint] Starting TeleBox..."
exec npm start
