# Ubuntu Server 部署 RuoYi-Vue（3）：前端构建、Nginx、UFW 与外部联调

- 日期：2026-10-07
- 环境：Windows、VMware Workstation、Ubuntu Server 26.04.1 LTS、SSH
- 服务器主机名：ubuntu-server-01
- 普通用户：admin01
- 服务器固定 IP：192.168.136.10/24
- 项目：RuoYi-Vue 3.9.2
- 后端路径：/home/admin01/projects/RuoYi-Vue
- 前端路径：/home/admin01/projects/ruoyi-ui/RuoYi-Vue3-master

---

## 一、本阶段目标和完成结果

本阶段把已经能够运行的 Java 后端接到 Vue 前端和 Nginx 上，并从 Windows 浏览器进行外部访问验证。

完成内容：

1. 确认后端仓库、提交版本和前后端分离关系。
2. 发现后端源码中没有 package.json，确认前端需要单独获取。
3. 获取并解压版本为 3.9.2 的 RuoYi-Vue3 前端。
4. 安装 Node.js 22 和 npm。
5. 处理 APT 下载 404。
6. 执行 npm install 和 npm run build:prod。
7. 部署 dist 到 /var/www/ruoyi。
8. 配置 Nginx 提供静态页面并代理 /prod-api/。
9. 解决 Windows 本机代理导致的 502。
10. 解决 UFW 未放行 80 导致的浏览器超时。
11. 从 Windows 浏览器打开若依页面。

当前部署状态：

~~~
Ubuntu 基础配置        已完成
Git 获取源码           已完成
JDK 17                已完成
Maven 构建后端         已完成
MySQL 初始化           已完成
Redis                  已完成
后端配置与手工启动     已完成
Node.js / npm          已完成
Vue 前端生产构建       已完成
Nginx                  已完成
UFW HTTP 80            已完成
前后端基本联调         已完成
systemd                尚未完成
~~~

注意：systemd 尚未配置，所以后端仍依赖 SSH 中的 java -jar 进程。

---

## 二、确认后端版本和前端来源

### 2.1 后端 Git 信息

在后端仓库目录：

~~~
cd /home/admin01/projects/RuoYi-Vue
git remote -v
git describe --tags --always
git log -1 --oneline
~~~

实际结果：

~~~
origin https://github.com/yangzongzhuan/RuoYi-Vue.git
v3.9.2-32-g13db1fce
13db1fce 添加新群号：113071109
~~~

这表示当前源码基于 v3.9.2，又比该标签多 32 次提交。不能只根据项目名称判断前后端版本，应该查看仓库和 package.json。

### 2.2 后端目录为什么找不到前端

在后端目录搜索：

~~~
find . -type f ( -name package.json -o -name package-lock.json -o -name yarn.lock -o -name pnpm-lock.yaml ) -print
~~~

没有输出。

目录列表主要是：

~~~
ruoyi-admin/
ruoyi-common/
ruoyi-framework/
ruoyi-generator/
ruoyi-quartz/
ruoyi-system/
sql/
~~~

这些是 Maven/Java 模块。没有 package.json、前端 src、public 或 ruoyi-ui，因此不能在这个目录里执行 npm 构建。

这次搜索没有输出并不代表命令失败；它表示搜索条件没有匹配结果。先用 pwd 确认目录，再扩大搜索范围，是比直接猜前端目录更可靠的排错方法。

### 2.3 GitHub 连接失败

尝试从 Ubuntu 检查 RuoYi-Vue3 仓库：

~~~
git ls-remote --heads https://github.com/yangzongzhuan/RuoYi-Vue3.git
~~~

出现：

~~~
fatal: unable to access ... Recv failure: Connection reset by peer
~~~

这发生在连接远程仓库阶段，不能据此判断仓库不存在。因为后端 Git 仓库之前能够访问，当前更可能是线路、代理或 GitHub 连接被重置。

为了继续学习和部署，改为在 Windows 获取 ZIP，再传到 Ubuntu：

