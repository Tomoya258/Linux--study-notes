# Ubuntu Server 部署 RuoYi-Vue（2）：Redis、配置文件、后端启动与排错

- 日期：2026-09-28 ～ 2026-09-29
- 环境：Windows、VMware Workstation、Ubuntu Server 26.04.1 LTS、SSH
- 服务器主机名：ubuntu-server-01
- 普通用户：admin01
- 服务器固定 IP：192.168.136.10/24
- 项目：RuoYi-Vue 3.9.2
- 项目路径：/home/admin01/projects/RuoYi-Vue

---

## 一、本阶段目标

上一阶段已经完成 JDK、Maven、MySQL 和若依数据库初始化，但后端 JAR 还没有真正启动。

本阶段的目标是把后端运行所需的三个外部条件准备好：

1. Redis 可用。
2. 若依配置能够连接 MySQL 和 Redis。
3. Linux 上有可写的上传目录和日志目录。

完成配置后重新打包，并通过真实启动结果验证，而不是只根据计划判断完成。

本阶段实际完成：

1. 安装 Redis 8.0.5。
2. 验证 Redis 运行状态、开机启动和本机监听。
3. 找到 application.yml 和 application-druid.yml。
4. 创建 Linux 上传目录并处理所有者。
5. 创建若依日志目录。
6. 修改数据库、Redis 和上传目录配置。
7. 重新打包后端 JAR。
8. 排查 YAML 格式错误。
9. 排查日志目录不存在。
10. 排查 MySQL 应用账号密码错误。
11. 成功启动若依后端并验证 HTTP 接口。

当前部署状态：

~~~
Ubuntu 基础配置        已完成
Git 获取源码           已完成
JDK 17                已完成
Maven 构建后端         已完成
MySQL 初始化           已完成
Redis                  已完成
若依后端手工启动       已完成
前端                   尚未构建
Nginx                  尚未配置
systemd                尚未配置
~~~

---

## 二、Redis 安装和验收

### 2.1 把 Windows 命令直接带到 Linux

最开始尝试：

~~~
where redis
~~~

Ubuntu 返回：

~~~
where: command not found
~~~

这里不能直接得出 Redis 没安装。问题只是命令来自 Windows 习惯。

Linux 中可以从几个层面检查：

~~~
command -v redis-cli
apt-cache policy redis-server
systemctl status redis-server
~~~

它们分别用于：

- 查找命令是否在 PATH 中。
- 查看软件包是否已安装或可安装。
- 查看服务是否存在及当前状态。

### 2.2 安装 Redis

实际执行：

~~~
sudo apt install redis
~~~

安装过程中带来了：

- redis-server：Redis 服务端。
- redis-tools：包含 redis-cli。
- liblzf1：相关依赖。

安装版本为：

~~~
Redis 8.0.5
~~~

安装输出中出现：

~~~
redis.service -> redis-server.service
~~~

这表示 redis.service 是链接或兼容名称，真正的服务单元是 redis-server.service。

后来执行：

~~~
systemctl enable redis
~~~

得到：

~~~
Failed to enable unit: Refusing to operate on linked unit file redis.service
~~~

原因是 systemd 拒绝直接对链接单元执行 enable。之后改用真实服务名：

~~~
sudo systemctl enable --now redis-server
~~~

这里：

- enable：设置开机启动。
- --now：同时立即启动。
- redis-server：真正的服务单元名称。

### 2.3 Redis 验收

执行：

~~~
systemctl is-active redis-server
systemctl is-enabled redis-server
redis-cli -h 127.0.0.1 -p 6379 ping
ss -ntpl
~~~

结果：

~~~
active
enabled
PONG
~~~

监听结果中有：

~~~
127.0.0.1:6379
[::1]:6379
~~~

验证含义：

- active：当前正在运行。
- enabled：已设置开机启动。
- PONG：redis-cli 通过本机 TCP 访问 Redis 成功。
- 127.0.0.1 和 [::1]：只监听本机回环地址。

redis-cli 的 ping 是 Redis 协议命令，不是 ICMP 网络 ping。返回 PONG 只能证明 Redis 服务本身可用，还不能证明若依已经成功连接 Redis。

### 2.4 防火墙 6379 的误操作

当时 UFW 原本只放行 SSH，后来误执行：

~~~
sudo ufw allow 6379
~~~

这个规则没有必要。Redis 只监听本机回环地址，外部机器无法通过服务器固定 IP 连接 Redis。同机部署也不需要开放 6379 或配置 VMware 端口转发。

