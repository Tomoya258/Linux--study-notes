# Ubuntu Server 部署 RuoYi-Vue（3）：前端构建、Nginx 与前后端联调

- 日期：2026-10-07
- 环境：Windows、VMware Workstation、Ubuntu Server 26.04.1 LTS、SSH
- 服务器主机名：ubuntu-server-01
- 普通用户：admin01
- 服务器固定 IP：192.168.136.10/24
- 项目：RuoYi-Vue 3.9.2
- 后端路径：/home/admin01/projects/RuoYi-Vue
- 前端路径：/home/admin01/projects/ruoyi-ui/RuoYi-Vue3-master

---

## 一、本阶段完成的内容

1. 确认后端仓库和提交版本。
2. 确认后端源码不包含 Vue 前端。
3. 获取与后端匹配的 RuoYi-Vue3 前端源码。
4. 安装 Node.js 22 和 npm。
5. 安装依赖并成功生成前端 dist。
6. 安装并配置 Nginx。
7. 用 Nginx 提供前端静态页面并代理 /prod-api/ 到后端 8080。
8. 解决 Windows 代理导致的 502。
9. 解决 UFW 未放行 80/tcp 导致的浏览器超时。
10. 从 Windows 浏览器成功打开若依页面。

当前部署进度：

~~~
Ubuntu 基础配置       已完成
Git 获取源码          已完成
JDK 17               已完成
Maven 构建后端        已完成
MySQL 初始化          已完成
Redis                 已完成
后端配置与手工启动    已完成
Node.js / 前端构建    已完成
Nginx                 已完成
前后端联调            已完成
systemd 管理若依      尚未完成
~~~

---

## 二、确认前后端源码关系

后端执行 git remote -v、git describe --tags --always 和 git log -1 --oneline，实际结果：

~~~
origin https://github.com/yangzongzhuan/RuoYi-Vue.git
v3.9.2-32-g13db1fce
13db1fce 添加新群号：113071109
~~~

后端目录只有 Java/Maven 模块。搜索 package.json、锁文件等没有输出，说明这份源码不包含前端。

从 Windows 获取 RuoYi-Vue3-master.zip 后传到 Ubuntu：

~~~
/home/admin01/projects/ruoyi-ui/RuoYi-Vue3-master.zip
~~~

解压目录为 /home/admin01/projects/ruoyi-ui/RuoYi-Vue3-master，确认有 package.json、src、public 和 .env.production。

前端 package.json 显示 version 3.9.2，build:prod 为 vite build。生产环境配置 VITE_APP_BASE_API 为 /prod-api，表示前端 API 请求由 Nginx 转发到 Java 后端。

---

## 三、Node.js 安装与前端构建

初次执行 node -v 和 npm -v 时，系统提示 command not found。apt-cache policy 查询到 Node.js 22.22.1 和 npm 9.2.0，满足 Vite 6 构建要求。

第一次安装时出现 404 Not Found 和 Unable to fetch some archives。原因是本地 APT 索引和镜像中的包版本不一致。执行 apt update 后重新安装成功。

前端目录：

~~~
cd /home/admin01/projects/ruoyi-ui/RuoYi-Vue3-master
npm install
npm run build:prod
~~~

构建验收：

~~~
ls -la dist
test -f dist/index.html && echo index.html exists
~~~

实际生成 dist/index.html、dist/index.html.gz 和 dist/static/，其中 index.html 大小为 5422 bytes。文件归 admin01 所有，说明没有用 sudo 执行 npm 安装和构建。

---

## 四、Nginx 安装和配置

Nginx 状态为 active (running)，并且 enabled。初始使用 Ubuntu 默认站点，之后将前端文件复制到 /var/www/ruoyi，创建 ruoyi 站点并停用默认站点。

核心配置逻辑：

~~~
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name 192.168.136.10;
    root /var/www/ruoyi;
    index index.html;

    location /prod-api/ {
        proxy_pass http://127.0.0.1:8080/;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
~~~

proxy_pass 末尾的斜杠会把 /prod-api/captchaImage 转发为后端 /captchaImage。

执行 nginx -t 检查通过后 reload Nginx。curl 验证首页返回 200，Content-Length 为 5422，与 dist/index.html 一致，说明返回的是若依前端而不是 Ubuntu 默认页。

端口检查确认 Nginx 监听 80，Java 监听 8080。

---

## 五、接口联调

本机通过 Nginx 测试：

~~~
curl -sS -o /dev/null -w 'captchaImage: %{http_code}\n' http://127.0.0.1/prod-api/captchaImage
curl -sS -o /dev/null -w 'getInfo: %{http_code}\n' http://127.0.0.1/prod-api/getInfo
~~~

实际结果：

~~~
captchaImage: 200
getInfo: 200
~~~

Nginx access.log 也记录了这两个请求的 200。访问 /prod-api/ 根路径得到 404 不代表代理失败，因为后端没有定义这个根接口，应测试实际存在的接口。

---

## 六、Windows 外部访问排错

浏览器开发者工具曾显示 Request URL 为 http://192.168.136.10/，Status Code 为 502，Remote Address 为 127.0.0.1:10090。Remote Address 是 Windows 本机代理，不是 Ubuntu 的 192.168.136.10:80，因此 502 由本机代理返回。

绕过代理后浏览器从 502 变成超时。Ubuntu 本机 curl 正常，Nginx 也监听 0.0.0.0:80，最终确认是 UFW 只放行了 SSH。

放行 HTTP：

~~~
sudo ufw allow 80/tcp
sudo ufw reload
~~~

之后 Windows 浏览器成功访问 http://192.168.136.10/。

排错路径：

~~~
Windows 代理
    ↓
VMware NAT / 虚拟网络
    ↓
UFW
    ↓
Nginx
    ↓
Java 后端
~~~

本机 curl 成功不能替代 Windows 外部访问验证。

---

## 七、重要认识与下一步

前端构建不等于网页可访问，完整链路是 npm run build:prod、生成 dist、Nginx 提供静态文件、UFW 放行 80、Windows 浏览器访问。

nginx -t 只证明配置语法正确，还必须验证静态文件、Java 8080、proxy_pass 路径、UFW 和浏览器访问。

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

当前后端仍由 SSH 窗口中的 java -jar 进程运行。下一阶段使用 systemd 管理后端，实现服务启停、日志查看、开机启动和重启验证。

提交到 GitHub 时继续排除数据库密码、Redis 密码、SSH 私钥、Token、日志文件、target、node_modules 和上传文件。
