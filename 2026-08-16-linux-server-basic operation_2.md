# Linux 学习笔记：进程管理、日志分析与时间同步

> 学习日期：2026-08-16
> 系统环境：CentOS 7

---

## 一、htop：更直观的进程管理工具

### 1. 安装 htop 时遇到的问题

最开始执行：

```bash
yum install htop -y
```

出现：

```text
没有可用软件包 htop。
错误：无须任何处理
```

### 原因

CentOS 7 默认的软件源中可能没有 `htop`，需要额外启用 EPEL 源。

安装 EPEL：

```bash
yum install epel-release -y
```

然后再次安装：

```bash
yum install htop -y
```

### 2. 下载速度非常慢

安装 EPEL 后，下载仓库元数据时速度只有约：

```text
4.1 kB/s
ETA 00:24:40
```

查看后发现自动选择的镜像站是：

```text
ftp.iij.ad.jp
```

这说明问题不一定是虚拟机网络慢，也可能是软件源镜像服务器访问速度慢。

---

## 二、使用 htop 管理进程

运行：

```bash
htop
```

可以查看：

* CPU 使用率
* 内存使用率
* Swap
* 系统进程
* PID
* 进程所属用户

还可以直接选择进程并发送信号。

### 实验：使用 htop 结束 vim 进程

一个终端：

```bash
vim net.log
```

另一个终端：

```bash
htop
```

找到对应的 `vim` 进程并发送 `SIGTERM`。

原窗口显示：

```text
Vim: Caught deadly signal TERM
Vim: Finished.

已终止
```

流程：

```text
htop
  ↓
找到 vim 进程
  ↓
发送 SIGTERM
  ↓
vim 收到 TERM 信号
  ↓
vim 进程结束
```

常见信号：

```text
SIGTERM / 15 → 请求进程正常结束
SIGKILL / 9 → 强制结束进程
```

```bash
kill PID
kill -9 PID
```

> 注意：强制结束编辑器可能导致未保存的数据丢失。

---

## 三、/var/log：Linux 日志目录

进入：

```bash
cd /var/log
```

查看：

```bash
ls -l
```

常见日志：

```text
/var/log/messages → 系统综合日志
/var/log/secure   → SSH、登录认证日志
/var/log/cron     → 定时任务日志
/var/log/boot.log → 系统启动日志
/var/log/yum.log  → 软件包操作日志
```

---

## 四、日志轮转 logrotate

看到：

```text
messages
messages-20260726
messages-20260803
messages-20260812
```

说明系统进行了日志轮转：

```text
当前日志不断增长
        ↓
旧日志保存
        ↓
创建新的日志文件
```

作用是避免日志无限增大。

---

## 五、tail + grep 实时过滤日志

```bash
tail -f /var/log/messages | grep -i "fail"
```

含义：

```text
tail -f
→ 实时查看新增内容

|
→ 管道，把前一个命令输出交给后一个命令

grep
→ 搜索和过滤文本

-i
→ 忽略大小写
```

### 遇到的错误

错误命令：

```bash
tail -f /var/log | grep -i "fail"
```

原因：

```text
/var/log
```

是目录，不是文件。

正确：

```bash
tail -f /var/log/messages | grep -i "fail"
```

监控 SSH 登录失败更适合：

```bash
tail -f /var/log/secure | grep -i "fail"
```

---

## 六、生产环境日志管理

手动排障仍然经常使用：

```bash
tail
grep
less
awk
sed
journalctl
```

但大量服务器不会逐台 SSH 查看日志。

典型流程：

```text
服务器
  ↓
系统日志 / 应用日志
  ↓
日志采集 Agent
  ↓
集中日志平台
  ↓
存储 / 搜索 / 可视化
  ↓
监控规则
  ↓
自动告警
```

常见技术：

```text
Filebeat
Fluent Bit
Logstash

Elasticsearch
Loki

Kibana
Grafana
```

可以理解为：

```text
日志平台 → 发现问题
Linux 命令 → 深入现场排查问题
```

---

## 七、date 命令

查看当前时间：

```bash
date
```

格式化：

```bash
date "+%Y-%m-%d"
```

常见格式：