~~~
/home/admin01/projects/ruoyi-ui/RuoYi-Vue3-master.zip
~~~

### 2.4 解压和路径误解

查看 ZIP 内容：

~~~
unzip -l RuoYi-Vue3-master.zip | sed -n '1,30p'
~~~

看到最外层目录是 RuoYi-Vue3-master，并且包含 package.json、src、public 和 .env.production。

曾经直接输入：

~~~
sed -n '1,160p' 路径/package.json
~~~

得到：

~~~
sed: can't read 路径/package.json: No such file or directory
~~~

这里的“路径”是指导文字中的占位符，不是应原样输入的目录名。正确做法是先解压、进入真实目录，再执行：

~~~
cd /home/admin01/projects/ruoyi-ui/RuoYi-Vue3-master
sed -n '1,160p' package.json
~~~

package.json 结果：

~~~
version: 3.9.2
build:prod: vite build
~~~

生产配置：

~~~
VITE_APP_BASE_API = /prod-api
~~~

因此前端请求会使用 /prod-api 前缀，Nginx 需要把它转发到 Java 后端。

---

## 三、Node.js 和前端生产构建

### 3.1 Node.js 尚未安装

第一次执行：

~~~
node -v
npm -v
~~~

结果：

~~~
Command 'node' not found
Command 'npm' not found
~~~

这说明服务器没有前端构建工具，不能直接执行 npm install。

### 3.2 查询软件源候选版本

~~~
apt-cache policy nodejs npm
~~~

结果：

~~~
nodejs Candidate: 22.22.1+dfsg+~cs22.19.15-1ubuntu1
npm Candidate: 9.2.0~ds3-1
~~~

Node.js 22 满足 Vite 6 的运行要求，因此使用 Ubuntu 软件源安装。

### 3.3 APT 404 排错

安装过程中下载约 163 MB，但部分软件包出现：

~~~
404 Not Found
Unable to fetch some archives
~~~

涉及 libheif、libssl-dev、libxpm4 等包。

这类错误不是 npm 项目错误，而是本地 APT 包索引记录的版本与镜像当前文件不一致。处理顺序：

~~~
sudo apt update
sudo apt install nodejs npm
~~~

更新软件包索引后重新安装成功。

### 3.4 依赖安装和生产构建

前端目录：

~~~
cd /home/admin01/projects/ruoyi-ui/RuoYi-Vue3-master
~~~

安装依赖：

~~~
npm install
~~~

构建生产文件：

~~~
npm run build:prod
~~~

这里没有使用 sudo，因为 npm 依赖和构建产物应由普通用户管理，避免 node_modules 或 dist 归 root 所有。

验证：

~~~
ls -la dist
test -f dist/index.html && echo "index.html exists"
~~~

实际结果：

~~~
dist/index.html       5422 bytes
dist/index.html.gz    1400 bytes
dist/static/          已生成
index.html exists
~~~

这证明前端构建已经成功。但 dist 只是静态文件，还需要 Nginx 才能从 HTTP 提供给浏览器。

---

## 四、Nginx 默认站点和部署位置

### 4.1 初始状态

检查 Nginx：

~~~
systemctl status nginx
~~~

结果：

~~~
Active: active (running)
Loaded: enabled
~~~

Nginx 已安装并开机启动，但最初启用的是 Ubuntu 默认站点：

~~~
/etc/nginx/sites-enabled/default
~~~

默认站点返回 Ubuntu 欢迎页，因此即使 Nginx 正常，也不代表若依前端已经部署。

### 4.2 为什么把 dist 复制到 /var/www/ruoyi

Nginx 主配置中的运行用户是 www-data。前端源码和 dist 位于 /home/admin01 下，如果直接让 Nginx 读取家目录，还要逐级处理父目录的进入权限。

最终把构建产物部署到：

~~~
/var/www/ruoyi
~~~

这样更适合作为 Web 静态文件目录。复制完成后将目录和文件设置为 root 可读，目录 755、文件 644。

本次使用脚本完成：