这个问题体现了两层控制的区别：

~~~
服务监听地址：决定程序接受哪些网络接口上的连接
防火墙规则：决定数据包是否允许到达服务器
~~~

即使服务只监听本机，也应清理不必要的对外规则。本次过程记录了误加规则，但删除规则的最终输出没有保留，后续应重新查看 UFW 状态确认。

---

## 三、定位若依配置文件

### 3.1 为什么先定位再修改

若依的配置不是一个文件全部负责。不同文件分别保存通用配置、环境选择和数据源配置。如果直接修改错误文件，重新打包后程序仍会读取旧值。

当时先在项目根目录：

~~~
cd /home/admin01/projects/RuoYi-Vue
~~~

尝试使用 ripgrep：

~~~
rg -l 'spring.data.redis|jdbc:mysql|ruoyi.profile|uploadPath' ruoyi-admin/src/main/resources
~~~

系统提示：

~~~
Command 'rg' not found
~~~

rg 是搜索工具，不是项目依赖。没有安装它，改用 Ubuntu 通常自带的 grep：

~~~
grep -RIlE 'spring.data.redis|jdbc:mysql|ruoyi.profile|uploadPath' ruoyi-admin/src/main/resources
~~~

这条命令只输出匹配文件名，不会修改文件，也不会直接输出密码。

结果：

~~~
ruoyi-admin/src/main/resources/application-druid.yml
ruoyi-admin/src/main/resources/application.yml
~~~

### 3.2 application.yml

搜索结果显示：

~~~
ruoyi-admin/src/main/resources/application.yml
~~~

其中看到：

~~~
ruoyi:
  profile: D:/ruoyi/uploadPath

server:
  port: 8080

spring:
  profiles:
    active: druid
  data:
    redis:
      host: localhost
      port: 6379
      database: 0
~~~

含义：

- profile 是若依保存上传文件时使用的基础目录。
- 后端监听 8080。
- 当前启用的 Spring 配置环境是 druid。
- Redis 位于 spring.data.redis 层级下。

D:/ruoyi/uploadPath 是 Windows 路径。Ubuntu 没有 Windows 的 D 盘，因此必须改成 Linux 绝对路径。

### 3.3 application-druid.yml

数据库配置文件为：

~~~
ruoyi-admin/src/main/resources/application-druid.yml
~~~

主库配置位于 master：

~~~
spring:
    datasource:
        druid:
            master:
                url: jdbc:mysql://localhost:3306/ry-vue
                username: root
                password: 已配置
~~~

slave 配置为：

~~~
slave:
    enabled: false
~~~

因为 slave 没有启用，所以空的 slave url、username 和 password 不需要填写。实际只修改 master。

查看配置结构时使用了 sed 和管道。例如：

~~~
sed -n '1,20p' application-druid.yml | sed -E '/password:/s/:.*/: [已隐藏]/'
~~~

前一个 sed 选取行，后一个 sed 将 password 冒号后的内容替换为已隐藏。管道符把前一个命令输出交给后一个命令处理，整个过程只读文件。

---

## 四、Linux 上传目录

### 4.1 上传目录有什么作用

上传目录用于保存运行期间产生的文件，例如：

- 用户头像。
- 图片。
- 附件。
- 其他业务上传文件。

典型关系：

~~~
浏览器上传文件
      ↓
若依后端接收
      ↓
保存到 profile 指定目录
      ↓
数据库保存文件名或路径
~~~

源码中的 Windows 路径：

~~~
D:/ruoyi/uploadPath
~~~

最终改为：

~~~
/home/admin01/projects/ruoyi/uploadPath
~~~

这个目录放在后端源码目录旁边，便于区分源码、构建产物和运行数据。

### 4.2 目录路径混淆

创建目录后，曾经在已经位于 uploadPath 的目录中执行：

~~~
realpath uploadPath
~~~

结果出现：

~~~
/home/admin01/projects/ruoyi/uploadPath/uploadPath
~~~

这不是实际目录多了一层，而是当前工作目录已经是 uploadPath，再写 uploadPath 就表示寻找一个子目录。

之后使用：

~~~
find / -type d -name "uploadPath" 2>/dev/null
~~~

确认真实路径：

~~~
/home/admin01/projects/ruoyi/uploadPath
~~~

路径中的开头斜杠很重要：

~~~
/ruoyi/uploadPath
~~~

表示从文件系统根目录开始。

