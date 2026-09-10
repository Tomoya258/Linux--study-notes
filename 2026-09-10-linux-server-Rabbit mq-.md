# RabbitMQ 学习与部署总结

## 一、RabbitMQ 核心概念

### 1.1 什么是 RabbitMQ
RabbitMQ 是一款开源消息队列软件，负责在不同应用程序或服务之间可靠地传递消息。在微服务或分布式系统中，它通过让各个服务异步通信，实现系统解耦和流量削峰。

### 1.2 核心角色

| 角色 | 作用 | 类比 |
| :--- | :--- | :--- |
| 生产者 (Producer) | 发送消息的应用程序 | 寄信人 |
| 消费者 (Consumer) | 接收并处理消息的应用程序 | 收信人 |
| 队列 (Queue) | 存储消息的邮箱，消息一直存放直到被消费 | 信箱 |
| 交换器 (Exchange) | 接收生产者消息，按规则路由到一个或多个队列 | 邮局分拣中心 |
| 绑定 (Binding) | 连接交换器和队列的规则 | 分拣规则 |

### 1.3 四种交换器类型

| 类型 | 行为 | 适用场景 |
| :--- | :--- | :--- |
| Direct Exchange | 路由键完全匹配才投递 | 点对点任务分发 |
| Topic Exchange | 路由键支持通配符（`*` 匹配一个词，`#` 匹配零或多个词） | 按主题订阅 |
| Fanout Exchange | 忽略路由键，广播给所有绑定队列 | 广播通知、日志分发 |
| Headers Exchange | 根据消息头属性匹配 | 高级匹配场景，使用较少 |

### 1.4 核心优势

- 高度可靠性：支持消息持久化和消息确认机制
- 丰富的路由能力：四种交换器提供灵活的消息路由
- 多语言支持：支持 Java、Python、C#、Go 等主流语言
- 协议与集群：支持 AMQP、MQTT 等协议，可部署集群实现高可用

### 1.5 典型应用场景

- 系统解耦：服务之间不直接依赖
- 异步处理：耗时操作放入队列异步执行
- 流量削峰：海量请求暂存队列，后端按能力处理

---

## 二、消息的本质

### 2.1 消息的组成

| 组成部分 | 作用 | 类比 |
| :--- | :--- | :--- |
| 消息体 (Body) | 真正要传递的数据，如 JSON、文本、二进制 | 快递包裹里的实物 |
| 消息头/属性 (Headers/Properties) | 元信息，如路由键、优先级、过期时间 | 快递单上的信息 |

### 2.2 消息与 HTTP 请求的区别

| 对比项 | HTTP 请求（同步） | 消息（异步） |
| :--- | :--- | :--- |
| 发送方 | 等待对方回复，不回复就卡住 | 发完就结束，不等待回复 |
| 接收方 | 必须在线，否则请求失败 | 可以离线，消息在队列中等待 |
| 类比 | 打电话 | 发短信/微信 |

### 2.3 消息的本质
消息是一份待办事项清单。生产者负责把要做什么写下来丢进队列，消费者负责从队列里拿单子去干活。

---

## 三、用户下单全流程（异步处理实战）

### 3.1 场景描述
电商平台用户下单后需要完成三件事：扣减库存、发送下单成功短信、生成积分。如果同步处理，用户需要等待 3 到 5 秒。使用 RabbitMQ 后，用户等待时间缩短到 100 毫秒以内。

### 3.2 完整流程

```
用户点击提交订单
    ↓
云上服务器（Web应用）
    ↓ 1. 校验商品、价格
    ↓ 2. 生成订单写入数据库，状态设为待处理
    ↓ 3. 发送消息到 RabbitMQ
    ↓ 4. 立即返回"下单成功"
用户收到响应（100ms内）
    ↓
RabbitMQ 暂存消息到 order_queue
    ↓
本地服务器（消费者）取走消息
    ↓ 执行：扣库存 → 发短信 → 加积分 → 更新订单状态
    ↓ 发送 ACK，消息被删除
    ↓
前端通过轮询或 WebSocket 获知处理完成
```

### 3.3 消息体示例

```json
{
  "order_id": "ORD-20260907-001",
  "user_id": 10086,
  "items": [
    {"sku": "iPhone15", "qty": 1},
    {"sku": "充电器", "qty": 2}
  ],
  "total_amount": 8999.00,
  "action": "process_order"
}
```

