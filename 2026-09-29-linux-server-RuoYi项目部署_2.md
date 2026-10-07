# Ubuntu Server 部署 RuoYi-Vue（2）：Redis、后端配置与首次启动

- 日期：2026-09-28 ～ 2026-09-29
- 环境：Windows、VMware Workstation、Ubuntu Server 26.04.1 LTS、SSH
- 服务器主机名：ubuntu-server-01
- 普通用户：admin01
- 服务器固定 IP：192.168.136.10/24
- 项目：RuoYi-Vue 3.9.2
- 项目路径：/home/admin01/projects/RuoYi-Vue

---

## 一、本阶段完成的内容

本阶段完成了若依后端从依赖准备到首次启动的验证。

1. 安装并验证 Redis。
2. 定位数据库、Redis 和上传目录配置。
3. 创建 Linux 上传目录并处理权限。
4. 修改配置后重新打包后端 JAR。
5. 排查 YAML 格式错误、日志目录不存在和 MySQL 认证失败。
6. 成功启动后端并验证 8080 端口和接口响应。

当前部署进度：

~~~
Ubuntu 基础配置       已完成
Git 获取源码          已完成
JDK 17               已完成
Maven 构建后端        已完成
MySQL 初始化          已完成
Redis                 已完成
后端配置与手工启动    已完成
Node.js / 前端构建    尚未开始
Nginx                 尚未开始
systemd 管理若依      尚未完成
~~~

---

## 二、Redis 安装与验证

在 Ubuntu 中输入 Windows 常用的 where redis 会得到 command not found。这个结果只说明 Ubuntu 没有 where 命令，不能说明 Redis 没安装。

实际安装：

~~~
sudo apt install redis
~~~

安装了 redis-server 和 redis-tools。本次 Redis 版本为 8.0.5。

安装后发现 redis.service 是指向 redis-server.service 的链接。使用 systemctl enable redis 时，systemd 拒绝操作链接单元，所以后续使用 redis-server 作为正式服务名。

服务验收：

~~~
sudo systemctl enable --now redis-server
systemctl is-active redis-server
systemctl is-enabled redis-server
redis-cli -h 127.0.0.1 -p 6379 ping
ss -ntpl
~~~

实际结果：

~~~
active
enabled
PONG
~~~

监听地址为 127.0.0.1:6379 和 [::1]:6379。这说明 Redis 已运行、已设置开机启动，并且只接受本机连接。redis-cli ping 是 Redis 协议测试命令，返回 PONG；它和 ICMP ping 不是同一件事。

曾经执行 sudo ufw allow 6379，后来确认这是多余的。Redis 只监听回环地址，删除对外放行规则更符合最小权限原则。

---

## 三、定位若依配置

关键文件：

~~~
ruoyi-admin/src/main/resources/application.yml
ruoyi-admin/src/main/resources/application-druid.yml
~~~

搜索命令：

~~~
grep -RIlE 'spring.data.redis|jdbc:mysql|ruoyi.profile|uploadPath' ruoyi-admin/src/main/resources
~~~

application.yml 中确认了 ruoyi.profile、server.port: 8080、spring.profiles.active: druid 和 spring.data.redis 配置。application-druid.yml 中主库位于 master，slave 保持关闭，空的 slave 配置不需要填写。

最终配置目标：

~~~
数据库：127.0.0.1:3306/ry-vue
数据库账号：ruoyi_app
Redis：127.0.0.1:6379
Redis 数据库索引：0
Redis 密码：空
~~~

redis-cli 不带密码即可返回 PONG，因此 Redis 当前没有启用认证。

---

## 四、上传目录和日志目录

上传目录保存头像、图片、附件等运行期间产生的文件。最终使用：

~~~
/home/admin01/projects/ruoyi/uploadPath
~~~

刚创建时目录属于 root:root，admin01 没有写权限。使用绝对路径修正：

~~~
sudo chown -R admin01:admin01 /home/admin01/projects/ruoyi/uploadPath
~~~

随后用当前用户创建和删除临时文件，验证写权限。排错时要区分 /ruoyi/uploadPath 和 /home/admin01/projects/ruoyi/uploadPath，前者从文件系统根目录开始，后者才是实际目录。

若依 Logback 默认写入 /home/ruoyi/logs/sys-info.log、sys-error.log 和 sys-user.log。第一次启动时因为 /home/ruoyi/logs 不存在，程序在日志初始化阶段退出。

正确处理：

~~~
sudo mkdir -p /home/ruoyi/logs
sudo chown admin01:admin01 /home/ruoyi/logs
~~~

日志目录和上传目录用途不同，不能混用。

---

## 五、配置备份与重新打包

修改前在项目根目录创建 backup，并备份两个配置文件。第一次备份失败是因为源文件实际位于 ruoyi-admin/src/main/resources/，目标 backup 目录也尚未创建。

修改后的关键值：

~~~
数据库主库：ruoyi_app@localhost
数据库：ry-vue
Redis：127.0.0.1:6379
上传目录：/home/admin01/projects/ruoyi/uploadPath
~~~

修改源码配置后必须重新打包，旧 JAR 不会自动更新。

YAML 冒号后的空格很重要。错误写法是 username:ruoyi_app，正确写法是 username: ruoyi_app；password 同理。

---

## 六、后端启动排错

第一次启动出现 while scanning a simple key 和 could not find expected ':'，原因是 username 和 password 的冒号后没有空格，修正后重新打包。

第二次启动已越过 YAML 解析，但因为 /home/ruoyi/logs 不存在而退出。创建目录并授权后继续排查。

之后应用日志出现：

~~~
Access denied for user 'ruoyi_app'@'localhost'
~~~

查询 MySQL 用户和权限确认 ruoyi_app@localhost 存在，并且拥有 ry-vue 数据库权限。随后使用 TCP 方式测试登录：

~~~
mysql --protocol=TCP -h localhost -P 3306 -u ruoyi_app -p ry-vue
~~~

仍然认证失败，所以结论是密码不匹配，而不是数据库权限缺失。使用 ALTER USER 修改账号密码，同步 application-druid.yml，重新打包并启动。

最终确认 Application Version: 3.9.2，Java 监听 8080，HTTP 请求有响应，Redis 单独验证返回 PONG。

这次实际验证了 YAML 可解析、日志目录可写、MySQL 账号密码和权限正确、后端 JAR 可以启动、8080 端口正常监听。

---

## 七、重要认识与下一步

cut -d: -f1 /etc/passwd 查询的是 Linux 系统用户。ruoyi_app 是 MySQL 内部账号，不会出现在 /etc/passwd 中，应在 MySQL 内查询 mysql.user。

MySQL 账号会同时匹配用户名和来源主机。ruoyi_app@localhost 与 ruoyi_app@127.0.0.1 可能是不同账号。

BUILD SUCCESS 只说明 JAR 已生成。运行阶段还要验证配置格式、日志目录、数据库认证、Redis 连接、端口监听和 HTTP 接口。

本阶段后端已经成功手工启动，但仍依赖当前 SSH 窗口。下一阶段获取 Vue 前端源码、安装 Node.js、构建前端、配置 Nginx，并最终使用 systemd 管理后端。

提交到 GitHub 时不要包含数据库真实密码、Redis 密码、SSH 私钥、Token、日志、target 构建产物和上传文件。
