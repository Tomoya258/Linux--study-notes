# Linux 学习笔记：Elasticsearch 安装、配置与排错

日期：2026-09-15  
环境：Windows + VMware + CentOS 7，通过 WindTerm 连接虚拟机。  
说明：本文根据今天的学习对话整理。示例 IP 和版本号需要替换为实际值；未从输出确认的信息不作为已完成事项。

## 1. 今天完成了什么

- 学习 Elasticsearch 的作用，以及它与 MySQL 的区别。
- 学习 RPM 签名公钥、YUM 仓库配置的用途。
- 安装并启动 Elasticsearch，修改集群名称与网络监听配置。
- 练习 Vim 修改配置文件。
- 排查 YAML 缩进错误、配置被注释、服务名拼写错误。
- 学习通过 systemd、日志、监听端口和防火墙逐层排查服务。
- 理解 VMware NAT 与局域网访问的关系。
- 讨论 Ubuntu 环境复现和后续项目部署。

最后提供的监听结果为：

```text
LISTEN 0 128 [::]:9200 [::]:* users:(("java",pid=20168,fd=297))
```

说明服务已监听 IPv6 通配地址的 9200 端口；Linux 上通常也可通过该双栈监听接收 IPv4 连接，但应以实际访问测试为准。该输出本身不能证明其他设备已经能够访问。

## 2. Elasticsearch 用来做什么

Elasticsearch 是搜索与分析引擎，常见用途包括全文搜索、条件筛选、相关度排序、聚合统计和日志检索。

| MySQL | Elasticsearch |
|---|---|
| 关系型数据库 | 搜索与分析引擎 |
| 擅长事务与业务数据管理 | 擅长全文搜索与聚合分析 |
| 常保存权威业务数据 | 常保存供搜索使用的数据副本或日志 |
| 表、行、列 | 索引、文档、字段 |

例如：商品信息保存在 MySQL，应用再把需要搜索的数据同步到 Elasticsearch。用户搜索商品时查询 Elasticsearch，下单等事务仍由 MySQL 承担。

搜索快的重要原因之一是倒排索引：提前记录“某个词出现在哪些文档”，搜索时利用索引定位，而不是每次扫描全部正文。

运维中可用日志采集工具把 Nginx、Java 应用等日志送入 Elasticsearch，再用 Kibana 检索与展示。安装 Elasticsearch 本身不会自动采集这些日志。

## 3. 签名公钥与 YUM 仓库

### 3.1 导入签名公钥

```bash
rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
```

- `rpm`：管理 RPM 软件包。
- `--import`：将公钥导入 RPM 的密钥存储。
- 公钥用于验证 RPM 包的数字签名；它不是密码，不需要保密。

发布者用私钥签名，安装端用可信公钥验证。验证成功说明软件包与签名匹配；可信来源和公钥指纹核对是建立信任的基础，不能只要导入一把密钥就认为软件一定可信。

查看已导入的公钥：

```bash
rpm -qa | grep gpg-pubkey
rpm -qi gpg-pubkey-实际编号
```

### 3.2 创建仓库配置

```bash
vim /etc/yum.repos.d/elasticsearch.repo
```

7.x 仓库的核心配置示例：

```ini
[elasticsearch]
name=Elasticsearch repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
```

| 配置 | 含义 |
|---|---|
| `[elasticsearch]` | 仓库标识 |
| `name` | 仓库说明 |
| `baseurl` | 软件包及仓库元数据地址 |
| `gpgcheck=1` | 检查软件包签名 |
| `gpgkey` | 获取公钥的地址 |
| `enabled=1` | 默认启用仓库 |

有些教程还写 `autorefresh=1` 和 `type=rpm-md`；这两项不是 CentOS 7 YUM 配置该仓库的必要项。

检查仓库、列出版本并安装：

```bash
yum repolist enabled
yum --disablerepo='*' --enablerepo=elasticsearch makecache
yum --showduplicates list elasticsearch
yum install elasticsearch
```

`makecache` 下载仓库元数据，并不是安装 Elasticsearch。`--showduplicates` 可查看仓库提供的多个版本。正式复现时应记录、选择具体版本；不要把 `7.17.x` 这种占位符原样当版本输入。

补充：CentOS 7 和 Elasticsearch 7.17 都已结束支持。旧环境可用于隔离练习，不能据此假定任意 7.17 小版本都兼容 CentOS 7；实际还受捆绑 JDK 等因素影响。新环境应根据项目要求和支持矩阵选版本。