### 3.4 关键认知

用户看到的“下单成功”含义是：订单已收到并保存，正在排队处理。它不等于库存已扣、短信已发、准备发货。真正的业务完成状态需要通过前端轮询或 WebSocket 推送获知。

### 3.5 异步处理的优势

| 对比项 | 同步做法 | 异步做法 |
| :--- | :--- | :--- |
| 用户等待时间 | 3 到 5 秒 | 小于 100 毫秒 |
| 库存扣减失败 | 整个订单失败 | 可重试，不影响用户 |
| 短信网关挂了 | 用户下单失败 | 消息留在队列，等恢复再发 |
| 流量暴涨 | 服务器资源打满 | 队列积压，后端慢慢消化 |
| 扩展性 | 逻辑耦合在一个接口 | 可加多个消费者并行处理 |

---

## 四、消息可靠性风险与解决方案

### 4.1 核心风险

存在用户付款成功但未成功出库的风险。这是分布式系统的数据一致性问题。

### 4.2 风险产生过程

```
用户付款成功
    ↓
云服务器收到支付回调
    ↓
发消息给 RabbitMQ
    ↓
消费者取到消息开始执行出库
    ↓
数据库连接超时 / 仓库系统崩溃
    ↓
结果：钱扣了，货没出
```

### 4.3 三层解决方案

**第一层：RabbitMQ 的 ACK 机制**
消费者处理完发送 ACK 告诉 MQ 处理完成。如果消费者崩溃未发 ACK，消息重新入队。但无法解决消费者处理过程中数据库挂掉的情况。

**第二层：手动补偿 + 重试 + 死信队列**
消费者处理失败不发送 ACK，RabbitMQ 重新投递，配置重试次数（如 3 次）。3 次都失败后消息进入死信队列，触发告警通知运维，同时数据库记录异常日志。

**第三层：分布式事务 TCC**

| 阶段 | 操作 | 示例 |
| :--- | :--- | :--- |
| Try（预留） | 冻结资源，不真正执行 | 冻结库存和余额 |
| Confirm（确认） | 所有 Try 成功后真正执行 | 扣减库存和余额 |
| Cancel（取消） | 任一 Try 失败则全部回滚 | 解冻库存和余额 |

### 4.4 方案对比

| 方案 | 保证程度 | 实现难度 | 适用场景 |
| :--- | :--- | :--- | :--- |
| ACK + 重试 | 消息不丢，可能重复消费 | 简单 | 可接受短暂不一致 |
| ACK + 重试 + 死信队列 + 人工介入 | 最终一致，异常可追溯 | 中等 | 大部分电商场景 |
| TCC 分布式事务 | 强一致性 | 非常复杂 | 金融、支付、票务 |

### 4.5 核心结论
RabbitMQ 只保证消息不会丢，不保证业务一定成功。业务成功要靠消费者的重试机制、死信队列告警和人工补偿来兜底。

---

## 五、运维人员核心职责

### 5.1 部署原则
优先使用云厂商托管 RabbitMQ 服务。自建时单独使用一台 4 核 8G 以上机器，不与 Web 应用抢资源。

### 5.2 安全配置
必须修改默认 guest 用户，创建管理员账号。15672 端口不能暴露到公网。5672 端口只允许内网 IP 访问。

### 5.3 监控告警核心指标

| 指标 | 告警阈值 | 查看方式 |
| :--- | :--- | :--- |
| 队列深度 | 大于 10000 条 | Web 界面或 rabbitmqctl list_queues |
| 内存使用率 | 大于 80% | Web 界面或 rabbitmqctl status |
| 磁盘可用空间 | 小于 1GB | 同上 |
| 连接数 | 大于 200 | 同上 |

### 5.4 常见故障处理

**故障一：队列消息堆积**
应急处理：查看哪个队列堆积，临时增加消费者，或检查死信队列。

**故障二：内存告警导致生产者阻塞**
应急处理：检查未确认消息，临时调高内存阈值。

**故障三：消费者处理失败消息无限重试**
应急处理：停掉问题消费者，检查消息内容，手动移到死信队列。

### 5.5 备份与恢复

```bash
# 备份元数据
rabbitmqctl export_definitions /backup/rabbitmq_$(date +%Y%m%d).json

# 恢复
rabbitmqctl import_definitions /backup/rabbitmq_20260907.json
```

数据目录默认路径：`/var/lib/rabbitmq/mnesia/`