```text
%Y → 年
%m → 月
%d → 日

%H → 小时
%M → 分钟
%S → 秒
```

特别容易混淆：

```text
%m → 月份
%M → 分钟
```

### 计算明天的时间

```bash
date -d "+1 day" "+%Y%m%d %H:%M:%S"
```

### 遇到的错误

格式字符串前面漏掉 `+`，导致：

```text
date: 额外的操作数
```

正确格式：

```bash
date "+格式"
```

---

## 八、ntpd 与 ntpdate

### ntpd

持续运行的时间同步服务：

```text
ntpd
 ↓
后台持续运行
 ↓
定期同步时间
 ↓
自动校准
```

查看：

```bash
systemctl status ntpd
```

学到的状态：

```text
loaded
→ 服务已安装

enabled
→ 设置开机自启

active (running)
→ 当前正在运行

inactive (dead)
→ 当前没有运行

failed
→ 启动或运行失败
```

重点：

```text
enabled ≠ active
```

```text
enabled → 下次开机是否自动启动
active  → 现在是否正在运行
```

启动：

```bash
systemctl start ntpd
```

启动并设置开机自启：

```bash
systemctl enable --now ntpd
```

### ntpdate

一次性手动同步时间：

```bash
ntpdate ntp.aliyun.com
```

区别：

```text
ntpdate → 手动同步一次
ntpd    → 长期自动同步
```

---

## 九、修改 Linux 时区

学习命令：

```bash
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
```

含义：

```text
/usr/share/zoneinfo/Asia/Shanghai
        ↓
上海时区文件
        ↓
软链接到
        ↓
/etc/localtime
```

参数：

```text
-s → 创建软链接
-f → 强制覆盖
```

查看：

```bash
date
```

### 时区和时间同步的区别

```text
时区错误
→ 修改 /etc/localtime

系统时间本身错误
→ 使用 ntpdate 或 ntpd
```

---

## 十、今天遇到的问题总结

| 问题                        | 原因             | 解决方法                    |
| ------------------------- | -------------- | ----------------------- |
| `yum install htop` 找不到软件包 | 默认源没有对应软件包     | 安装 EPEL                 |
| 下载速度只有几 KB/s              | 自动选择的镜像服务器慢    | 更换镜像或等待                 |
| `tail -f /var/log` 报错     | `/var/log` 是目录 | 指定具体日志文件                |
| `date` 出现额外操作数            | 格式字符串前缺少 `+`   | 使用 `date "+格式"`         |
| `%m` 和 `%M` 混淆            | 大小写含义不同        | `%m` 是月，`%M` 是分钟        |
| `ntpd inactive (dead)`    | 服务当前未运行        | `systemctl start ntpd`  |
| `enabled` 但没运行            | 开机自启和运行状态不同    | 区分 `enabled` 与 `active` |
| vim 被 htop 杀掉             | 收到 SIGTERM     | 学习进程信号                  |

---

## 十一、今日知识体系

```text
Linux 进程管理
│
├── top
├── htop
├── PID
├── SIGTERM
└── SIGKILL

Linux 日志
│
├── /var/log
├── messages
├── secure
├── cron
├── yum.log
├── logrotate
├── tail -f
└── grep + 管道

Linux 时间管理
│
├── date
├── 时间格式化
├── 时间计算
├── %m 与 %M
├── 时区
│   └── /etc/localtime
│
└── 时间同步
    ├── ntpdate
    └── ntpd
```

---

## 十二、下一步学习建议

```text
进程管理
├── ps
├── pstree
├── kill
└── nice / renice

日志管理
├── journalctl
├── rsyslog
└── logrotate

服务管理
├── systemctl
└── systemd

自动化
├── Shell
├── Ansible
└── Python

DevOps
├── Git
├── CI/CD
├── Docker
└── Kubernetes

监控
├── Prometheus
├── Grafana
├── ELK
└── Loki
```

> **今日总结：**
>
> 今天学习的不只是几个 Linux 命令，而是开始把几个系统概念串起来：
>
> **进程如何运行和结束 → 日志如何记录问题 → 如何实时过滤日志 → 如何管理系统时间和时区 → 如何通过服务实现长期自动化。**