## 4. 问题一：elasticsearch 命令未找到

现象：

```text
elasticsearch --version
-bash: elasticsearch: 未找到命令
```

原因：Shell 会在 `PATH` 指定的目录中查找命令。RPM 安装的 Elasticsearch 可执行文件通常不在这些目录里，不能仅凭这条报错判断未安装。

检查方法：

```bash
rpm -q elasticsearch
ls -l /usr/share/elasticsearch/bin/elasticsearch
/usr/share/elasticsearch/bin/elasticsearch --version
echo "$PATH"
```

- `rpm -q elasticsearch`：查询是否安装及软件包版本。
- `ls -l`：确认文件是否存在及其权限。
- 完整路径：无需通过 `PATH` 查找即可执行。

长期运行服务使用 systemd 管理，不要以 root 手动启动 Elasticsearch 主进程。

## 5. systemd 服务管理

| 命令 | 用途 |
|---|---|
| `systemctl start elasticsearch` | 立即启动 |
| `systemctl stop elasticsearch` | 停止服务 |
| `systemctl restart elasticsearch` | 重启；未运行时也会尝试启动 |
| `systemctl status elasticsearch -l --no-pager` | 查看状态和少量最近日志 |
| `systemctl enable elasticsearch` | 设置开机自启，不会立即启动 |
| `systemctl enable --now elasticsearch` | 设置自启并立即启动 |
| `systemctl is-enabled elasticsearch` | 检查自启设置 |

状态中重点关注：

```text
Active: active (running)   # 正在运行
Active: failed            # 启动或运行失败
Main PID: ... (java)       # 服务主进程
```

`-l` 显示完整长行；`--no-pager` 直接输出，不进入分页查看器。

修改 `elasticsearch.yml` 后需要重启服务。只有修改 systemd 单元文件等服务定义时，才通常需要额外执行 `systemctl daemon-reload`。

### 服务名拼错

错误命令：

```bash
systemctl enable elaticsearch
```

报错：

```text
Failed to execute operation: No such file or directory
```

原因是 `elaticsearch` 少了一个 `s`，正确名称为 `elasticsearch`。今天对话中提供了修正命令，但未提供 `is-enabled` 的最终输出，自启状态应再确认。

## 6. Vim 修改配置

Vim 是文本编辑器。终端中的鼠标指针移动通常不会移动编辑光标，先用键盘操作更可靠。

```bash
vim /etc/elasticsearch/elasticsearch.yml
```

| 按键 | 用途 |
|---|---|
| `Esc` | 回到普通模式 |
| 方向键或 `h j k l` | 移动光标；分别为左、下、上、右 |
| `i` | 在光标前进入插入模式 |
| `/cluster.name` 后回车 | 搜索配置项 |
| `n` | 查找下一个匹配 |
| `cc` | 替换当前整行并进入插入模式 |
| `o` | 在下面新建一行并进入插入模式 |
| `0` | 移到当前行第一列 |
| `x` | 删除光标所在字符 |
| `u` | 撤销上一次修改 |
| `:wq` 后回车 | 保存退出 |
| `:q!` 后回车 | 放弃尚未保存的修改并退出 |

修改集群名称：搜索 `cluster.name`，回到普通模式后按 `cc`，输入：

```yaml
cluster.name: my-cluster
```

确认顶格，再按 `Esc`、输入 `:wq` 保存。今天日志中的实际名称是 `my-cluster`；`mycluster` 也可以，名称由自己确定。

若已保存但还在同一次 Vim 会话中，可用 `u` 撤销后再次保存。已经退出后通常不能依赖普通撤销，除非事先配置了持久化撤销；此时应使用备份或手动修正。`:q!` 不能撤回已经写入磁盘的修改。

修改前保存一份不易覆盖的备份：

```bash
cp -p /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak-$(date +%Y%m%d-%H%M%S)
```

比较时用实际备份文件名：

```bash
diff -u /实际备份路径 /etc/elasticsearch/elasticsearch.yml
```

备份要在修改前做。配置已损坏后再备份，保存的是故障现场，不是可直接恢复的正常版本。

## 7. 问题二：YAML 缩进导致服务启动失败

表面报错：

```text
Job for elasticsearch.service failed because the control process exited with error code.
```