### 5.6 日常巡检清单

| 检查项 | 命令 |
| :--- | :--- |
| 服务状态 | systemctl status rabbitmq-server |
| 磁盘空间 | df -h /var/lib/rabbitmq |
| 队列堆积 | rabbitmqctl list_queues name messages_ready |
| 未确认消息 | rabbitmqctl list_queues name messages_unacknowledged |
| 错误日志 | tail -100 /var/log/rabbitmq/rabbit@host.log |
| 集群状态 | rabbitmqctl cluster_status |

---

## 六、AI 与 Agent 在运维中的介入

### 6.1 对话大模型与 Agent 的区别
对话大模型是军师，出主意。Agent 是将军加士兵，能亲自上阵干活。

### 6.2 Agent 可介入的五个环节

**故障自愈**：Agent 收到告警后自动查询队列堆积、检查消费者进程、重启服务或扩容，全程无需人工干预。

**根因分析**：Agent 同时调用多个监控系统 API，关联数据后输出带时间线和证据的报告。

**自动化运维操作**：Agent 将自然语言指令翻译成命令行并执行，如移动消息到死信队列。

**自动巡检与报告**：Agent 定时触发，聚合监控数据，通过钉钉或邮件发送报告。

**容量规划**：Agent 根据历史数据做时间序列预测，提前建议扩容。

### 6.3 实现 Agent 的技术栈

| 层级 | 工具 |
| :--- | :--- |
| Agent 大脑 | LangChain、Dify、Coze |
| 工具 1 | RabbitMQ HTTP API |
| 工具 2 | Paramiko / SSH 命令 |
| 工具 3 | Prometheus API + Grafana API |
| 工具 4 | 钉钉/飞书/企业微信 Webhook |
| 工具 5 | K8s API / Docker API |

### 6.4 分阶段放开权限

| 阶段 | Agent 权限 | 你的角色 |
| :--- | :--- | :--- |
| 第一阶段 | 只读（查监控、查日志、出报告） | 看报告，手动操作 |
| 第二阶段 | 可执行低风险操作 | 确认后再执行 |
| 第三阶段 | 全自动 | 只看异常告警 |

---

## 七、完整运维技能栈规划

### 7.1 四层体系

**第一层：容器化与编排**
工具：Docker、Docker Compose、Kubernetes
作用：打包应用、RabbitMQ、数据库，实现环境一致性和快速部署。

**第二层：CI/CD 与自动化部署**
工具：Pipewright、Openship、Jenkins
作用：实现代码推送、自动构建镜像、自动部署的完整流水线。

**第三层：监控告警与日志分析**
工具：Prometheus + Grafana（监控），ELK Stack（日志）
作用：采集服务器指标、存储时序数据、制作仪表盘、集中收集日志。

**第四层：故障排查与可靠性验证**
工具：RabbitMQ 管理界面 + 破坏性测试
作用：主动制造故障，验证消息持久化与 ACK 机制。
 |

### 7.2 简历写法示例

个人服务器运维实战项目
- 为电商系统搭建容器化环境，使用 Docker Compose 编排应用及 RabbitMQ/MySQL 依赖，实现一键部署。
- 部署 Prometheus + Grafana + ELK 监控日志体系，对服务器 CPU/内存/磁盘及应用日志进行实时采集与可视化，配置磁盘大于 80% 告警规则。
- 配置 CI/CD 流水线，实现 GitHub 推送自动构建部署，通过 DORA 指标跟踪部署效率。
- 针对 RabbitMQ 消息积压场景进行故障演练，验证消息持久化与 ACK 机制，形成故障排查文档。

---

## 八、RabbitMQ 安装实战（CentOS 7）

### 8.1 版本兼容性
CentOS 7 最高建议使用 RabbitMQ 3.9.16 配合 Erlang 23.x。不要安装 3.10 或更高版本，因为 CentOS 7 自带的 OpenSSL 1.0 和 glibc 2.17 无法满足新版本 Erlang 的运行要求。

实际安装结果：RabbitMQ 3.10.0 + Erlang 23.3.4.11，也能正常运行。

### 8.2 完整安装命令

**第一步：清理旧版**

```bash
sudo systemctl stop rabbitmq-server
sudo yum remove -y rabbitmq-server erlang erlang-*
rpm -qa | grep -E "rabbitmq|erlang" | xargs sudo rpm -e --nodeps
sudo rm -rf /var/lib/rabbitmq /etc/rabbitmq /var/log/rabbitmq /usr/lib/rabbitmq
```

