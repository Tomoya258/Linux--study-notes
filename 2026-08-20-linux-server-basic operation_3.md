
```markdown
# Linux 运维学习笔记 - 2026年8月20日

> 学习主题：网络端口、Nginx 部署与排错、中间件概念

---

## 一、端口（Port）核心概念

### 1. 端口是什么？
端口是应用程序与外界通信的接口，通过 **IP地址 + 端口号** 确定唯一的通信端点。

**一句话理解：**
```
IP 地址 = 找到哪台机器（一栋楼的地址）
端口 = 找到这台机器上的哪个程序（房间号）
程序 = 房间里的服务
```

**组合示例：**
```
192.168.136.133:80
```
含义：找到 IP 为 `192.168.136.133` 的机器，再找到它的 80 端口，由 Nginx 处理。

### 2. 端口三大分类

| 范围 | 类型 | 说明 | 常见例子 |
|---|---|---|---|
| 0-1023 | 公认端口 | 系统服务专用 | 22(SSH), 80(HTTP), 443(HTTPS), 25(SMTP) |
| 1024-49151 | 注册端口 | 用户应用程序常用 | 3306(MySQL), 8080(Tomcat), 6379(Redis) |
| 49152-65535 | 动态端口 | 客户端临时使用 | 每次连接时系统自动分配 |

**记忆口诀：**
- 0-1023 = "政府大楼"，系统专用
- 1024-49151 = "商业写字楼"，应用程序入驻
- 49152-65535 = "临时停车位"，用完回收

### 3. 服务端端口 vs 客户端端口

| | 服务端 | 客户端 |
|---|---|---|
| 端口 | 固定（如 22, 80） | 临时（如 3411） |
| 谁决定 | 服务配置决定 | 操作系统自动分配 |
| 范围 | 公认/注册端口 | 动态端口 |
| 类比 | 餐厅固定门牌号 | 客人临时座位号 |

**实际例子（SSH 连接）：**
```
服务器：192.168.13.2:22        ← 服务端固定端口
客户端：192.168.136.1:3411     ← 客户端临时端口
```

---

## 二、查看端口占用的命令

### 1. netstat

**安装：**
```bash
yum install -y net-tools
```

**常用组合：**
```bash
netstat -anp
```

**参数详解：**

| 参数 | 全称 | 含义 |
|---|---|---|
| `-a` | all | 显示所有连接和监听端口 |
| `-n` | numeric | 不解析服务名，直接显示数字端口 |
| `-p` | program | 显示占用端口的进程 ID 和名称 |

**实际使用：**
```bash
# 查看所有网络连接
netstat -anp

# 过滤查看指定端口（如 80）
netstat -anp | grep :80

# 过滤查看指定程序（如 nginx）
netstat -anp | grep nginx
```

### 2. ss（更现代的工具）

```bash
ss -tlnp

# -t: TCP
# -l: 只显示 LISTEN 状态
# -n: 显示数字端口
# -p: 显示进程
```

### 3. 其他相关命令

```bash
# 查看服务器 IP
ip a
# 或
hostname -I

# 查看某个端口被哪个进程占用
lsof -i :80
```

---

## 三、LISTEN 和 ESTABLISHED 的区别

### LISTEN（监听）
某个程序打开了一个端口，正在等待别人连接。

**类比：** 门开着，等客人。

```
0.0.0.0:22  LISTEN  1058/sshd
```
含义：sshd 在 22 端口等待 SSH 客户端连接。

### ESTABLISHED（已建立连接）
已经有一个客户端成功连接，目前正在通信。

**类比：** 客人已经进来了，正在聊天。

```
192.168.13.2:22  192.168.136.1:3411  ESTABLISHED  1505/sshd
```
含义：客户端 `192.168.136.1` 通过临时端口 `3411` 连接到了服务器的 SSH 服务。

---

## 四、0.0.0.0 和 127.0.0.1 的区别

| 地址 | 含义 | 谁能访问 |
|---|---|---|
| `0.0.0.0:80` | 监听本机所有 IPv4 接口的 80 端口 | 所有能访问到该机器 IP 的客户端 |
| `127.0.0.1:80` | 只监听本机回环地址的 80 端口 | 只有本机自己（localhost） |

**示例：**
```bash
# Nginx 配置为监听所有接口（正确）
0.0.0.0:80  LISTEN  2127/nginx

