
---

# Linux Java Web 环境搭建学习记录

日期：2026年9月1日

## 一、学习目标

在 CentOS 7 虚拟机上完成 Java Web 运行环境的搭建，包括 JDK 21、Tomcat 9、Nginx 的安装与配置，并理解各组件的作用及相互关系。

---

## 二、环境信息

- 操作系统：CentOS 7
- 用户：root
- 软件统一安装目录：/export/server/

---

## 三、JDK 21 安装与环境变量配置

### 3.1 下载与解压

下载 Oracle JDK 21 压缩包，上传至 /export/server/ 目录，执行解压：

```
tar -xzvf jdk-21_linux-x64_bin.tar.gz
```

解压后得到目录：jdk-21.0.12.1

### 3.2 创建软链接

为方便版本切换和维护，创建软链接指向具体版本目录：

```
ln -s /export/server/jdk-21.0.12.1 /export/server/jdk
```

软链接的意义：
- 环境变量固定指向 /export/server/jdk，版本升级时只需修改软链接指向
- 避免在多个配置文件中逐一修改路径

### 3.3 配置环境变量

编辑 /etc/profile 文件，在末尾添加：

```
export JAVA_HOME=/export/server/jdk
export PATH=$JAVA_HOME/bin:$PATH
```

使配置生效：

```
source /etc/profile
```

### 3.4 遇到的问题

- 系统未安装 vim，使用 vi 代替，或用 yum install vim -y 安装
- 编辑 /etc/profile 时出现 .swp 交换文件残留，原因是在编辑过程中终端异常断开，执行 rm -f /etc/.profile.swp 删除后重新编辑
- 环境变量配置完成后，用 echo $JAVA_HOME 和 which java 验证

### 3.5 理解环境变量

- JAVA_HOME：告诉系统和其它软件（如 Tomcat）JDK 的安装位置
- PATH：让系统能够在任何目录下识别并执行 java 命令

---

## 四、Apache Tomcat 9 安装

### 4.1 下载与解压

下载 apache-tomcat-9.0.121.tar.gz，解压到 /export/server/：

```
tar -xzvf apache-tomcat-9.0.121.tar.gz -C /export/server/
```

### 4.2 创建 Tomcat 专用用户

为安全考虑，不推荐用 root 用户启动 Tomcat，创建专用用户：

```
useradd -M -s /bin/nologin tomcat
```

-M：不创建家目录
-s /bin/nologin：该用户不能登录系统

### 4.3 修改目录所有权

```
chown -R tomcat:tomcat /export/server/apache-tomcat-9.0.121/
```

-R 表示递归修改，将目录及其内部所有文件的所有权都改为 tomcat 用户和组。

### 4.4 启动 Tomcat

切换到 tomcat 用户启动：

```
su - tomcat -c "/export/server/tomcat/bin/startup.sh"
```

### 4.5 遇到的问题

- 执行 su -tomcat 时报错 "无效选项 -- t"，原因是 - 和 tomcat 之间缺少空格，正确写法为 su - tomcat
- 提示符中 $ 表示普通用户， # 表示 root 用户，两者权限级别不同

---

## 五、Nginx 安装

### 5.1 安装 yum-utils

```
yum install -y yum-utils
```

yum-utils 是一个工具包集合，包含了 yum-config-manager 等命令，用于管理 yum 仓库。

### 5.2 添加 Nginx 官方仓库

创建 /etc/yum.repos.d/nginx.repo 文件，内容如下：

```
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
```

### 5.3 安装 Nginx

```
yum install -y nginx
```

### 5.4 启动并设置开机自启

```
systemctl start nginx
systemctl enable nginx
```

### 5.5 遇到的问题

- 误以为 yum-utils 是一个可执行的命令，执行 yum-utils -version 报错
- 正确用法是使用其包含的工具，如 yum-config-manager
- 用 which yum-config-manager 即可验证安装是否成功

---

## 六、当前系统服务状态

| 服务 | 端口 | 状态 |
|------|------|------|
| JDK 21 | - | 已安装，环境变量已配置 |
| Tomcat 9 | 8080 | 已启动，监听 8080 端口 |
| Nginx | 80 | 已启动，监听 80 端口，已设置开机自启 |

验证命令：

```
ss -tlnp | grep nginx
ss -tlnp | grep 8080
```

---

## 七、架构理解

当前架构为 Nginx 在前端（80 端口）接收用户请求，Tomcat 在后端（8080 端口）运行 Java 应用，形成反向代理的基础结构。

用户访问流程：
浏览器 -> Nginx(80) -> Tomcat(8080)

---

## 八、配置文件备份建议

将关键配置文件留存至 GitHub 私有仓库，便于环境重建和版本追踪：

- /etc/yum.repos.d/nginx.repo
- /etc/profile（环境变量部分）
- Tomcat 配置文件（server.xml 等）
- 安装脚本（Shell）

注意：不要将数据库密码、私钥等敏感信息推送至公开仓库。

---

以后内容都偏生产环境 要多练多扩散思维