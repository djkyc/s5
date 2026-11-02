FROM node:20-slim

# 1. 系统依赖
RUN apt-get update && \
    apt-get install -y \
        build-essential \
        python3 \
        sqlite3 \
        git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. 工作目录
WORKDIR /app

# 3. 安装依赖
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# 4. 复制源码
COPY . .

# 5. entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ✅ 只声明“目录型”数据
VOLUME ["/app/data", "/app/my_session"]

# 6. 运行环境
ENV NODE_ENV=production

# 7. 启动入口
ENTRYPOINT ["/entrypoint.sh"]
