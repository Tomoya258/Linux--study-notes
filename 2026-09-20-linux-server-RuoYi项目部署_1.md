# Ubuntu Server 部署 RuoYi-Vue（1）：基础检查、JDK、Maven 与 MySQL

- 日期：2026-09-20
- 环境：Windows、VMware Workstation、Ubuntu Server 26.04.1 LTS、SSH
- 服务器主机名：`ubuntu-server-01`
- 普通用户：`admin01`
- 服务器固定 IP：`192.168.136.10/24`
- 项目：RuoYi-Vue 3.9.2

---

## 一、今天完成的内容

今天正式开始把一个真实项目部署到 Ubuntu Server，而不再只是单独安装软件。

完成了以下工作：

1. 更新 Ubuntu 软件包索引。
2. 检查系统版本、主机名、IP、路由、DNS、CPU、内存、磁盘、SSH、端口、防火墙和时间同步。
3. 编写可复用的服务器基础检查脚本。
4. 理解普通进程、守护进程、Chrony 和 NTP 的作用。
5. 克隆 RuoYi-Vue 官方源码。
6. 排查 Linux 路径和 Git 仓库目录错误。
7. 根据项目的 `pom.xml` 确认需要 Java 17。
8. 安装并验证 OpenJDK 17。
9. 安装 Maven，理解 Maven、JDK、`pom.xml` 和 JAR 的关系。
10. 使用 Maven 成功编译并打包若依后端。
11. 安装 MySQL 8.4。
12. 创建 `ry-vue` 数据库和 `ruoyi_app` 应用专用账号。
13. 导入若依主 SQL 和 Quartz 定时任务 SQL。
14. 使用应用账号通过 TCP 登录 MySQL，验证数据库可用。

目前部署进度：

```text
Ubuntu 基础配置       已完成
Git 获取源码          已完成
JDK 17               已完成
Maven 构建后端        已完成
MySQL 初始化          已完成
Redis                 尚未开始
后端配置与启动        尚未开始
Node.js / 前端构建    尚未开始
Nginx                 尚未开始
systemd 管理若依      尚未开始
```

---

## 二、Ubuntu 基础检查

### 2.1 更新软件包索引

```bash
sudo apt update
```

这条命令会从软件源获取最新的软件包清单，但不会直接升级已经安装的软件。

本次使用的 Ubuntu 软件源为阿里云镜像：

```text
https://mirrors.aliyun.com/ubuntu
```

输出中出现：

```text
15 packages can be upgraded
```

表示有 15 个软件包可以升级，不代表已经执行升级。

### 2.2 查看系统版本

```bash
cat /etc/os-release
```

关键结果：

```text
PRETTY_NAME="Ubuntu 26.04.1 LTS"
VERSION_ID="26.04"
VERSION_CODENAME=resolute
ID_LIKE=debian
```

含义：

- 当前是 Ubuntu 26.04.1 LTS。
- `LTS` 表示长期支持版本，适合服务器。
- 版本代号是 `resolute`。
- Ubuntu 属于 Debian 系，因此使用 `apt` 和 `.deb` 软件包。

`/etc` 可以理解为 Linux 的全局配置中心。它主要保存系统和服务配置，例如：

```text
/etc/os-release          系统版本信息
/etc/ssh/sshd_config     SSH 服务配置
/etc/netplan/            Ubuntu 网络配置
/etc/nginx/              Nginx 配置
/etc/mysql/              MySQL 配置
/etc/passwd              用户基本信息
/etc/group               用户组信息
```

### 2.3 查看主机和虚拟化信息

```bash
hostnamectl
```

关键结果：

```text
Static hostname: ubuntu-server-01
Virtualization: vmware
Operating System: Ubuntu 26.04.1 LTS
Kernel: Linux 7.0.0-31-generic
Architecture: x86-64
```

说明系统正确识别了 VMware 虚拟机、主机名、内核和 CPU 架构。

### 2.4 检查固定 IP

```bash
ip -br addr
```

结果：