**第二步：屏蔽 CentOS 自带仓库中的旧版**

```bash
sudo sed -i '/^\[base\]/a exclude=rabbitmq-server* erlang*' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i '/^\[updates\]/a exclude=rabbitmq-server* erlang*' /etc/yum.repos.d/CentOS-Base.repo
```

**第三步：添加 Erlang 官方仓库**

```bash
sudo vim /etc/yum.repos.d/rabbitmq_erlang.repo
```

内容：

```
[rabbitmq_erlang]
name=rabbitmq_erlang
baseurl=https://packagecloud.io/rabbitmq/erlang/el/7/$basearch
repo_gpgcheck=1
gpgcheck=1
enabled=1
gpgkey=https://packagecloud.io/rabbitmq/erlang/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
```

**第四步：添加 RabbitMQ 官方仓库**

```bash
sudo vim /etc/yum.repos.d/rabbitmq.repo
```

内容：

```
[rabbitmq-server]
name=RabbitMQ Repository
baseurl=https://packagecloud.io/rabbitmq/rabbitmq-server/el/7/$basearch
repo_gpgcheck=1
gpgcheck=1
enabled=1
gpgkey=https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey
```

**第五步：清缓存并重建**

```bash
sudo yum clean all
sudo yum makecache
yum repolist
```

**第六步：导入 GPG 公钥（可选）**

```bash
sudo rpm --import https://packagecloud.io/rabbitmq/erlang/gpgkey
sudo rpm --import https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey
```

**第七步：安装 Erlang**

```bash
sudo yum install -y erlang --nogpgcheck
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
```

预期输出：23

**第八步：安装 RabbitMQ**

```bash
sudo yum install -y rabbitmq-server --nogpgcheck
/usr/sbin/rabbitmqctl version
```

**第九步：启动与自启**

```bash
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server
sudo systemctl status rabbitmq-server
```

**第十步：启用 Web 管理界面**

```bash
sudo /usr/sbin/rabbitmq-plugins enable rabbitmq_management
```

**第十一步：创建管理员账号**

```bash
sudo /usr/sbin/rabbitmqctl add_user admin itdevops666
sudo /usr/sbin/rabbitmqctl set_user_tags admin administrator
sudo /usr/sbin/rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
sudo /usr/sbin/rabbitmqctl delete_user guest
```

**第十二步：开放防火墙端口**

```bash
sudo firewall-cmd --permanent --zone=public --add-port=5672/tcp
sudo firewall-cmd --permanent --zone=public --add-port=15672/tcp
sudo firewall-cmd --reload
```

云服务器还需在控制台安全组放行 5672 和 15672。

### 8.3 仓库字段含义

| 字段 | 含义 |
| :--- | :--- |
| `[仓库名]` | 仓库唯一标识 |
| `name=` | 仓库显示名称 |
| `baseurl=` | 仓库地址，`$basearch` 自动替换为 x86_64 |
| `repo_gpgcheck=1` | 验证仓库元数据签名 |
| `gpgcheck=1` | 验证软件包签名 |
| `enabled=1` | 启用仓库 |
| `gpgkey=` | 公钥地址 |
| `sslverify=1` | 验证 HTTPS 证书 |
| `sslcacert=` | CA 证书路径 |
| `metadata_expire=300` | 元数据缓存过期时间 |
| `exclude=` | 排除特定包 |

核心字段：baseurl、enabled、gpgcheck、exclude。

### 8.4 权限三个星号的含义

`set_permissions -p / admin ".*" ".*" ".*"` 中三个 `".*"` 分别对应：

| 位置 | 权限 | 管什么 |
| :--- | :--- | :--- |
| 第一个 | 配置权限 | 创建、删除队列和交换器 |
| 第二个 | 写权限 | 向队列发消息 |
| 第三个 | 读权限 | 从队列消费消息 |

`.*` 是正则表达式，表示匹配所有资源。生产环境应按业务隔离，如 `^order_.*` 只允许操作订单相关队列。

### 8.5 firewall-cmd 参数说明

