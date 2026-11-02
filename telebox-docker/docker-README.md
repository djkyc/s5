# 📦 TeleBox Docker 镜像（自动同步官方版本）

本镜像自动同步 **TeleBox 官方代码** 并构建多架构 Docker 镜像（amd64 / arm64）。

镜像地址：

```
ghcr.io/djkyc/telebox
```

---

# 🚀 如何获取镜像

最新版本：

```
docker pull ghcr.io/djkyc/telebox:latest
```

指定版本（例如：0.2.6）：

```
docker pull ghcr.io/djkyc/telebox:0.2.6
```

---

# 📁 持久化目录

容器必须挂载以下目录：

| 路径 | 说明 |
|------|------|
| /app/data | 数据库文件 |
| /app/my_session | Telegram Session 登录文件 |

---

# 🧪 Docker 手动部署示例

```bash
mkdir -p data my_session

docker run -d   --name telebox   -v $(pwd)/data:/app/data   -v $(pwd)/my_session:/app/my_session   -e TELEBOX_API_ID=你的API_ID   -e TELEBOX_API_HASH=你的API_HASH   -e TELEBOX_BOT_TOKEN=你的BotToken   ghcr.io/djkyc/telebox:latest
```

查看日志（首次需要输入验证码登录）：

```bash
docker logs -f telebox
```

---

# ☁️ Zeabur 容器部署教程（完整步骤）

下面是 **在 Zeabur 平台部署 TeleBox 的完整方法**，可直接照做：

---

## ✅ 1. 创建容器服务

1. 登录 Zeabur
2. 点击 **Create Service**
3. 选择 **Container**
4. 镜像填写：

```
ghcr.io/djkyc/telebox:latest
```

或指定版本：

```
ghcr.io/djkyc/telebox:0.2.6
```

---

## ✅ 2. 设置环境变量（必须）

进入：

**Service → Settings → Environment**

添加：

| Key | Value |
|-----|--------|
| TELEBOX_API_ID | 你的 Telegram API ID | https://my.telegram.org
| TELEBOX_API_HASH | Telegram API Hash |
| TELEBOX_BOT_TOKEN | 机器人 Token / 或使用用户登录 |
| NODE_ENV | production |

如要使用手机账户登录，可加：

| TELEBOX_PHONE | +86188xxxxxxx |

---

## ✅ 3. 添加持久化存储（非常重要）

进入：

**Service → Storage → Add Storage**

添加两个 Volume：

### Volume 1：会话文件

```
Mount Path: /app/my_session
Storage: Persistent
```

### Volume 2：数据存储

```
Mount Path: /app/data
Storage: Persistent
```

⚠ 必须添加，否则容器重启后需要重新登录。

---

## ✅ 4. 启动命令（Dockerfile 已内置）

无需修改 Start Command  
默认使用：

```
npm start
```

若需要手动指定：

```
npm start
```

---

## ✅ 5. 部署并完成首次登录

点击 **Deploy**

进入：

**Service → Logs**

你会看到提示：

```
Please enter your phone number:
```

依次输入：

1. 手机号（例如：+86188xxxxxxx）
2. Telegram 验证码
3. 两步验证密码（如果开启）

首次登录成功后会话将保存在 `/app/my_session`

之后无需再登录。

---

## 🎉 完成！

TeleBox 已成功运行在 Zeabur，并且登录信息、数据库文件都已持久保存。

---

# ⚙️ Docker Compose 示例

```yaml
version: "3.9"
services:
  telebox:
    image: ghcr.io/djkyc/telebox:latest
    container_name: telebox
    volumes:
      - ./data:/app/data
      - ./my_session:/app/my_session
    environment:
      TELEBOX_API_ID: "123456"
      TELEBOX_API_HASH: "abcdef123456"
      TELEBOX_BOT_TOKEN: "123:ABC"
    restart: unless-stopped
```

---

# ❤️ 反馈

如遇到构建、同步、部署相关问题，可以提交 Issue。
