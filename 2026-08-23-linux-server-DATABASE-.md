

# Linux 运维学习笔记 - 2026年8月23日

## 一、今日学习内容

- [x] 在 CentOS 7 上安装 MySQL 8.0
- [x] MySQL 初始配置和密码修改
- [x] 配置 MySQL 远程访问（防火墙 + 安全组）
- [x] 使用 DBeaver 从 Windows 本地连接远程 MySQL
- [x] 完成数据库/数据表的基本 CRUD 操作验证

---

## 二、整体连接链路

```
本地 DBeaver
    ↓ (JDBC)
Linux 云服务器 (SSH Tunnel)
    ↓ (127.0.0.1:3306)
MySQL 8.0
    ↓
数据库 (Database)
    ↓
数据表 (Table)
    ↓
数据 (Data)
```

---

## 三、MySQL 安装与配置

### 3.1 安装 MySQL 8.0

```bash
# 添加 MySQL YUM 源
sudo yum install -y https://repo.mysql.com/mysql80-community-release-el7-3.noarch.rpm

# 安装 MySQL 服务器
sudo yum install -y mysql-community-server
```

### 3.2 启动 MySQL 并设置开机自启

```bash
# 启动服务
sudo systemctl start mysqld

# 设置开机自启
sudo systemctl enable mysqld

# 查看运行状态
sudo systemctl status mysqld
```

>  预期结果：看到 `active (running)` 字样

### 3.3 获取临时密码并修改 root 密码

```bash
# 获取临时密码
sudo grep 'temporary password' /var/log/mysqld.log
```

```sql
-- 登录 MySQL
mysql -u root -p

-- 修改密码
ALTER USER 'root'@'localhost' IDENTIFIED BY 'ItDevops@666';
FLUSH PRIVILEGES;
```

---

## 四、遇到的问题及解决方案

### ❌ 问题 1：GPG 密钥验证失败

**报错信息：**
```
mysql-community-common-8.0.46-1.el7.x86_64.rpm 的公钥尚未安装
GPG 密钥配置为：file:///etc/pki/rpm-gpg/RPM-GPG-KEY-mysql
```

** 解决方案：**
```bash
# 跳过 GPG 检查快速安装
sudo yum install -y mysql-community-server --nogpgcheck
```

---

### ❌ 问题 2：firewall-cmd 命令报错

**报错信息：**
```
firewall-cmd: error: ambiguous option: --list-cmd match ...
```

** 解决方案：**
```bash
# 正确语法：指定 zone
firewall-cmd --zone=public --add-port=3306/tcp --permanent
firewall-cmd --reload

# 查看已开放端口
firewall-cmd --zone=public --list-ports
```

---

### ❌ 问题 3：MySQL 远程登录失败

**报错信息：**
```
ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)
```

**✅ 解决方案：**

1. **确认密码正确**：`ItDevops@666`
2. **修改 root 允许远程访问**：
```sql
USE mysql;
UPDATE user SET Host='%' WHERE User='root';
FLUSH PRIVILEGES;
```

3. **修改配置文件绑定所有 IP**：
```bash
# 编辑 /etc/my.cnf
bind-address = 0.0.0.0

# 重启 MySQL
sudo systemctl restart mysqld
```

4. **开放防火墙端口**：
```bash
firewall-cmd --zone=public --add-port=3306/tcp --permanent
firewall-cmd --reload
```

5. **云服务器安全组放行 3306 端口**（重要！）

---

### ❌ 问题 4：DBeaver 连接报错 - Public Key Retrieval

**报错信息：**
```
Public Key Retrieval is not allowed
```

**原因分析：**
- MySQL 8 默认使用 `caching_sha2_password` 认证方式
- JDBC 驱动默认 `allowPublicKeyRetrieval=false`，不允许获取 RSA 公钥

**✅ 解决方案：**

**方法一：在 DBeaver 连接 URL 中添加参数**
```
jdbc:mysql://127.0.0.1:3306/?allowPublicKeyRetrieval=true&useSSL=false&serverTimezone=Asia/Shanghai
```

**方法二：在 DBeaver 驱动属性中添加**
```
allowPublicKeyRetrieval = true
useSSL = false
```

---

### ❌ 问题 5：Invalid argument: No enum constant

**错误写法：**
```
useSSL= TRUE
allowPublicKeyRetrieval= TRUE
```

**原因：** `=` 后面有空格，JDBC 解析失败

**✅ 正确写法：**
```
useSSL=false&allowPublicKeyRetrieval=true
```

> ⚠️ 注意：`=` 后面**不要加空格**

---

### ❌ 问题 6：Unknown database 'test'