```text
lo      UNKNOWN  127.0.0.1/8 ::1/128
ens33   UP       192.168.136.10/24 fe80::.../64
```

- `lo` 是回环网卡，只供本机访问本机。
- `ens33` 是 VMware 虚拟网卡。
- `UP` 表示网卡启用。
- `192.168.136.10/24` 是已经配置好的固定 IPv4 地址。
- `/24` 等同于子网掩码 `255.255.255.0`。

### 2.5 常用服务器检查命令

```bash
ip route
resolvectl status
ping -c 4 192.168.136.2
ping -c 4 www.baidu.com
free -h
df -hT
lscpu
systemctl status ssh --no-pager -l
ss -lntp
sudo ufw status verbose
timedatectl
```

这些命令分别用于检查：

| 命令 | 主要用途 |
|---|---|
| `ip route` | 默认网关和路由表 |
| `resolvectl status` | DNS 配置 |
| `ping -c 4` | 网络连通性，发送 4 次后停止 |
| `free -h` | 内存和 Swap |
| `df -hT` | 磁盘容量、使用率和文件系统类型 |
| `lscpu` | CPU 架构、核心数和型号 |
| `systemctl status ssh` | SSH 服务当前状态 |
| `ss -lntp` | 正在监听的 TCP 端口及进程 |
| `ufw status verbose` | Ubuntu 防火墙状态和规则 |
| `timedatectl` | 时间、时区和同步状态 |

### 2.6 实际资源检查结果

```text
CPU：4 个逻辑 CPU
内存：约 7.2 GiB
可用内存：约 6.6 GiB
Swap：4.0 GiB
根分区：29 GiB，使用约 27%
SSH：22 端口正在监听
UFW：当时为 inactive
```

当前资源足够用于单机练习部署：

```text
Nginx + RuoYi 后端 + MySQL + Redis
```

---

## 三、服务器基础检查脚本

### 3.1 为什么写成脚本

如果以后新增堡垒机或其他业务服务器，每次手动输入十几条命令效率较低，也容易漏项。把检查流程写成脚本后，可以在新服务器上复用。

脚本在本仓库中的位置：

```text
scripts/server-health-check.sh
```

复制到服务器后增加执行权限：

```bash
chmod +x server-health-check.sh
```

运行：

```bash
./server-health-check.sh
```

也可以使用绝对路径或家目录路径：

```bash
~/Linux--study-notes/scripts/server-health-check.sh
```

### 3.2 遇到的错误：把 `chmod` 写成 `chmode`

错误命令：

```bash
chmode +x ~/Linux--study-notes/scripts/server-health-check.sh
```

报错：

```text
Command 'chmode' not found
```

正确命令：

```bash
chmod +x ~/Linux--study-notes/scripts/server-health-check.sh
```

原因：正确命令是 `chmod`，来自 change mode，用于修改文件权限；不存在 `chmode` 命令。

---

## 四、Chrony、NTP 与守护进程

### 4.1 Chrony 是什么

Chrony 是 Linux 上的时间同步软件，通过 NTP（Network Time Protocol，网络时间协议）自动校准服务器时间。

```text
互联网 NTP 服务器
        ↓
     chronyd
        ↓
  Ubuntu 系统时钟
```

Chrony 主要由两部分组成：

```text
chronyd   后台守护进程，持续负责时间同步
chronyc   查询和管理 chronyd 的命令行工具
```

常用命令：

```bash
systemctl status chrony --no-pager
chronyc sources -v
chronyc tracking
```

本次检查结果：

```text
chrony.service：active (running)
开机启动：enabled
Reach：377
Leap status：Normal
系统与 NTP 时间误差：约 1.84 毫秒
```

`chronyc sources -v` 中常见标记：

```text
^*   当前选中的最佳 NTP 时间源
^+   可用并参与校准的辅助时间源
^-   当前没有参与组合，但不一定故障
^?   当前不可用
```

启动日志中曾出现：

```text
Can't synchronise: no selectable sources
```

但随后出现多个 `Selected source`，且 `chronyc tracking` 显示 `Leap status: Normal`，说明这只是开机初期网络尚未完全就绪时的短暂状态，不是持续故障。