~~~
/home/admin01/projects/ruoyi/uploadPath
~~~

才是当前用户家目录下的实际路径。

### 4.3 所有者和写权限

刚创建目录时看到：

~~~
drwxr-xr-x root root uploadPath
~~~

目录属于 root:root。权限 755 允许其他用户进入和读取，但 admin01 不是所有者，不能在里面创建上传文件。

第一次尝试时还出现了几个错误：

- 在 uploadPath 目录中再次写 uploadPath，目标不存在。
- 把实际目录写成 /ruoyi/uploadPath，路径从根目录开始，因此不存在。
- 把 chown 拼成 chowm，系统提示 command not found。

最终使用完整绝对路径：

~~~
sudo chown -R admin01:admin01 /home/admin01/projects/ruoyi/uploadPath
~~~

修正后目录显示为 admin01:admin01。随后用当前用户创建和删除临时文件，验证写权限。

学习重点：

~~~
权限问题先看路径，再看所有者，再看读写执行位。
~~~

不应为了省事直接使用 chmod 777。

---

## 五、配置文件备份

修改配置前需要保留原始版本，便于回退和比较。

第一次执行：

~~~
cp application-druid.yml backup/application-druid.yml.时间戳.bak
~~~

报错：

~~~
cp: cannot stat 'application-druid.yml': No such file or directory
~~~

原因是当前位于项目根目录，文件实际位于：

~~~
ruoyi-admin/src/main/resources/application-druid.yml
~~~

之后使用正确源路径，但又出现：

~~~
cp: cannot create regular file 'backup/...': No such file or directory
~~~

原因是 backup 目录还不存在。备份命令需要同时满足：

1. 源文件路径正确。
2. 目标目录存在。
3. 文件名中的时间格式正确。

还曾把时间格式写成：

~~~
%Y%m%d_#H%M%S
~~~

小时应使用：

~~~
%Y%m%d_%H%M%S
~~~

其中 %H 是小时，#H 不是 date 的格式占位符。

Git diff 一度也无法使用：

~~~
fatal: not a git repository
~~~

当时不在真正的项目仓库目录。进入 /home/admin01/projects/RuoYi-Vue 后，仓库本身是正常的。备份文件也可以用 diff -u 比较，不一定依赖 Git。

---

## 六、修改配置目标

### 6.1 数据库

只修改 application-druid.yml 的 master：

~~~
url: jdbc:mysql://127.0.0.1:3306/ry-vue?...
username: ruoyi_app
password: 真实密码
~~~

笔记和聊天中不记录真实密码。

数据库应用账号不是 Linux 系统账号。后来执行：

~~~
cut -d: -f1 /etc/passwd
~~~

看到 root、mysql、redis、admin01 等，这是 /etc/passwd 中的 Linux 用户列表。ruoyi_app 是 MySQL 内部用户，不会出现在这里。MySQL 账号应在 mysql.user 中查询。

### 6.2 Redis

application.yml 中使用：

~~~
host: 127.0.0.1
port: 6379
database: 0
password:
~~~

Redis 当前没有启用认证，因为不带密码执行 redis-cli ping 已返回 PONG。password 保持为空。

### 6.3 上传目录

application.yml 中使用：

~~~
profile: /home/admin01/projects/ruoyi/uploadPath
~~~

路径必须和真实目录完全一致，必须是 Linux 绝对路径。

### 6.4 YAML 格式

第一次修改后启动失败：

~~~
username:ruoyi_app
password:数据库密码
~~~

错误信息：

~~~
while scanning a simple key
could not find expected ':'
~~~

YAML 中冒号后需要空格，正确写法：

~~~
username: ruoyi_app
password: 数据库密码
~~~

YAML 还要注意：

- 使用空格，不使用 Tab。
- 同一层级保持相同缩进。
- 冒号后的值不要误删。
- 修改配置后必须重新打包，因为旧 JAR 里仍然是旧配置。

---

## 七、日志目录排错

YAML 修正后，程序继续启动但出现：

~~~
Failed to create parent directories for [/home/ruoyi/logs/sys-info.log]
FileNotFoundException: /home/ruoyi/logs/sys-info.log
~~~

若依 Logback 的默认日志路径是：

~~~
/home/ruoyi/logs/sys-info.log
/home/ruoyi/logs/sys-error.log
/home/ruoyi/logs/sys-user.log
~~~

当时只创建了 /home/admin01/projects/ruoyi/uploadPath，上传目录不能替代日志目录。

还曾经执行：