# Nginx 只监听本机（外部无法访问）
127.0.0.1:80  LISTEN  2127/nginx
```

---

## 五、防火墙管理（firewalld）

### 1. 查看防火墙状态
```bash
systemctl status firewalld
firewall-cmd --state
```

### 2. 查看已开放的端口
```bash
firewall-cmd --list-ports
```

### 3. 开放端口
```bash
firewall-cmd --add-port=80/tcp --permanent
firewall-cmd --reload
```

**参数说明：**
- `--add-port=80/tcp`：添加 80 端口的 TCP 规则
- `--permanent`：永久生效（重启后保留）
- `--reload`：重新加载配置（立即生效）

---

## 六、Nginx 学习记录

### 1. Nginx 是什么？
Nginx 是一个 **Web 服务器/中间件**，处于用户和后端服务之间，负责接收请求、处理请求、返回响应。

**类比：** 餐厅门口的服务员，站在门口接待客人。

### 2. 中间件是什么？
中间件 = 位于"客户端"和"后端服务"之间的软件层。

**类比：** 餐厅的传菜窗口，连接客人和后厨。

```
浏览器（客户端）
    ↓
【 Nginx 】  ← 中间件层
    ↓
后端服务器（应用/数据库）
```

### 3. 常见 Nginx 用途
- 提供静态网页（HTML/CSS/JS/图片）
- 反向代理（转发请求给后端应用）
- 负载均衡（分发请求到多台服务器）

### 4. Nginx 关键文件位置（CentOS）

| 文件/目录 | 用途 |
|---|---|
| `/etc/nginx/nginx.conf` | 主配置文件 |
| `/etc/nginx/conf.d/` | 额外配置目录 |
| `/var/log/nginx/access.log` | 访问日志 |
| `/var/log/nginx/error.log` | 错误日志 |
| `/usr/share/nginx/html/` | 默认网页目录 |

---

## 七、今天遇到的问题与解决过程

### 问题：启动 Nginx 后，浏览器无法访问

**现象：**
- `systemctl start nginx` 成功
- `netstat -anp | grep :80` 显示 Nginx 在 `0.0.0.0:80` 监听
- 浏览器访问 `http://192.168.136.133` 无法打开

**排查过程：**

```text
1. 检查 Nginx 状态 → systemctl status nginx        ✅ 正常运行
2. 检查监听端口   → netstat -anp | grep :80        ✅ 0.0.0.0:80
3. 本机测试      → curl http://localhost           ✅ 正常返回
4. 检查防火墙    → firewall-cmd --list-ports       ❌ 80 端口未开放
```

**解决方案：**
```bash
firewall-cmd --add-port=80/tcp --permanent
firewall-cmd --reload
```

**验证：**
```bash
firewall-cmd --list-ports
# 输出：80/tcp
```

### 问题总结

```
服务运行了但访问不了 → 首先检查防火墙是否放行了端口
```

### 排查顺序（值得记住）

```text
1. 服务是否运行？        → systemctl status 服务名
2. 端口是否在监听？      → netstat -anp | grep 端口号
3. 本机能否访问？        → curl http://localhost
4. 防火墙是否放行？      → firewall-cmd --list-ports
5. SELinux 是否阻止？    → getenforce
```

---

## 八、今日命令汇总

| 用途 | 命令 |
|---|---|
| 启动 Nginx | `systemctl start nginx` |
| 查看 Nginx 状态 | `systemctl status nginx` |
| 查看网络连接 | `netstat -anp` |
| 查看 TCP 监听端口 | `ss -tlnp` |
| 查看服务器 IP | `ip a` |
| 查看防火墙状态 | `systemctl status firewalld` |
| 查看已开放端口 | `firewall-cmd --list-ports` |
| 开放端口 | `firewall-cmd --add-port=80/tcp --permanent` |
| 重载防火墙 | `firewall-cmd --reload` |
| 查看 SELinux 状态 | `getenforce` |
| 临时关闭 SELinux | `setenforce 0` |
| 查看 Nginx 访问日志 | `tail -f /var/log/nginx/access.log` |
| 查看 Nginx 错误日志 | `tail -f /var/log/nginx/error.log` |

---

## 九、今日学习心得

### 核心理解
1. **IP 找机器，端口找程序。**
2. **LISTEN = 门开着等人，ESTABLISHED = 人进来了在聊天。**
3. **服务端固定端口，客户端临时端口。**
4. **Nginx 是一种中间件，处于用户和后端服务之间。**

### 今日收获
- 理解了端口的概念和分类
- 掌握了 `netstat -anp` 查看端口占用
- 理解了 LISTEN 和 ESTABLISHED 的区别
- 完成了 Nginx 的部署和排错（防火墙问题）
- 理解了 Nginx 作为 Web 服务器/中间件的角色



*笔记整理日期：2026-08-20*
```

---

今天的东西有点复杂 不是很好理解