### 4.2 为什么服务器时间必须准确

服务器时间不准可能导致：

- 多台服务器的日志顺序混乱。
- HTTPS 证书被判断为未生效或过期。
- 数据库记录时间错误。
- 定时任务执行时间错误。
- Token 和身份认证异常。
- 监控图表时间线错位。

### 4.3 守护进程和普通进程

普通进程通常由用户临时执行，完成任务后退出，例如：

```bash
cat /etc/os-release
cp file1 file2
```

守护进程通常长期在后台运行，等待请求并提供服务，例如：

```text
sshd       提供 SSH 服务
chronyd    提供时间同步
mysqld     提供 MySQL 数据库服务
```

普通程序放到后台运行不一定就是守护进程：

```bash
ping 127.0.0.1 &
```

它虽然进入后台，但仍可能与当前终端有关，也不是一个由 systemd 管理、长期提供系统服务的进程。

---

## 五、RuoYi-Vue 项目与单机部署架构

### 5.1 为什么选择 RuoYi-Vue

RuoYi-Vue 是前后端分离的后台管理系统，适合把多个运维知识点串成一条完整部署链路：

```text
源码
  ↓
JDK + Maven 构建 Java 后端
  ↓
MySQL 保存业务数据
  ↓
Redis 保存缓存和登录相关数据
  ↓
Node.js 构建 Vue 前端
  ↓
Nginx 提供静态页面并反向代理 API
  ↓
systemd 管理 Java 后端
```

第一阶段只用一台 Ubuntu：

```text
Windows 浏览器
      ↓
Ubuntu 192.168.136.10
├── Nginx + 前端静态文件
├── Java / RuoYi 后端（8080）
├── MySQL（3306，只监听本机）
└── Redis（6379，只监听本机）
```

这种单机部署不具备高可用，但适合学习、测试、小型内部系统，也能完整练习部署链路。

### 5.2 检查服务器现有环境

```bash
git --version 2>/dev/null || echo "未安装"
java -version 2>&1 || echo "未安装"
mvn -version 2>/dev/null || echo "未安装"
mysql --version 2>/dev/null || echo "未安装"
redis-server --version 2>/dev/null || echo "未安装"
nginx -v 2>&1 || echo "未安装"
node --version 2>/dev/null || echo "未安装"
npm --version 2>/dev/null || echo "未安装"
docker --version 2>/dev/null || echo "未安装"
```

初始结果只有 Git 2.53.0 已安装，Java、Maven、MySQL、Redis、Nginx、Node.js、npm 和 Docker 均未安装。

这次选择传统部署，不使用 Docker，以便理解每个组件如何安装、配置、启动和排错。

---

## 六、克隆若依源码与 Linux 路径问题

### 6.1 创建项目目录

```bash
cd ~
pwd
mkdir -p /home/admin01/projects
cd projects
```

`~` 对当前用户 `admin01` 来说等于：

```text
/home/admin01
```

`mkdir -p` 的 `-p` 表示需要时自动创建父目录；目录已存在时也不会报错。

### 6.2 克隆官方仓库

```bash
git clone https://github.com/yangzongzhuan/RuoYi-Vue.git
```

源码最终路径：

```text
/home/admin01/projects/RuoYi-Vue
```

检查远程仓库：

```bash
cd ~/projects/RuoYi-Vue
git remote -v
```

结果：

```text
origin  https://github.com/yangzongzhuan/RuoYi-Vue.git (fetch)
origin  https://github.com/yangzongzhuan/RuoYi-Vue.git (push)
```

`origin` 是远程仓库的默认简称；`fetch` 用于获取，`push` 用于推送。普通用户通常没有权限直接向作者仓库推送，后续若要保存自己的修改，应 Fork 到自己的 GitHub。

### 6.3 遇到的错误：家目录路径顺序写反

错误命令：

```bash
cd /admin01/home/
```

报错：

```text
No such file or directory
```

正确路径：

```bash
cd /home/admin01
```

也可以直接使用：

