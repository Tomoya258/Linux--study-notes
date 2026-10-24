# Ubuntu Server 部署 RuoYi-Vue（4）：systemd 接管 Java 后端

- 日期：2026-10-25
- 环境：Windows、VMware Workstation、Ubuntu Server 26.04.1 LTS、SSH
- 服务器主机名：ubuntu-server-01
- 普通用户：admin01
- 服务器固定 IP：192.168.136.10/24
- 项目：RuoYi-Vue 3.9.2
- 后端路径：/home/admin01/projects/RuoYi-Vue
- 前端路径：/home/admin01/projects/ruoyi-ui/RuoYi-Vue3-master

---

## 一、本阶段目标

前面已经完成 Java 后端、MySQL、Redis、Vue 前端和 Nginx 的部署。此前后端是通过 SSH 窗口手工执行 `java -jar` 启动的，这种方式存在明显问题：

- 关闭 SSH 窗口后，后端进程可能结束。
- 服务器重启后，后端不会自动恢复。
- 应用没有统一纳入 Linux 服务管理。
- 日志只能依赖启动 Java 的那个终端查看。

本阶段的目标是使用 systemd 接管 Java 后端，实现：

1. 后端由系统服务启动。
2. 使用 `systemctl` 管理启动、停止和重启。
3. 使用 `journalctl` 查看应用日志。
4. 应用异常退出后自动重启。
5. 设置开机自动启动。
6. 接管后 Nginx 和浏览器访问仍然正常。

---

## 二、systemd 是什么

systemd 是 Ubuntu 中负责启动和管理系统服务的组件。很多常见服务，例如 Nginx、MySQL 和 Redis，都由 systemd 管理。

一个 service 文件描述了一个服务应该如何运行，主要包括三部分：

~~~
[Unit]
服务说明和启动顺序

[Service]
运行用户、工作目录、启动命令和重启策略

[Install]
开机启动时挂载到哪个目标
~~~

本次创建的服务文件为：

~~~
/etc/systemd/system/ruoyi.service
~~~

把自定义服务文件放到 `/etc/systemd/system/`，可以让本机自行维护的服务与系统软件包提供的服务区分开。

---

## 三、启动前确认 Java 和 JAR

进入后端项目目录：

~~~bash
cd /home/admin01/projects/RuoYi-Vue
~~~

查询 Java 实际路径并检查构建产物：

~~~bash
JAVA_BIN="$(readlink -f "$(command -v java)")"

echo "Java 路径：$JAVA_BIN"
test -x "$JAVA_BIN" && echo "Java 可执行文件正常"
test -f ruoyi-admin/target/ruoyi-admin.jar && echo "JAR 文件存在"
~~~

实际得到的 Java 路径为：

~~~
/usr/lib/jvm/java-17-openjdk-amd64/bin/java
~~~

这里使用绝对路径有两个原因：

1. systemd 启动服务时的环境变量不一定与 SSH 登录后的 shell 完全相同。
2. `ExecStart` 使用绝对路径，能够减少因为 PATH 不同导致的启动失败。

同时需要注意，原来手工启动的 Java 进程不能和 systemd 启动的 Java 同时运行。两个进程都会尝试监听 8080，后启动的进程会因为端口已经被占用而失败。

---

## 四、创建 RuoYi systemd 服务

使用 `tee` 将服务内容写入系统服务目录：

~~~bash
sudo tee /etc/systemd/system/ruoyi.service > /dev/null <<EOF
[Unit]
Description=RuoYi Java Application
After=network-online.target mysql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=admin01
WorkingDirectory=/home/admin01/projects/RuoYi-Vue
ExecStart=$JAVA_BIN -jar /home/admin01/projects/RuoYi-Vue/ruoyi-admin/target/ruoyi-admin.jar
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF
~~~

配置项作用：

| 配置项 | 作用 |
| --- | --- |
| `After` | 在网络、MySQL 和 Redis 相关服务之后启动 |
| `User=admin01` | 使用普通用户运行 Java，不使用 root 运行应用 |
| `WorkingDirectory` | 指定应用工作目录，避免相对路径找错 |
| `ExecStart` | 指定 Java 绝对路径、JAR 绝对路径和启动方式 |
| `Restart=on-failure` | Java 异常退出时自动尝试重启 |
| `RestartSec=5` | 重启前等待 5 秒 |
| `SuccessExitStatus=143` | 将正常停止时常见的 143 退出码视为成功 |
| `WantedBy=multi-user.target` | 让服务可以挂载到系统正常启动目标 |

服务文件中没有写数据库密码、Redis 密码或其他敏感信息。应用配置仍由项目配置文件负责。

---

## 五、第一次检查发现服务没有启动

创建 service 文件后，第一次查看状态得到：

~~~
ruoyi.service - RuoYi Java Application
Loaded: loaded (/etc/systemd/system/ruoyi.service; disabled; preset: enabled)
Active: inactive (dead)
~~~

同时：

- `journalctl -u ruoyi.service` 没有日志。
- `systemctl is-enabled ruoyi.service` 返回 `disabled`。
- 8080 没有后端监听。
- Nginx 的接口请求返回 502。

原因不是 service 文件创建失败，而是只完成了“写入服务文件”，还没有完成以下三个动作：

1. 让 systemd 重新读取新文件。
2. 设置服务开机启动。
3. 立即启动服务。

这次问题说明：创建配置文件、启用服务和启动服务是三个不同动作。文件存在不代表服务已经运行。

---

## 六、重新加载、启用和启动服务