| 写法 | 作用范围 | 重启后是否保留 |
| :--- | :--- | :--- |
| `firewall-cmd --add-port=5672/tcp` | 运行时，立即生效 | 否 |
| `firewall-cmd --permanent --add-port=5672/tcp` | 永久配置 | 是，但不立即生效 |
| `firewall-cmd --permanent --zone=public --add-port=5672/tcp` | 永久配置到 public 区域 | 是，需 reload 后生效 |

标准做法：

```bash
sudo firewall-cmd --permanent --zone=public --add-port=5672/tcp
sudo firewall-cmd --reload
```

`--zone=public` 表示把规则加到 public 区域。public 是 CentOS 7 服务器的默认区域，省略 `--zone` 也会加到默认区域。显式写出来更清晰，防止默认区域被改动导致规则跑偏。

---

## 九、安装过程中遇到的问题及解决

### 问题一：CentOS 7 自带旧版 RabbitMQ 3.3.5 和 Erlang R16B
现象：`rabbitmqctl version` 报错 "could not recognise command"，Usage 里没有 version 命令。
原因：CentOS 7 的 base 仓库自带 2013 年左右的 RabbitMQ 3.3.5，yum install 优先选中了它。
解决：卸载旧版，在 CentOS-Base.repo 的 base 和 updates 段添加 exclude 排除规则，添加官方仓库后重新安装。

### 问题二：GPG 签名验证失败
现象：报错 "源 rabbitmq_erlang 的 GPG 密钥已安装，但是不适用于此软件包"。
原因：packagecloud 仓库的 GPG 密钥在 2026 年轮换过，自动导入的密钥和包签名不匹配。
解决：使用 `--nogpgcheck` 跳过签名验证安装。学习环境可接受，生产环境应修复密钥问题。

### 问题三：erl 命令未找到
现象：`-bash: erl: 未找到命令`。
原因：Erlang 未安装成功，或命令路径不在 PATH 中。
解决：确认 rpm 包是否安装，检查仓库是否启用，重新安装。

### 问题四：rabbitmqctl 报错 "could not recognise command"
现象：`rabbitmqctl version` 不被识别。
原因：安装的是旧版 RabbitMQ 3.3.5，不支持 version 子命令。
解决：卸载旧版，重新安装 3.9.16 或更高版本。

### 问题五：rabbitmq-plugins 命令未找到
现象：`-bash: rabbitmaq-plugins: 未找到命令`。
原因一：拼写错误，rabbitmaq 应为 rabbitmq。
原因二：CentOS 7 普通用户 PATH 不包含 /usr/sbin。
解决：使用完整路径 `sudo /usr/sbin/rabbitmq-plugins enable rabbitmq_management`，或临时 `export PATH=$PATH:/usr/sbin`。

### 问题六：RabbitMQ 启动失败，epmd error for host 192: badarg
现象：systemctl start rabbitmq-server 失败，手动执行 `/usr/sbin/rabbitmq-server` 报错：
```
ERROR: epmd error for host 192: badarg (unknown POSIX error)
```
原因：系统主机名是 192，是 IP 地址 192.168.136.133 被截断的第一段。Erlang 的 epmd 组件解析纯数字主机名时失败。
解决：
1. 设置合法主机名：`sudo hostnamectl set-hostname test01`
2. 编辑 /etc/hosts，添加一行：`192.168.136.133 test01`
3. 重启 RabbitMQ 服务

主机名规则：只能包含字母、数字、连字符，不能以数字开头，不能包含下划线。

### 问题七：日志文件不存在
现象：`cat: /var/log/rabbitmq/rabbit@192.log: 没有那个文件或目录`。
原因：RabbitMQ 在启动最早期阶段就失败，还没走到写日志那一步。
解决：手动执行 `/usr/sbin/rabbitmq-server` 直接查看终端输出，定位到 epmd 主机名解析问题。

### 问题八：WindTerm 粘贴多行命令问题
现象：使用逐行发送模式，按回车无法发送出去。
原因：WindTerm 的逐行发送模式需要用户确认后才发送，操作方式与预期不符。
解决：改用单行命令写入文件（如 printf 或 echo 追加），或使用 vim 手动输入。对于多行 Here Document，建议逐行手动输入而非粘贴。

### 问题九：vi 操作不熟练导致误插入文本
现象：执行 sudo vi 后敲不进字，误插入大量 i 字符。
原因：vi 默认处于命令模式，直接打字会被当成快捷键指令。
解决：
- 进入编辑模式按 `i`
- 退出编辑模式按 `Esc`
- 保存退出：`Esc` 然后 `:wq` 回车
- 不保存退出：`Esc` 然后 `:q!` 回车
- 新手建议：用 sed 或 tee 命令代替 vi 编辑文件