这只是启动失败的通知，不能单凭它判断原因。继续查看：

```bash
systemctl status elasticsearch -l --no-pager
journalctl -u elasticsearch -n 80 --no-pager
```

当天日志的关键部分：

```text
expected <block end>, but found '<block mapping start>'
in 'reader', line 55, column 2:
 network.host: 0.0.0.0
 ^
```

原因：`network.host` 作为顶层配置，前面多了空格，与其他顶层配置不对齐，导致 YAML 解析失败。

正确写法：

```yaml
cluster.name: my-cluster
network.host: 0.0.0.0
```

两项可以位于不同位置，不必相邻，但都应顶格。冒号后留空格，缩进不要使用 Tab。

可跳到指定行修改：

```bash
vim +55 /etc/elasticsearch/elasticsearch.yml
```

按 `Esc`、`0` 到第一列，确认是多余空格再按 `x` 删除。保存后重启并检查状态。

日志同时提到第 16 行，是因为它指向正在解析的配置块起点，不代表 `cluster.name: my-cluster` 这行一定错误。

纠正一个易误解的例子：`cluster.name: mycluster#` 中紧贴文字的 `#` 可以属于字符串值，不一定造成 YAML 语法错误；但名称会包含这个字符。不能只看到 `#` 就判断报错。

## 8. journalctl 如何使用

```bash
journalctl -u elasticsearch -n 80 --no-pager
```

| 参数 | 含义 |
|---|---|
| `journalctl` | 查询 systemd-journald 收集的日志 |
| `-u elasticsearch` | 筛选该服务单元的日志 |
| `-n 80` | 最近 80 条日志 |
| `--no-pager` | 直接输出 |

其他常用方式：

```bash
journalctl -u elasticsearch -f
journalctl -u elasticsearch -b
journalctl -u elasticsearch --since today
journalctl -u elasticsearch --since "10 minutes ago"
```

- `-f`：持续跟踪新增日志，按 `Ctrl+C` 退出。
- `-b`：只看本次系统启动后的日志。
- `--since`：限制起始时间。

`journalctl -p err` 按日志优先级筛选，不是搜索文本中的 `ERROR`；部分应用报错可能没有对应优先级，排查时不要只依赖这个筛选。

Elasticsearch 的应用日志还可能主要写入 `/var/log/elasticsearch/`，journal 不一定包含全部报错。若系统日志没有原因，可先查看该目录中的实际日志文件，再读取末尾内容。

## 9. 为什么监听进程是 java

Elasticsearch 运行在 JVM 中，所以 `ss` 显示的进程名通常是 `java`。

```text
users:(("java",pid=17211,fd=300))
```

- `java`：进程名。
- `pid`：进程编号，重启后可能改变。
- `fd`：该进程里的文件描述符编号。

检查进程身份，替换为当前 PID：

```bash
ps -fp 17211
systemctl status elasticsearch
```

不能仅看到 `java` 就断定一定是 Elasticsearch，结合命令行和服务 PID 确认。

## 10. 9200、9300 与 ss 输出

| 端口 | 用途 |
|---|---|
| 9200 | HTTP API，供 curl、后端程序、Kibana 等访问 |
| 9300 | Elasticsearch 节点间的 Transport 通信 |

7.x 默认 HTTP 端口范围通常为 `9200–9300`，Transport 范围为 `9300–9400`，各自选择可用端口。今天实际 HTTP 监听端口是 9200；显式设置单个端口后不能再假定它会自动换端口。此前对话给出的范围终点 `9299/9399` 不准确，以此处为准。

```bash
ss -ntpl | grep 9200
```

- `-n`：数字显示地址和端口。
- `-t`：TCP。
- `-p`：显示进程信息；查看其他用户进程通常需要 root。
- `-l`：只看监听套接字。
- `|`：把左边命令的输出交给右边。
- `grep 9200`：筛选包含 9200 的行。

监听状态下，`Recv-Q` 表示当前等待应用接收的连接队列数量，`Send-Q` 表示该队列上限；不要将这里的数值理解为已收发的数据量。

| 地址 | 含义 |
|---|---|
| `127.0.0.1` | IPv4 本机回环 |
| `::1` | IPv6 本机回环 |
| `::ffff:127.0.0.1` | IPv4 回环地址的 IPv6 映射表示 |
| `0.0.0.0` | 所有本地 IPv4 地址 |
| `::` | 所有本地 IPv6 地址；可能同时接受 IPv4 |