```bash
cd ~
```

Linux 普通用户家目录的一般形式是 `/home/用户名`，不是 `/用户名/home`。

### 6.4 遇到的错误：在 Git 仓库外执行 `git status`

当时所在目录：

```text
/home/admin01/projects
```

执行：

```bash
git status
```

报错：

```text
fatal: not a git repository (or any of the parent directories): .git
```

原因：真正的 `.git` 在：

```text
/home/admin01/projects/RuoYi-Vue/.git
```

Git 会在当前目录及其父目录中寻找 `.git`，但不会自动进入子目录寻找仓库。因此应先执行：

```bash
cd ~/projects/RuoYi-Vue
git status
```

### 6.5 `.`、`..`、`~` 和 `/`

| 符号 | 含义 |
|---|---|
| `.` | 当前目录 |
| `..` | 上一级目录 |
| `~` | 当前用户家目录 |
| `/` | Linux 文件系统根目录 |
| `-` | 上一次所在目录，可配合 `cd -` |

执行 `cd .` 会留在当前目录，不会进入项目。

错误输入：

```bash
c d..
```

Shell 会把 `c` 当成命令名，所以提示：

```text
c: command not found
```

正确写法：

```bash
cd ..
```

### 6.6 遇到的错误：把 `--oneline` 写成 `--online`

错误命令：

```bash
git log -1 --online
```

报错：

```text
fatal: unrecognized argument: --online
```

正确命令：

```bash
git log -1 --oneline
```

- `-1`：只显示最近一条提交。
- `--oneline`：以一行简洁格式显示。

报错不是“没有提交”，而是 Git 不认识拼错的参数。应区分：

```text
没有输出 ≠ 命令报错
```

### 6.7 项目主要目录

```bash
ls -d */
```

主要目录及作用：

| 目录 | 作用 |
|---|---|
| `ruoyi-admin/` | 后端启动模块，生成可运行 JAR |
| `ruoyi-common/` | 公共工具与通用代码 |
| `ruoyi-framework/` | 权限、安全认证等框架代码 |
| `ruoyi-system/` | 用户、角色、菜单等系统功能 |
| `ruoyi-generator/` | 代码生成器 |
| `ruoyi-quartz/` | 定时任务模块 |
| `ruoyi-ui/` | Vue 前端 |
| `sql/` | 数据库初始化 SQL |

---

## 七、根据项目要求安装 JDK 17

### 7.1 从 `pom.xml` 查询 Java 版本

```bash
grep -n "java.version" pom.xml
```

`grep` 在文件中搜索文本，`-n` 同时显示行号。本项目要求 Java 17，所以不应盲目安装 Ubuntu 推荐的最新 Java 25 或 26。

### 7.2 查询并安装 JDK

```bash
apt-cache policy openjdk-17-jdk-headless
sudo apt install openjdk-17-jdk-headless
```

为什么选择这个包：

- `openjdk-17`：Java 17 的开源实现。
- `jdk`：包含编译和运行工具。
- `headless`：不安装桌面图形界面相关依赖，更适合服务器。

验证：

```bash
java -version
javac -version
```

本次安装版本：

```text
17.0.20
```

职责区别：

```text
java    启动 JVM，运行已经编译好的 Java 程序
javac   把 .java 源码编译成 .class 字节码
```

### 7.3 查找 Java 真实路径

```bash
which java
readlink -f "$(which java)"
```

结果：

```text
/usr/lib/jvm/java-17-openjdk-amd64/bin/java
```

因此 JDK 根目录，也就是常说的 `JAVA_HOME`，为：

```text
/usr/lib/jvm/java-17-openjdk-amd64
```

### 7.4 遇到的错误：使用中文全角括号

错误命令：

```bash
readlink -f "$（which java)"
```

结果变成了当前目录下的普通路径：

```text
/home/admin01/projects/RuoYi-Vue/$（which java)
```

正确命令：

```bash
readlink -f "$(which java)"
```

`$()` 是 Shell 的命令替换语法，会先执行括号里的 `which java`，再把其输出交给 `readlink -f`。中文输入法产生的全角括号不属于 Shell 语法。