执行：

~~~bash
sudo systemctl daemon-reload
sudo systemctl enable ruoyi.service
sudo systemctl start ruoyi.service
sleep 10
~~~

三条关键命令的区别：

- `daemon-reload`：让 systemd 重新读取或刷新 service 文件。
- `enable`：建立开机启动关系，但通常不会立即启动服务。
- `start`：立即启动服务，但单独执行不等于设置开机启动。

因此，实际部署中通常需要同时执行 `enable` 和 `start`。

---

## 七、服务启动后的验证

### 7.1 服务状态

~~~bash
systemctl --no-pager --full status ruoyi.service
~~~

需要关注：

- `Active: active (running)`：服务正在运行。
- `Main PID`：主进程应为 Java。
- 是否出现 `failed`。
- 是否出现端口占用、路径不存在或权限错误。

### 7.2 开机启动状态

~~~bash
systemctl is-enabled ruoyi.service
~~~

返回：

~~~
enabled
~~~

说明服务已经设置为开机启动。

### 7.3 端口监听

~~~bash
ss -lntp | grep ':8080'
~~~

这个检查从进程和网络角度确认 Java 后端正在监听 8080。systemd 显示 active 只能说明服务进程没有被 systemd 判定为停止，还需要确认应用确实建立了监听端口。

### 7.4 查看统一日志

~~~bash
journalctl -u ruoyi.service -n 50 --no-pager
~~~

`-u ruoyi.service` 只查看若依服务，`-n 50` 查看最近 50 行，`--no-pager` 让日志直接输出，方便复制和排错。

### 7.5 验证完整访问链路

~~~bash
curl -sS -o /dev/null -w 'captchaImage: %{http_code}\n' \
http://127.0.0.1/prod-api/captchaImage
~~~

这里请求的是 Nginx 的 80 端口，不是直接访问 8080。完整链路为：

~~~
curl → Nginx → /prod-api/ 反向代理 → Java 后端 → Redis/MySQL
~~~

返回 `captchaImage: 200`，再加上 Windows 浏览器能够进入页面，说明 systemd 接管后没有破坏前后端联调。

---

## 八、本阶段排错思路

### 8.1 服务 inactive、没有日志

先区分：

- 服务文件不存在或语法错误。
- systemd 没有重新加载文件。
- 服务已经加载但没有启动。

本次状态显示 `Loaded`，说明 systemd 能找到服务文件；状态是 `disabled` 和 `inactive (dead)`，说明还没有执行启用和启动。没有日志也符合“服务从未真正启动”的情况。

### 8.2 Nginx 返回 502

502 表示 Nginx 作为代理没有从上游 Java 应用得到正常响应。排查顺序是：

~~~
Nginx 是否运行
    ↓
Java 是否监听 8080
    ↓
systemd 服务是否 active
    ↓
查看 journalctl 中的启动错误
    ↓
检查 MySQL、Redis 和应用配置
~~~

本次 502 的直接原因是 Java 后端还没有由 systemd 启动，不是 Nginx 配置突然损坏。

### 8.3 常见 systemd 启动错误

| 错误现象 | 常见原因 |
| --- | --- |
| `203/EXEC` | `ExecStart` 路径错误，或文件没有执行权限 |
| `217/USER` | `User` 指定的用户不存在 |
| `Address already in use` | 原手工 Java 进程仍占用 8080 |
| 服务启动后立即退出 | JAR、配置、数据库、Redis 或目录权限问题 |
| 状态 active 但接口失败 | 应用尚未完成启动，或 Nginx、路径、业务接口仍有问题 |

通用排查顺序仍然是“状态 → 日志 → 端口 → HTTP 接口”，而不是只看其中一项。

---

## 九、本阶段完成情况

~~~
systemd 服务文件                 已完成
Java 后端由 systemd 启动          已完成
运行用户使用 admin01              已完成
Java 和 JAR 使用绝对路径           已完成
异常退出自动重启配置              已完成
开机自动启动配置                  已完成
journalctl 日志查看                已完成
8080 端口监听                     已完成
Nginx API 代理                    已完成
Windows 浏览器访问                已完成
服务器重启后的实际验收             待后续补充
~~~

截至本阶段，RuoYi 的单机部署链路已经完成：

~~~
Windows 浏览器
    ↓
VMware NAT
    ↓
Ubuntu / UFW / Nginx 80
    ↓
systemd 管理的 Java 8080
    ↓
MySQL + Redis
~~~

这标志着项目从“能够手工启动”进入“具备基础服务管理能力”的阶段。

---

## 十、下一步：Shell 编程

systemd 阶段结束后，开始学习 Shell 编程。学习顺序结合本项目已有脚本：

1. 变量与命令替换：理解 `JAVA_BIN`、`$(...)` 和双引号。
2. 条件判断：理解 `test -x`、`test -f` 和 `if`。
3. 退出码：理解为什么命令成功或失败会影响脚本后续执行。
4. 重定向和管道：理解 `>`、`2>`、`|` 和 `/dev/null`。
5. 参数与函数：把重复的检查动作整理成函数。
6. 日志和错误处理：让脚本在失败时给出清楚原因。
7. 脚本改造：逐步完善 RuoYi 的前端部署和服务检查脚本。

Shell 的学习目标不是背命令，而是能够读懂、修改并逐步独立编写用于部署和排错的脚本。

提交 GitHub 前继续排除数据库密码、Redis 密码、SSH 私钥、Token、日志文件、target、node_modules 和上传文件。