~~~
mkdir /ruoyi/logs
~~~

报错：

~~~
No such file or directory
~~~

因为 /ruoyi 表示根目录下的目录，且父目录不存在。随后执行：

~~~
mkdir ruoyi
~~~

在 /home 下又遇到 Permission denied，因为普通用户不能直接在 /home 创建目录。使用 sudo 分步创建：

~~~
sudo mkdir /home/ruoyi
sudo mkdir /home/ruoyi/logs
~~~

之后误把 chown 目标写成 /ruoyi/logs，再次得到路径不存在。正确路径是：

~~~
sudo chown admin01:admin01 /home/ruoyi/logs
~~~

并用 ls -ld 和临时文件测试确认 admin01 可写。

这次的排错链路是：

~~~
错误日志路径
    ↓
确认程序实际要写哪里
    ↓
区分 /ruoyi 和 /home/ruoyi
    ↓
创建父目录
    ↓
修正所有者
    ↓
测试写入
~~~

---

## 八、MySQL 认证失败排查

日志目录问题解决后，若依进入数据库初始化，但出现：

~~~
Access denied for user 'ruoyi_app'@'localhost' (using password: YES)
~~~

这说明程序已经读取到了账号和密码，并且确实尝试连接 MySQL。此时不能先假设是网络、端口或数据库不存在。

### 8.1 查询用户是否存在

进入 MySQL 后执行：

~~~
SELECT user, host FROM mysql.user WHERE user='ruoyi_app';
~~~

结果：

~~~
ruoyi_app | localhost
~~~

说明用户存在，并且允许来源是 localhost。

### 8.2 查询权限

执行：

~~~
SHOW GRANTS FOR 'ruoyi_app'@'localhost';
~~~

结果包含：

~~~
GRANT ALL PRIVILEGES ON ry-vue.* TO ruoyi_app@localhost
~~~

说明数据库权限已经授予。此时问题更可能是密码，而不是授权。

### 8.3 用相近方式手工登录

退出 MySQL 后执行：

~~~
mysql --protocol=TCP -h localhost -P 3306 -u ruoyi_app -p ry-vue
~~~

输入同一个应用密码，仍然出现：

~~~
ERROR 1045 (28000): Access denied for user 'ruoyi_app'@'localhost'
~~~

因此确认是 MySQL 用户密码与配置中使用的密码不一致。

### 8.4 修复账号密码

使用 MySQL 管理权限执行：

~~~
ALTER USER 'ruoyi_app'@'localhost'
IDENTIFIED BY '新的强密码';
~~~

然后把同一个新密码填入 application-druid.yml，重新打包，再次启动。

之前日志曾经被完整粘贴，其中可能包含数据库密码。实际处理后应视为密码已经暴露，必须更换密码，并且笔记、GitHub、截图和日志中都不能保留真实值。

---

## 九、后端最终启动验证

重新打包并启动：

~~~
mvn clean package -DskipTests
java -jar ruoyi-admin/target/ruoyi-admin.jar
~~~

最终输出中确认：

~~~
Application Version: 3.9.2
The following 1 profile is active: "druid"
~~~

另一个 SSH 窗口验证：

~~~
ss -lntp | grep ':8080'
~~~

看到 Java 监听 8080。通过 HTTP 请求也能得到响应，Redis 单独验证返回 PONG。

本阶段可以确认：

- YAML 已经能够解析。
- 日志目录可写。
- MySQL 用户密码和 ry-vue 权限正确。
- 后端 JAR 能够启动。
- Java 正在监听 8080。
- HTTP 请求能够到达后端。

需要区分：

~~~
BUILD SUCCESS
~~~

只说明 Maven 生成了 JAR。

~~~
Application run completed + port 8080 + HTTP response
~~~

才说明应用运行阶段也通过了基本验证。

本阶段后端仍然是手工运行。Java 进程依赖当前 SSH 窗口，关闭窗口或重启后不会自动恢复。

---

## 十、阶段总结与下一步

本阶段后端已经可以手工启动，下一步是：

1. 获取与后端版本匹配的 Vue 前端。
2. 安装 Node.js 并构建 dist。
3. 使用 Nginx 提供前端并代理 API。
4. 放行 HTTP 80。
5. 使用 systemd 管理后端。
6. 重启服务器验证开机自启。

提交公开仓库时不要包含：

~~~
数据库真实密码
Redis 真实密码
SSH 私钥
Token 和密钥
应用日志
target/ 构建产物
上传文件
~~~