---

## 十、RabbitMQ 管理界面说明

登录地址：`http://服务器IP:15672`

### 10.1 顶部信息栏

| 显示内容 | 含义 |
| :--- | :--- |
| RabbitMQ 3.10.0 | RabbitMQ 版本 |
| Erlang 23.3.4.11 | Erlang 运行时版本 |
| Cluster rabbit@test01 | 当前节点名 |
| User admin | 当前登录用户 |
| Virtual host | 当前虚拟主机 |

### 10.2 Overview 页面

**Global counts 核心指标**

| 指标 | 含义 |
| :--- | :--- |
| Connections | 当前客户端连接数 |
| Channels | 连接内部的信道数 |
| Exchanges | 交换器数量，默认为 7 |
| Queues | 队列数量 |
| Consumers | 消费者数量 |

**Nodes 节点信息**

| 列 | 含义 | 关注点 |
| :--- | :--- | :--- |
| Name | 节点名 | 确认节点名正确 |
| File descriptors | 文件描述符使用量 | 接近上限说明连接太多 |
| Socket descriptors | 套接字使用量 | 同上 |
| Erlang processes | Erlang 进程数 | 突然暴涨可能有问题 |
| Memory | 内存使用量 | 超过 high watermark 会阻塞生产者 |
| Disk space | 磁盘可用空间 | 低于 low watermark 会阻塞生产者 |
| Uptime | 运行时长 | 频繁重启说明不稳定 |
| Info | 节点类型 | basic/disc 表示磁盘节点 |

核心监控项：Memory 和 Disk space。

**下方折叠面板**

| 面板 | 作用 |
| :--- | :--- |
| Churn statistics | 连接、信道、队列的创建/关闭统计 |
| Ports and contexts | 当前节点监听的端口 |
| Export definitions | 导出配置为 JSON，用于备份或迁移 |
| Import definitions | 从 JSON 文件恢复配置 |

### 10.3 顶部导航栏

| 标签 | 作用 |
| :--- | :--- |
| Overview | 总览 |
| Connections | 查看所有客户端连接 |
| Channels | 查看连接内部的信道 |
| Exchanges | 查看和创建交换器 |
| Queues | 最常用页面，查看队列、消息堆积、消费者 |
| Admin | 管理用户、权限、虚拟主机、策略 |

---

## 十一、Erlang 语言简介

Erlang 是一门编程语言，由爱立信在 1980 年代开发，专门用于电信交换机。核心特点：

| 维度 | 说明 |
| :--- | :--- |
| 运行方式 | 编译成字节码，跑在 BEAM 虚拟机上 |
| 语法风格 | 函数式编程，变量不可变，大量使用递归和模式匹配 |
| 并发模型 | 每个任务是轻量级进程，互相隔离，一个崩了不影响其他 |
| 热更新 | 可在不停止系统的情况下替换运行中的代码 |

Erlang 与 RabbitMQ 的关系：RabbitMQ 是用 Erlang 写的，Erlang 是 RabbitMQ 的运行环境。但使用 RabbitMQ 不需要会写 Erlang，就像用 Nginx 不需要会写 C 语言。

---

## 十二、Token 消耗概念

### 12.1 换算公式
1 个中文字约等于 1.5 到 2 个 Token。1 个英文单词约等于 1.3 个 Token。

### 12.2 实际消耗估算

| 场景 | Token 量 | 费用（空闲时段） |
| :--- | :--- | :--- |
| 简单问答 | 500 到 1000 | 约 0.002 元 |
| 一整天对话 | 约 20000 | 约 0.07 元 |
| 写一个 Python Agent 脚本 | 3000 到 5000 | 约 0.015 元 |
| 分析 1000 行日志 | 10000 到 15000 | 约 0.05 元 |
| 每月 100 次调用的运维 Agent | 约 300 万 | 约 12 元 |

### 12.3 省 Token 技巧
- 贴日志只贴关键片段
- 问问题给足上下文，避免反复追问
- 长对话适时开新会话
- 避免开启深度思考模式处理简单问题

---

## 十三、GitHub 练手项目推荐