右侧对端地址 `[::]:*` 表示监听套接字尚没有固定对端，**不代表防火墙已允许任意来源访问**。

## 11. 问题三：放行 9200 后浏览器仍不能访问

当时输出：

```text
[::ffff:127.0.0.1]:9200
[::1]:9200
```

说明仅监听本机回环。Windows 访问虚拟机 IP 时，请求无法由这个监听接收，开放防火墙不能解决监听地址问题。

查询有效配置：

```bash
grep -nE '^[[:space:]]*(network\.host|http\.host|http\.port)' /etc/elasticsearch/elasticsearch.yml
```

没有输出后，放宽查询，将注释也找出来：

```bash
grep -nE 'network\.host|http\.host|http\.port' /etc/elasticsearch/elasticsearch.yml
```

实际发现配置写在注释后面：

```yaml
# address here to expose this node on the network: network.host: 0.0.0.0
```

整行以 `#` 开头，后面的配置不会生效。修改为独立、顶格的一行：

```yaml
# address here to expose this node on the network:
network.host: 0.0.0.0
```

注意：只需要新增或修正目标行，不要用这个片段覆盖整个配置文件。若存在 `http.host` 或其他 HTTP 专用绑定设置，还需要检查是否覆盖了通用网络设置。

```bash
systemctl restart elasticsearch
systemctl status elasticsearch -l --no-pager
ss -lntp | grep 9200
```

修正后的实际输出出现 `[::]:9200`。对外绑定还可能触发更严格的启动检查；若出现新错误，应根据新日志排查。

浏览器访问地址应为：

```text
http://虚拟机IP:9200
```

Windows 浏览器里的 `127.0.0.1` 指 Windows 本机，不是 CentOS。`0.0.0.0` 用于绑定配置，也不应当作远程访问目标。

## 12. 防火墙状态与放行规则

```bash
systemctl status firewalld
systemctl is-active firewalld
firewall-cmd --state
firewall-cmd --get-active-zones
```

先根据活动区域确认网卡属于哪个 zone，再查询对应规则。下面假设网卡在 `public`：

```bash
firewall-cmd --zone=public --list-all
firewall-cmd --zone=public --list-ports
firewall-cmd --zone=public --list-services
firewall-cmd --zone=public --query-port=9200/tcp
```

- `--list-ports`：直接按端口配置的放行列表。
- `--list-services`：按服务定义放行，例如 ssh。
- `--list-all`：包括 services、ports、rich rules 等区域配置。
- 不指定 `--zone` 时通常查询默认区域，不一定是实际接收流量的区域。

`--query-port=9200/tcp` 返回 `yes` 代表该区域存在这一直接端口规则；返回 `no` **不能单独证明端口被阻止**，还可能通过服务定义、富规则等方式允许。

需要在实验网络放行时：

```bash
firewall-cmd --zone=public --permanent --add-port=9200/tcp
firewall-cmd --reload
firewall-cmd --zone=public --query-port=9200/tcp
```

`--permanent` 修改永久配置，`--reload` 重新加载永久配置成为运行时规则。仅存在于运行时的临时修改可能在重载后丢失。

即使 firewalld 没运行，也不代表系统或上游不存在其他过滤规则。没有认证的 Elasticsearch 数据接口不要直接暴露到公网。

## 13. 网络访问排查顺序

在 CentOS 执行：

```bash
systemctl status elasticsearch -l --no-pager
curl http://127.0.0.1:9200
ss -lntp | grep 9200
hostname -I
firewall-cmd --get-active-zones
```

再查询实际区域的规则。在 Windows PowerShell 测试：

```powershell
Test-NetConnection 虚拟机IP -Port 9200
```

`TcpTestSucceeded : True` 说明 TCP 连接成功，但不等于 API 身份认证、协议和业务处理都正常。

| 现象 | 下一步检查 |
|---|---|
| 服务失败 | journal 和应用日志 |
| 本机 curl 失败 | 服务、端口、HTTP/HTTPS、认证 |
| 本机可访问，只有回环监听 | 网络绑定配置 |
| 已对外监听，远端 TCP 失败 | IP、路由、VMware 模式、防火墙 |
| TCP 成功，浏览器失败 | URL、HTTP/HTTPS、代理和具体错误 |

今天使用 HTTP 测试的是当前实验环境；其他版本或启用安全功能的环境可能需要 HTTPS、证书和账号。