---

## 八、Maven 与若依后端构建

### 8.1 Maven 的作用

Maven 是 Java 项目的构建和依赖管理工具。它读取 `pom.xml` 后完成：

```text
下载第三方依赖
      ↓
调用 JDK 编译源码
      ↓
执行测试
      ↓
把项目打包成 JAR
```

几个概念的关系：

```text
Git       获取和管理源码
JDK       编译、运行 Java
Maven     下载依赖、组织构建、打包项目
pom.xml   Maven 的项目说明书
JAR       最终的 Java 程序包
```

Maven 默认把下载的依赖缓存到：

```text
/home/admin01/.m2/repository
```

第一次构建需要下载大量依赖，之后再次构建通常更快。

### 8.2 安装和验证 Maven

```bash
apt-cache policy maven
sudo apt install maven
mvn -version
```

验证时应确认：

```text
Apache Maven：能够显示版本
Java version：17.0.20
Java home：/usr/lib/jvm/java-17-openjdk-amd64
```

### 8.3 构建若依后端

```bash
cd ~/projects/RuoYi-Vue
mvn clean package -DskipTests
```

参数含义：

- `mvn`：启动 Maven。
- `clean`：删除以前的构建结果，主要是各模块的 `target` 目录。
- `package`：编译并打包。
- `-DskipTests`：本次跳过测试阶段，减少第一次部署的干扰。

不要用 `sudo mvn`，否则 `~/.m2` 中的缓存文件可能归 root 所有，之后普通用户构建可能遇到权限问题。

最终看到：

```text
BUILD SUCCESS
```

说明后端构建成功。

### 8.4 检查构建产物

```bash
ls -lh ruoyi-admin/target/
find ruoyi-admin/target -maxdepth 1 -type f -name "*.jar" -printf "%f\n"
find . -maxdepth 2 -type d -name target -print
```

结果：

```text
ruoyi-admin.jar           约 87 MB
ruoyi-admin.jar.original  约 65 KB
```

- `ruoyi-admin.jar` 是包含依赖、后续使用 `java -jar` 运行的程序包。
- `.original` 是 Spring Boot 重新打包前的原始 JAR，通常不直接运行。

构建成功不等于应用已经能启动，因为运行阶段还依赖 MySQL 和 Redis。

---

## 九、检查若依运行配置

### 9.1 查看 SQL 和配置文件

```bash
find sql -maxdepth 2 -type f -printf "%p\n"
find ruoyi-admin/src/main/resources -maxdepth 2 -type f -print
sed -n '1,220p' ruoyi-admin/src/main/resources/application.yml
sed -n '1,260p' ruoyi-admin/src/main/resources/application-druid.yml
```

项目包含：

```text
sql/ry_20260417.sql   若依主表和初始化数据
sql/quartz.sql        Quartz 定时任务表
```

从配置中读到：

```text
若依版本：3.9.2
后端端口：8080
MySQL：localhost:3306
数据库名：ry-vue
Redis：localhost:6379
Redis 数据库索引：0
```

需要后续修改的默认配置：

```yaml
ruoyi:
  profile: D:/ruoyi/uploadPath
```

这是 Windows 路径，Linux 部署时可以改成：

```yaml
ruoyi:
  profile: /opt/ruoyi/uploadPath
```

默认数据库配置使用：

```yaml
username: root
password: password
```

实际部署不让应用使用 MySQL `root`，而是创建只能访问若依数据库的专用账号。

### 9.2 XML 与数据库的关系

数据库内容不是由 `pom.xml` 自动生成的。

```text
pom.xml
  管理 Java 依赖、版本、模块和构建流程

application-druid.yml
  告诉若依连接哪台 MySQL、哪个数据库、使用什么账号

sql/*.sql
  真正创建表、字段、索引和初始数据

*Mapper.xml
  告诉 MyBatis 如何查询和修改已经存在的数据表
```

---

## 十、安装和初始化 MySQL

### 10.1 安装与检查