**报错信息：**
```
SQL 错误 [1049] [42000]: Unknown database 'test'
```

**原因：** 执行 `USE test;` 时，MySQL 中不存在名为 `test` 的数据库

**✅ 解决方案：**
```sql
-- 先查看实际存在的数据库
SHOW DATABASES;

-- 如果需要，创建 test 数据库
CREATE DATABASE test;
USE test;
```

---

## 五、DBeaver 远程连接配置

### 5.1 配置 SSH 隧道（推荐方式）

```
DBeaver
    │
    ├── MySQL 配置
    │   ├── Host: 127.0.0.1
    │   ├── Port: 3306
    │   ├── Database: (留空)
    │   ├── Username: root
    │   └── Password: MySQL密码
    │
    └── SSH Tunnel 配置
        ├── Host/IP: Linux虚拟机公网IP
        ├── Port: 22
        ├── User Name: root
        └── Password: Linux root密码
```

### 5.2 为什么 MySQL 主机填 127.0.0.1？

因为使用的是 **SSH 隧道**：

```
Windows (DBeaver)
    │
    │ SSH 连接 (22端口)
    ▼
Linux 云服务器
    │
    │ 127.0.0.1:3306 (本地回环)
    ▼
MySQL 服务
```

- **SSH 主机** = Linux 服务器的真实 IP
- **MySQL 主机** = 127.0.0.1（因为 SSH 隧道把本地端口转发到服务器本地）

### 5.3 DBeaver 执行 SQL 快捷键

| 操作 | 快捷键 |
|------|--------|
| 执行 SQL | `Ctrl + Enter` |
| 换行 | `Enter` |

---

## 六、验证测试

### 6.1 查看 MySQL 监听端口

```bash
ss -lntp | grep 3306
```

输出示例：
```
LISTEN     0      128       [::]:3306       [::]:*       users:(("mysqld"...))
```

> `[::]:3306` 表示在 IPv6 所有地址上监听，也接受 IPv4 连接

| 端口 | 用途 |
|------|------|
| **3306** | MySQL 经典协议端口（DBeaver 使用） |
| 33060 | MySQL X Protocol 端口（MySQL Shell 使用） |

### 6.2 创建测试表并插入数据

```sql
-- 创建数据库
CREATE DATABASE usertest;
USE usertest;

-- 创建测试表
CREATE TABLE user_test (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50)
);

-- 插入数据
INSERT INTO user_test (name) VALUES ('tomoya');

-- 查询数据
SELECT * FROM user_test;
```

**结果：** 成功查询到 `tomoya` ✅

---

## 七、今日理解的重要概念

### 7.1 端口是什么？

- **IP** = 找到服务器（如 `192.168.x.x`）
- **端口** = 找到服务器上的具体服务（如 `:3306`）

```
192.168.x.x:3306  → 访问这台服务器上的 MySQL 服务
```

### 7.2 `ss -lntp` 参数详解

| 参数 | 含义 |
|------|------|
| `-l` | 只显示正在监听 (listening) 的端口 |
| `-n` | 直接显示数字端口，不解析为服务名 |
| `-t` | 只显示 TCP 协议 |
| `-p` | 显示使用该端口的进程信息 |

```bash
ss -lntp | grep 3306
# = 查看 TCP 监听端口，筛选出 3306
```

### 7.3 MySQL 层级关系

```
MySQL 实例
    └── 数据库 (Database)  ← USE 数据库名;
            └── 数据表 (Table)  ← SHOW TABLES;
                    └── 数据 (Data)  ← SELECT * FROM 表名;
```

---

## 八、排错思路总结

```
客户端连不上
    ↓
检查服务是否运行 (systemctl status mysqld)
    ↓
检查端口是否监听 (ss -lntp | grep 3306)
    ↓
检查防火墙/安全组
    ↓
检查连接参数 (allowPublicKeyRetrieval, useSSL)
    ↓
检查用户名和密码
    ↓
检查数据库是否存在 (SHOW DATABASES;)
    ↓
检查数据表是否存在 (SHOW TABLES;)
    ↓
检查数据是否存在 (SELECT * FROM 表名;)
```

>  **核心原则**：根据报错位置，一层一层排查，不要一次性改多个配置。

---

## 九、已安装软件清单

| 软件 | 版本 | 状态 | 用途 |
|------|------|------|------|
| MySQL | 8.0.46 | ✅ 已装 | 关系型数据库 |
| DBeaver | - | ✅ 本地使用 | MySQL 图形化管理工具 |

---



*笔记时间：2026-08-23*
*系统环境：CentOS Linux release 7*
*MySQL 版本：8.0.46*
*本地工具：DBeaver*

--今天装了数据库 并决定使用DBeaver远程管理