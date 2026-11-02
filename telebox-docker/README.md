```shell
bash
 <(curl -Ls https://raw.githubusercontent.com/djkyc/telebox-docker/refs/heads/main/os.sh)
```

🌟 脚本特性：

1.智能交互拦截：如果检测到本地已经存在 ~/telebox 目录，会自动弹窗提示你是否覆盖重装，避免误操作覆盖旧数据。

多系统自适应：

2.Debian / Ubuntu / 其它 Linux：自动保持标准依赖，流畅安装。

3.Serv00 (FreeBSD)：自动识别系统环境，并在安装前自动剥离无法编译的 canvas 模块，彻底解决编译报错和 SSH 断开问题。

配置直达：脚本执行完毕后，会自动进入项目目录并启动 npm start，带你直达输入 api_id 和 api_hash 的 Telegram 登录

配置环节！

FreeBSD/Serv00 环境的独家适配（剥离了原版 Linux 专用的 canvas 依赖，修复了 better-sqlite3 编译）。

V8 内存防爆机制（严格限制 max-old-space-size=280，防止超出 Serv00 的 512MB 限制）。 

后台守护与一键指令映射（通过 ts、tbr、tp、td 完美掌控）。  

高可用 5 分钟看门狗自动保活（底层通过标准的 FreeBSD crontab 稳稳挂载）。 
