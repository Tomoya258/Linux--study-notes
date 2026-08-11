

---

# 一、Linux 查看 IP 地址

## 1. 使用 ip 命令

查看网络信息：

```bash
ip a
````

示例：

```
ens33:
    inet 192.168.136.133/24
```

说明：

* 网卡：ens33
* IP：192.168.136.133

常用：

```bash
ip addr
ip -4 addr
hostname -I
```

---

# 二、WindTerm SSH 连接 Linux

## SSH 原理

SSH：

```
客户端 ssh
        |
        |
        ↓
服务器 sshd
```

客户端：

```bash
ssh root@IP地址
```

服务器：

```bash
systemctl status sshd
```

---

## WindTerm 配置

参数：

```
协议：
SSH

主机：
192.168.136.xxx

端口：
22

用户：
root
```

---

# 三、虚拟机 IP 变化问题

## 遇到问题

之前 WindTerm 可以连接：

```
192.168.136.128
```

重启虚拟机后：

```
192.168.136.133
```

导致：

```
ssh root@192.168.136.128
```

无法连接。

## 原因

虚拟机默认使用 DHCP：

```
Linux
 |
 |
DHCP
 |
 |
VMware 分配 IP
```

每次启动可能获得不同 IP。

## 解决方案

### 方法1：设置静态 IP

服务器推荐。

### 方法2：VMware DHCP 地址绑定

根据 MAC 地址固定 IP。

查看 MAC：

```bash
ip a
```

例如：

```
link/ether 00:0c:29:f3:b3:35
```

---

# 四、yum 安装软件失败问题

## 问题

执行：

```bash
yum install wget -y
```

报错：

```
Could not resolve host: mirrorlist.centos.org
```

## 原因

CentOS 7 已经停止维护（EOL）

官方 mirrorlist 源失效。

---

# 五、CentOS 7 更换阿里云 Vault 源

## 错误操作

下载 repo：

```bash
curl -o CentOS-Base.repo xxx
```

结果：

```
<!DOCTYPE html>
<html>
```

原因：

下载的是网页，不是 repo 文件。

检查：

```bash
head /etc/yum.repos.d/CentOS-Base.repo
```

---

## 正确解决

创建：

```
/etc/yum.repos.d/CentOS-Base.repo
```

内容：

```ini
[base]
name=CentOS-7-Base
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/os/x86_64/
enabled=1
gpgcheck=0

[updates]
name=CentOS-7-Updates
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/updates/x86_64/
enabled=1
gpgcheck=0

[extras]
name=CentOS-7-Extras
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/extras/x86_64/
enabled=1
gpgcheck=0
```

清理缓存：

```bash
yum clean all
```

生成缓存：

```bash
yum makecache
```

测试：

```bash
yum install wget -y
```

结果：

```
Installed:
wget.x86_64
```

说明 yum 修复成功。

---

# 六、rpm 软件包管理

查看所有已安装 rpm：

```bash
rpm -qa
```

查询：

```bash
rpm -qa | grep wget
```

例如：

```
wget-1.14-18.el7_6.1.x86_64
```

关系：

```
yum
 |
 | 下载、解决依赖
 ↓
rpm
 |
 | 安装软件包
 ↓
系统文件
```

---

# 七、systemd 服务管理

Linux 使用 systemd 管理后台服务。

核心命令：

## 查看状态

```bash
systemctl status 服务名
```

例如：

```bash
systemctl status sshd
```

---

## 启动服务

```bash
systemctl start sshd
```

立即启动。

---

## 停止服务

```bash
systemctl stop sshd
```

例如：

```bash
systemctl stop sshd
```

停止 SSH 服务。

注意：

已经连接的 SSH 不会立即断开。

因为：

```
sshd
 |
 +-- bash
```

停止 sshd 只影响新的连接。

---

## 重启服务

```bash
systemctl restart 服务名
```

---

## 重新加载配置

```bash
systemctl reload 服务名
```

区别：

restart：

```
停止
 ↓
启动
```

reload：

```
重新读取配置
继续运行
```

---

## 设置开机启动

```bash
systemctl enable ntpd
```

作用：

开机自动启动。

不会立即启动。

立即启动：

```bash
systemctl start ntpd
```

或者：

```bash
systemctl enable --now ntpd
```

---

# 八、daemon（守护进程）

很多 Linux 服务后面有 d：

例如：

```
sshd
httpd
crond
ntpd
```

d：

```
daemon
```

意思：

后台长期运行的服务。

例如：

SSH：

```
ssh
 |
客户端

sshd
 |
服务器后台服务
```

---

# 九、Linux 服务管理流程

## 新安装软件

例如 nginx：

```bash
yum install nginx
```

流程：

```
安装
 ↓
status 查看
 ↓
start 启动
 ↓
enable 开机启动
```

命令：

```bash
systemctl status nginx

systemctl start nginx

systemctl enable nginx
```

---

# 十、Linux 目录结构复习

根目录：

```
/
├── etc
├── usr
├── var
├── home
├── root
├── proc
├── dev
└── tmp
```

## /etc

配置文件：

```
/etc/ssh/sshd_config
```

## /var

变化数据：

```
/var/log
```

日志。

## /home

普通用户目录。

## /root

root 用户目录。

## /usr

系统程序：

```
/usr/bin/wget
```

## /proc

虚拟文件系统：

查看 CPU：

```bash
cat /proc/cpuinfo
```

查看内存：

```bash
cat /proc/meminfo
```

---

# 十一、服务器硬件基础

## 普通服务器

通常：

```
CPU
内存
硬盘
网络
```

没有独立显卡。

---

## 为什么服务器 CPU 通常没有核显？

原因：

* 不需要显示输出
* 节省功耗
* 主板有 BMC 管理芯片

---

## BMC

服务器远程管理：

例如：

* IPMI
* iDRAC
* iLO

作用：

* 远程开机
* BIOS 管理
* 安装系统

---

# 十二、今天掌握的核心命令

查看网络：

```bash
ip a
```

SSH：

```bash
ssh 用户@IP
```

软件：

```bash
yum install
yum search
rpm -qa
```

服务：

```bash
systemctl start
systemctl stop
systemctl status
systemctl restart
systemctl reload
systemctl enable
systemctl disable
```

---