## 14. 为什么同一局域网的其他设备仍访问不到

电脑连接同一个路由器，不意味着都能直接访问 VMware 创建的私有网络。

| VMware 模式 | 常见情况 |
|---|---|
| NAT | 宿主机能访问 VM；其他局域网设备默认通常不能直接访问 VM |
| Host-only | 宿主机与同一虚拟网络中的 VM 通信，其他设备通常无法直接访问 |
| 桥接 | VM 接入物理局域网；能否互访还取决于地址、路由、防火墙和网络隔离 |

查看 VMware 的“虚拟机设置 → 网络适配器”确认模式。今天没有提供该设置的截图或输出，因此 NAT 是合理怀疑，**不是已经证实的原因**。同一 Wi-Fi 下也可能存在访客网络或客户端隔离。

NAT 的其他设备访问可通过端口转发或额外路由实现；桥接则需要重新确认 VM 地址和 SSH 连接。只做个人练习时，宿主机能访问即可，不必为了验证而立即更改网络模式。

## 15. 下一阶段：项目与 Ubuntu 复现

当前已说明安装的组件包括 Tomcat、MySQL、Nginx、RabbitMQ、Elasticsearch，之前也练习过 Redis。组件安装完成后，可以开始完整项目部署，不必等学完全部 Shell 内容。

第一项目建议：[RuoYi-Vue 普通前后端分离版本](https://github.com/yangzongzhuan/RuoYi-Vue)。选定具体版本，依据项目文档核对 Java、MySQL、Redis、Node.js 等要求。

- Nginx：前端静态文件和 API 反向代理。
- Java 后端：处理业务。
- MySQL：业务数据。
- Redis：项目要求的缓存等功能。

Spring Boot 可执行 JAR 通常自带嵌入式 Web 服务器，不一定需要独立 Tomcat。WAR 是否能部署到外置 Tomcat，取决于项目打包方式和兼容版本。RabbitMQ、Elasticsearch 不必强行加入第一个项目。

后续可以考虑 [mall](https://github.com/macrozheng/mall)，进一步练习更多中间件。

### 计划中的机器分工，尚未实施

| 机器 | 建议用途 |
|---|---|
| 阿里云：2 核、4GB 内存、约 40GB 系统盘 | 小规模演示项目，运行必需组件 |
| 本地 VM：1 核、1～2GB 内存 | SSH 跳板机练习 |
| 本地 VM：4 核、8GB 内存起步 | Ubuntu 测试部署，按需运行额外中间件 |

本地电脑有 32GB 内存。云端“40GB”按系统盘容量理解，购买前需确认。2 核 4GB 适合控制资源的低并发演示，不代表能同时运行所有中间件。

先让云端项目独立运行，不把必需数据库放在家中，以免依赖电脑开机和家庭链路。构建在本地完成，再上传构建产物，可降低云端压力。

### CentOS 到 Ubuntu 的建议

1. 保留 CentOS，创建 Ubuntu 24.04 LTS 测试环境。
2. 记录项目版本和依赖要求，重新安装软件，不直接复制旧安装目录。
3. 迁移必要配置，核对路径、服务名、运行用户和文件权限。
4. MySQL 测试数据按需导出 SQL、导入并验证；账号权限另行检查。
5. RabbitMQ definitions 不包含队列消息；Elasticsearch 数据迁移使用兼容的快照恢复，不能简单搬运数据目录。
6. 完成手动启动、systemd 管理、Nginx 反代、日志检查、备份恢复和发布回退。
7. 将本地验证成功的步骤复现到相同系统版本的云服务器。

云安全组和系统防火墙是两层控制，需要分别检查。普通 SSH 跳板机先练账号、密钥和 sudo；完整堡垒机的审批、会话审计等功能后续再学。

Shell 可以结合三个实际需求开始：服务健康检查、按日期备份数据库、发布并判断成功与否。优先学习变量、引号、条件判断、退出状态码和重定向。

## 16. 今天最重要的经验

- 安装成功、服务运行、端口监听、远端可达、业务正常，是不同检查层次。
- 启动失败先看日志，不要先重装。
- YAML 顶层配置要顶格；`#` 注释行里的配置不生效。
- 防火墙放行不能代替服务对外监听，也不能自动解决路由问题。
- 修改前备份，修改后重启并验证；记录实际版本和排错证据。