1. 检查 dist/index.html 是否存在。
2. 创建 /var/www/ruoyi。
3. 复制 dist 内容。
4. 设置静态文件权限。
5. 写入 /etc/nginx/sites-available/ruoyi。
6. 建立 /etc/nginx/sites-enabled/ruoyi 链接。
7. 删除 default 站点链接。
8. 执行 nginx -t。
9. reload Nginx。
10. 使用 curl 测试首页和 API。

### 4.3 Nginx 配置逻辑

核心站点配置：

~~~
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name 192.168.136.10;

    root /var/www/ruoyi;
    index index.html;
    client_max_body_size 50m;

    location /prod-api/ {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
~~~

各部分作用：

- root：静态文件根目录。
- location /：处理页面和 Vue 单页路由。
- try_files：文件存在时直接返回，不存在时回退到 index.html。
- location /prod-api/：匹配前端发出的 API 请求。
- proxy_pass：将请求转发到 Java 8080。
- client_max_body_size：允许较大的上传请求。

proxy_pass 最后有斜杠时：

~~~
浏览器请求 /prod-api/captchaImage
后端收到 /captchaImage
~~~

如果路径尾部写法不同，后端可能收到多余的 /prod-api 前缀，导致 404。因此 API 路径必须结合前端环境变量和后端实际接口一起验证。

---

## 五、Nginx 配置检查和静态页面验证

检查启用站点：

~~~
ls -l /etc/nginx/sites-enabled/
~~~

结果只有：

~~~
ruoyi -> /etc/nginx/sites-available/ruoyi
~~~

说明 default 已停用。

检查实际加载的配置：

~~~
sudo nginx -T 2>/dev/null | grep -E 'server_name|root |proxy_pass|listen '
~~~

确认：

~~~
server_name 192.168.136.10
root /var/www/ruoyi
proxy_pass http://127.0.0.1:8080/
~~~

检查端口：

~~~
ss -lntp | grep -E ':80|:8080'
~~~

结果确认：

~~~
0.0.0.0:80   Nginx
*:8080       Java
~~~

首次脚本测试首页时返回 Content-Length 615，说明返回的仍像 Ubuntu 默认页。后来确认 Nginx 已加载新站点，再测试：

~~~
curl -I -H 'Host: 192.168.136.10' http://127.0.0.1/
~~~

返回：

~~~
HTTP/1.1 200 OK
Content-Length: 5422
~~~

5422 与前端 dist/index.html 大小一致，因此确认已经返回若依页面，而不是默认欢迎页。

这个过程说明：

~~~
nginx -t 成功 ≠ 返回了正确页面
~~~

还需要检查实际加载的 root 和 HTTP 响应内容。

---

## 六、本机接口联调

先确认 Java 后端仍在运行：

~~~
ss -lntp | grep ':8080'
~~~

再通过 Nginx 测试真实接口：

~~~
curl -sS -o /dev/null -w 'captchaImage: %{http_code}
' http://127.0.0.1/prod-api/captchaImage

curl -sS -o /dev/null -w 'getInfo: %{http_code}
' http://127.0.0.1/prod-api/getInfo
~~~

实际结果：

~~~
captchaImage: 200
getInfo: 200
~~~

Nginx access.log 也记录了两个请求的 200。

此前请求 /prod-api/ 根路径返回 404。这个结果不能单独证明反向代理失败，因为后端可能没有定义根路径接口。更可靠的做法是测试已知存在的 captchaImage 等真实接口。

当前链路已经验证：

~~~
浏览器 API 前缀 /prod-api/
       ↓
Nginx location /prod-api/
       ↓
Java 后端 /captchaImage 或 /getInfo
       ↓
HTTP 响应
~~~

---

## 七、Windows 浏览器外部访问排错

### 7.1 502 其实来自 Windows 代理

浏览器第一次访问出现 502。开发者工具中看到：

~~~
Request URL: http://192.168.136.10/
Status Code: 502 Bad Gateway
Remote Address: 127.0.0.1:10090
Proxy-Connection: keep-alive
~~~

关键证据是 Remote Address 为 127.0.0.1:10090。这是 Windows 本机代理端口，而不是 Ubuntu 的 192.168.136.10:80。

因此需要区分：

~~~
浏览器 → Windows 本机代理 127.0.0.1:10090 → Ubuntu
~~~

502 是代理无法访问虚拟机时返回的，不是 Ubuntu Nginx 日志中的错误。此时不应先修改 Nginx 或 Java。

处理方向：

- 暂时关闭 Windows 代理。
- 将 192.168.136.10 加入代理绕过列表。
- 将 192.168.136.* 加入本地直连规则。
- 用 Windows PowerShell 直连测试：

~~~
curl.exe --noproxy "*" -I http://192.168.136.10/
~~~

### 7.2 绕过代理后变成超时

绕过代理后，错误从 502 变成超时。

此时 Ubuntu 本机测试是成功的：

- Nginx 监听 0.0.0.0:80。
- Java 监听 8080。
- 本机首页返回 200。
- 本机 API 返回 200。

但是 Windows 外部访问仍然超时，说明问题位于外部路径。检查 UFW：

~~~
sudo ufw status
~~~

原规则只允许 OpenSSH，没有 HTTP 80。Nginx 监听端口不代表防火墙允许外部连接。

放行并重新加载：

~~~
sudo ufw allow 80/tcp
sudo ufw reload
~~~

之后 Windows 浏览器成功加载：

~~~
http://192.168.136.10/
~~~

也可以在 Windows 测试端口：

~~~
Test-NetConnection 192.168.136.10 -Port 80
~~~

预期 TcpTestSucceeded 为 True。

这次完整排错路径：

~~~
浏览器显示 502
    ↓
查看 Remote Address
    ↓
发现 Windows 代理
    ↓
绕过代理
    ↓
错误变成超时
    ↓
确认服务器监听 80
    ↓
检查 UFW
    ↓
放行 80/tcp
    ↓
浏览器访问成功
~~~

---

## 八、为什么本机 curl 不能替代浏览器测试

在 Ubuntu 中执行：

~~~
curl http://127.0.0.1/
~~~

只验证本机到 Nginx 的路径，通常不会经过：

- Windows 代理。
- VMware 虚拟网络。
- Ubuntu 外部网卡。
- UFW 对外规则。

Windows 浏览器访问则经过：

~~~
Windows 浏览器
    ↓
Windows 代理设置
    ↓
VMware NAT / VMnet8
    ↓
Ubuntu ens33
    ↓
UFW
    ↓
Nginx 80
    ↓
Java 8080
~~~

因此部署验证至少分三层：

1. 本机服务验证：进程、监听、curl。
2. Nginx 代理验证：通过 /prod-api/ 请求真实接口。
3. 外部访问验证：Windows 浏览器和防火墙。

---

## 九、阶段总结和下一步

截至本阶段结束：

~~~
Redis 服务                    已完成
MySQL 数据库与应用账号        已完成
若依后端配置                  已完成
后端 JAR 构建与手工启动        已完成
Node.js 和 npm                已完成
Vue 前端生产构建              已完成
Nginx 静态站点                 已完成
Nginx API 反向代理             已完成
UFW HTTP 80                   已完成
Windows 浏览器访问             已完成
systemd 管理后端               尚未完成
~~~

当前后端仍由 SSH 窗口中的 java -jar 进程运行。关闭 SSH 窗口或重启服务器后，Java 进程不会自动恢复。

下一阶段使用 systemd：

1. 创建若依 service 文件。
2. 指定运行用户 admin01。
3. 指定 JAR 绝对路径和工作目录。
4. 用 systemctl 启动、停止和重启。
5. 用 systemctl status 验收。
6. 用 journalctl 查看日志。
7. 停止 SSH 中手工启动的 Java。
8. 重启服务器验证开机自启。

提交 GitHub 时继续排除数据库密码、Redis 密码、SSH 私钥、Token、日志文件、target、node_modules 和上传文件。