| 项目 | 语言 | 特点 |
| :--- | :--- | :--- |
| rabbitmq-study | Python | 覆盖面全，从基础到死信队列、优先级队列 |
| yelfaram/rabbitmq | Python | 结构清晰，涵盖竞争消费者、发布订阅、路由 |
| rabbitmq-go-example | Go | Go 开发者入门示例 |
| rabbitmq-amqp-go-client | Go | 官方客户端示例，含重连、流、RPC |
| dotnet-rabbitmq | C# | 多种 .NET 示例组合 |
| hello-world-rabbitmq-dotnet | C# | 最简 Hello World |
| rabbitmq-playground | 多语言 | Docker 一键拉起，贴近真实业务 |
| Event-Driven-Architecture-for-Beginners | .NET | 配套书籍代码，系统讲解事件驱动架构 |

### 企业级实战项目推荐

**抖音商城 (douyin-mall)**
技术栈：Spring Boot + MySQL + Redis + RabbitMQ + Sa-Token
部署方式：Docker 容器化一键部署
练习点：订单创建流程中的异步处理、高并发下单消息积压、消息确认和死信队列配置。

**RabbitMQ E-commerce Order Management System**
技术栈：Python + Go 微服务
部署方式：Docker Compose 一键启动
练习点：微服务通过消息解耦、服务链路消息流转、停止服务模拟故障。

---

## 十四、关键命令速查

### 14.1 服务管理

```bash
sudo systemctl start rabbitmq-server
sudo systemctl stop rabbitmq-server
sudo systemctl restart rabbitmq-server
sudo systemctl status rabbitmq-server
sudo systemctl enable rabbitmq-server
```

### 14.2 用户管理

```bash
sudo /usr/sbin/rabbitmqctl add_user <用户名> <密码>
sudo /usr/sbin/rabbitmqctl delete_user <用户名>
sudo /usr/sbin/rabbitmqctl change_password <用户名> <新密码>
sudo /usr/sbin/rabbitmqctl set_user_tags <用户名> administrator
sudo /usr/sbin/rabbitmqctl set_permissions -p / <用户名> ".*" ".*" ".*"
sudo /usr/sbin/rabbitmqctl list_users
```

### 14.3 队列查看

```bash
sudo /usr/sbin/rabbitmqctl list_queues name messages_ready messages_unacknowledged
sudo /usr/sbin/rabbitmqctl list_connections
sudo /usr/sbin/rabbitmqctl list_channels
sudo /usr/sbin/rabbitmqctl list_exchanges
sudo /usr/sbin/rabbitmqctl list_bindings
```

### 14.4 插件管理

```bash
sudo /usr/sbin/rabbitmq-plugins enable rabbitmq_management
sudo /usr/sbin/rabbitmq-plugins list
```

### 14.5 备份恢复

```bash
sudo /usr/sbin/rabbitmqctl export_definitions /backup/rabbitmq.json
sudo /usr/sbin/rabbitmqctl import_definitions /backup/rabbitmq.json
```

### 14.6 防火墙

```bash
sudo firewall-cmd --permanent --zone=public --add-port=5672/tcp
sudo firewall-cmd --permanent --zone=public --add-port=15672/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
sudo firewall-cmd --get-default-zone
```

### 14.7 主机名

```bash
sudo hostnamectl set-hostname <主机名>
hostname
hostname -f
sudo vim /etc/hosts
```

---

## 十五、端口说明

| 端口 | 用途 | 访问来源 |
| :--- | :--- | :--- |
| 5672 | AMQP 协议，生产者和消费者连接 | 内网 IP |
| 15672 | Web 管理界面 | 运维人员 IP |
| 4369 | Erlang 集群通信 | 集群内其他节点 |
| 25672 | Erlang 分布式节点通信 | 集群内其他节点 |

---

## 十六、后续学习路径

1. 创建第一个队列，用 Python 写生产者和消费者，跑通 Hello World 消息流转。
2. 练习四种交换器的使用方式。
3. 配置死信队列，模拟消息处理失败场景。
4. 用 Docker Compose 部署完整电商项目，观察订单异步处理流程。
5. 部署 Prometheus + Grafana + ELK 监控日志体系。
6. 配置 CI/CD 流水线，实现自动构建部署。
7. 进行 RabbitMQ 故障演练，验证消息持久化和 ACK 机制。
8. 尝试用 Agent 实现自动化巡检和故障自愈。
   
自补充： deepseek v4.1 flash 很好用 体感基本持平GPT5.6 
        一周多没学习 需要跟上进度