```bash
sudo apt install mysql-server
sudo systemctl enable --now mysql

mysql --version
systemctl is-active mysql
systemctl is-enabled mysql
sudo ss -lntp | grep 3306
```

本次 MySQL 版本：

```text
MySQL 8.4.11
```

`enable --now` 同时完成：

- `enable`：设置开机自动启动。
- `--now`：立即启动当前服务。

单机部署时，让 MySQL 只监听 `127.0.0.1:3306` 更安全。Java 后端和 MySQL 在同一台服务器上，不需要向局域网或公网开放 3306。

### 10.2 Ubuntu 本机管理员登录

```bash
sudo mysql
```

Ubuntu 上的 MySQL root 常使用本机系统身份认证，所以具有 sudo 权限的系统用户可以通过 `sudo mysql` 进入管理终端。

Linux Shell 提示符：

```text
admin01@ubuntu-server-01:~$
```

MySQL 提示符：

```text
mysql>
```

进入 `mysql>` 后必须输入 SQL，而不是 Linux 命令。

### 10.3 创建数据库和应用用户

在 `mysql>` 中执行：

```sql
CREATE DATABASE `ry-vue`
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

CREATE USER 'ruoyi_app'@'localhost'
IDENTIFIED BY '请替换成自己的强密码';

GRANT ALL PRIVILEGES ON `ry-vue`.*
TO 'ruoyi_app'@'localhost';

SHOW DATABASES;
SHOW GRANTS FOR 'ruoyi_app'@'localhost';
EXIT;
```

数据库名 `ry-vue` 含有连字符 `-`，所以 SQL 中使用反引号包围：

```text
`ry-vue`
```

账号设计：

```text
MySQL 管理账号：root
应用账号：ruoyi_app
允许来源：localhost
权限范围：ry-vue.*
```

这里的授权是“只限制在 `ry-vue` 数据库范围内的全部权限”，比让应用使用 root 安全，但并不是最严格的最小权限。学习环境先使用这种简单可靠的方案，生产环境可进一步收窄权限。

> 安全注意：笔记、GitHub、聊天记录和截图中不要保存真实数据库密码。如果密码曾经公开，应立即使用 `ALTER USER` 修改。

修改密码：

```sql
ALTER USER 'ruoyi_app'@'localhost'
IDENTIFIED BY '新的强密码';
```

### 10.4 导入若依 SQL

回到 Linux Shell：

```bash
cd ~/projects/RuoYi-Vue
sudo mysql --database='ry-vue' < sql/ry_20260417.sql
sudo mysql --database='ry-vue' < sql/quartz.sql
```

`<` 是输入重定向：

```text
SQL 文件内容
    ↓
交给 mysql 客户端执行
    ↓
在 ry-vue 中创建表和初始数据
```

成功时可能没有任何输出，直接回到提示符。可以用后续查询确认，而不能只凭“没有输出”下结论。

### 10.5 遇到的错误：行尾反斜杠导致命令粘连

错误命令：

```bash
sudo mysql --database='ry-vue' < sql/quartz.sql\
```

行尾 `\` 在 Shell 中表示“当前命令还没有结束，下一行继续”。因此下一条命令被拼接进文件名，出现类似报错：

```text
sql/quartz.sqlsudo: No such file or directory
```

正确命令末尾不能带 `\`：

```bash
sudo mysql --database='ry-vue' < sql/quartz.sql
```

如果终端提示符变为：

```text
>
```

通常表示 Shell 正在等待命令继续输入。可以按 `Ctrl+C` 取消当前未完成命令，然后重新输入正确命令。

### 10.6 验证导入结果

查看全部表：

```bash
sudo mysql --database='ry-vue' -e "SHOW TABLES;"
```

导入主 SQL 后出现了 20 张业务表，例如：

```text
sys_user
sys_role
sys_menu
sys_config
sys_job
gen_table
```

验证 Quartz 表：

```bash
sudo mysql --database='ry-vue' -e "SHOW TABLES LIKE 'QRTZ%';"
```

统计表数量：

```bash
sudo mysql --database='ry-vue' -NBe \
"SELECT COUNT(*)
 FROM information_schema.tables
 WHERE table_schema='ry-vue';"
```

参数含义：

- `-e`：执行后面的 SQL 并退出。
- `-N`：不显示列标题。
- `-B`：使用便于脚本处理的批处理输出格式。

### 10.7 使用应用账号测试 TCP 连接

```bash
mysql -u ruoyi_app -p -h 127.0.0.1 --database='ry-vue'
```

- `-u ruoyi_app`：指定数据库用户。
- `-p`：交互式输入密码，不把密码写在命令历史中。
- `-h 127.0.0.1`：通过本机 TCP 连接，模拟 Java 后端的连接方式。
- `--database='ry-vue'`：登录后直接选择若依数据库。

登录后验证：

```sql
SELECT USER(), CURRENT_USER(), DATABASE();
SHOW TABLES;
EXIT;
```

本次已经成功使用 `ruoyi_app` 登录，说明：

- MySQL 服务正常。
- 3306 本机连接正常。
- 用户名和密码有效。
- `ry-vue` 权限有效。
- Java 后端后续具备连接数据库的基础条件。

---

## 十一、DBeaver 是否必需

DBeaver 不是若依运行必需组件。当前所有初始化操作都能通过 MySQL 命令行完成。

如果后续需要从 Windows 使用 DBeaver，推荐使用 SSH 隧道：

```text
Windows DBeaver
      │ SSH：192.168.136.10:22
      ▼
Ubuntu
      │ MySQL：127.0.0.1:3306
      ▼
MySQL
```

这样无需：

- 把 MySQL 改成监听 `0.0.0.0`。
- 在 UFW 中向外开放 3306。
- 允许数据库 root 远程登录。

DBeaver 数据库连接信息：

```text
Host：127.0.0.1
Port：3306
Database：ry-vue
Username：ruoyi_app
Password：本地保存的真实密码
```

SSH 隧道信息：

```text
Host：192.168.136.10
Port：22
Username：admin01
认证：SSH 密码或私钥
```

---

## 十二、今天的重要认识

### 12.1 构建成功不等于部署完成

```text
BUILD SUCCESS
```

只说明源码已经成功编译并生成 JAR。若依真正运行还依赖：

```text
MySQL
Redis
正确的 application.yml
正确的 application-druid.yml
Linux 上传目录
```

### 12.2 命令是否成功与当前目录有关

同一条 `git status`：

- 在 `/home/admin01/projects` 中执行会失败。
- 在 `/home/admin01/projects/RuoYi-Vue` 中执行会成功。

执行项目前先观察提示符或使用：

```bash
pwd
```

### 12.3 项目文件各有职责

```text
pom.xml                  构建与依赖
application.yml          应用与 Redis 等通用配置
application-druid.yml    MySQL 数据源配置
sql/*.sql                建表和初始数据
*Mapper.xml              数据库查询与修改规则
ruoyi-admin.jar          可运行后端程序
```

### 12.4 生产化部署与本地运行不同

在 Windows 的 IDEA 中点击 Run，只是开发环境运行。服务器化部署还要解决：

- 脱离 IDE 启动。
- SSH 断开后持续运行。
- 开机自动启动和故障恢复。
- Nginx 入口与反向代理。
- 日志、权限、防火墙、备份和监控。

---

## 十三、下一步计划

下一次继续：

```text
1. 安装和检查 Redis
2. 创建 Linux 上传目录
3. 修改 MySQL 专用账号配置
4. 修改 Redis 配置
5. 把 Windows 上传路径改成 Linux 路径
6. 重新构建或使用外部配置
7. 首次启动 ruoyi-admin.jar
8. 根据日志排查启动问题
9. 安装 Node.js 并构建前端
10. 使用 Nginx 部署前端并反向代理后端
11. 使用 systemd 管理若依后端
```

后续提交到公开 GitHub 时必须排除：

```text
数据库真实密码
Redis 真实密码
SSH 私钥
Token 和密钥
日志文件
target/ 构建产物
上传文件
```
