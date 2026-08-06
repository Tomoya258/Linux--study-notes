
# Linux 用户、用户组、权限管理学习笔记

日期：2026-08-06

---

# 一、Linux 文件权限基础

## 1. ls -l 查看文件权限

示例：

```bash
ls -l
````

输出：

```text
drwxr-xr-x 2 root root 22 7月27 15:59 devops
```

拆解：

```
d rwx r-x r-x root root devops
│ │   │   │    │    │
│ │   │   │    │    └── 文件/目录名
│ │   │   │    └────── 所属组(group)
│ │   │   └────────── 其他用户权限(other)
│ │   └────────────── 组用户权限(group)
│ └────────────────── 所有者权限(owner)
└──────────────────── 文件类型
```

---

# 二、chmod 权限管理

## 1. chmod 作用

`chmod`：

> change mode，修改访问权限

管理：

* 用户能不能读
* 用户能不能写
* 用户能不能执行

不会改变文件属于谁。

---

# 2. rwx 权限含义

三个权限：

| 字母 | 含义         |
| -- | ---------- |
| r  | read 读     |
| w  | write 写    |
| x  | execute 执行 |

---

# 3. 数字权限原理

Linux 使用八进制表示权限：

```
r = 4
w = 2
x = 1
```

权限数字就是相加：

| 数字 | 二进制 | 权限  |
| -- | --- | --- |
| 0  | 000 | --- |
| 1  | 001 | --x |
| 2  | 010 | -w- |
| 3  | 011 | -wx |
| 4  | 100 | r-- |
| 5  | 101 | r-x |
| 6  | 110 | rw- |
| 7  | 111 | rwx |

---

例如：

```bash
chmod 755 test
```

等价：

```
rwx r-x r-x
```

拆分：

```
7 = 4+2+1 = rwx
5 = 4+1   = r-x
5 = 4+1   = r-x
```

注意：

```
5 不是 r+w

5 = r+x
```

---

# 三、chown 所有权管理

## 1. chown 作用

`chown`：

> change owner，修改文件所有者

管理：

* 文件属于哪个用户
* 文件属于哪个组

---

# 2. chown 基本格式

```bash
chown 用户:组 文件
```

例如：

```bash
chown devops:dev dev
```

表示：

```
用户改为 devops
组改为 dev
```

---

## 3. 只修改组

```bash
chown :dev dev
```

表示：

只修改 group：

```
root:root

变成

root:dev
```

---

## 4. 递归修改

```bash
chown -R devops:dev /home/devops
```

含义：

递归修改目录里面所有文件：

```
/home/devops
├── .bashrc
├── test
└── file.txt
```

全部变成：

```
devops:dev
```

---

# 四、chmod 和 chown 的区别

一句话：

```
chmod 管权限
chown 管归属
```

---

## chmod 回答：

> 谁可以做什么？

例如：

```bash
chmod 755 test
```

结果：

```
owner:
rwx

group:
r-x

other:
r-x
```

---

## chown 回答：

> 这个东西是谁的？

例如：

```bash
chown devops:dev test
```

结果：

```
所有者:
devops

组:
dev
```

---

# 五、用户管理

## 1. 创建用户

```bash
useradd 用户名
```

例如：

```bash
useradd devops
```

---

注意：

创建用户 ≠ 设置密码

---

# 2. 设置密码

```bash
passwd 用户名
```

例如：

```bash
passwd devops
```

---

如果没有设置密码：

执行：

```bash
su - devops
```

会出现：

```
su: 鉴定故障
```

原因：

用户没有可用密码。

---

# 六、user 和 group 的关系

查看用户信息：

```bash
id 用户名
```

例如：

```bash
id devops
```

结果：

```
uid=1000(devops)
gid=1001(dev)
groups=1001(dev)
```

表示：

```
用户:
devops

主组:
dev
```

---

# 七、su 用户切换

## root 切换普通用户

```bash
su - devops
```

通常不需要密码。

---

## 普通用户切换其他用户

例如：

```
devops -> jac
```

需要输入：

```
jac 的密码
```

---

# 八、/etc/skel 用户模板目录

## 作用

创建新用户时：

系统会复制：

```
/etc/skel/*
```

到：

```
/home/用户名
```

例如：

```
/etc/skel
├── .bashrc
├── .bash_profile
└── .bash_logout
```

---

# 九、遇到的问题总结

---

## 问题1：chmod 写法错误

错误：

```bash
chmod u=rw,g+rx,o= test
```

原因：

参数之间不能有错误空格。

chmod 会把后面的内容当文件名。

---

正确：

```bash
chmod u=rw,g+rx,o= test
```

---

# 问题2：id devops 提示不存在

执行：

```bash
id devops
```

结果：

```
no such user
```

原因：

/opt/devops 是目录，不是用户。

目录名和用户名没有关系。

---

# 问题3：useradd devops 警告

提示：

```
此主目录已经存在。
不从 skel 目录里向其中复制任何文件。
```

原因：

```
/home/devops
```

已经存在。

所以：

```
/etc/skel
        |
        X
        |
/home/devops
```

没有复制默认配置。

---

解决：

复制模板：

```bash
cp -a /etc/skel/. /home/devops/
```

修改归属：

```bash
chown -R devops:dev /home/devops
```

---

# 问题4：su - jac 失败

现象：

```bash
su - jac
```

出现：

```
su: 鉴定故障
```

原因：

用户创建了：

```bash
useradd jac
```

但是没有设置密码。

解决：

```bash
passwd jac
```

---

# 十、今天完整实验流程总结

## 创建用户

```bash
useradd devops
useradd jac
useradd jack
```

---

## 创建组

```bash
groupadd dev
```

---

## 修改用户主组

```bash
usermod -g dev devops
```

---

## 创建目录

```bash
mkdir /opt/dev
```

---

## 修改目录组

```bash
chown :dev /opt/dev
```

---

## 修改目录所有者和组

```bash
chown devops:dev /opt/dev
```

---

## 修改权限

```bash
chmod 755 /opt/dev
```

最终：

```
目录:
 /opt/dev

所有者:
 devops

组:
 dev

权限:
 rwxr-xr-x
```

---

# 十一、核心记忆

## chmod

```
改变权限

谁能做什么？
```

例：

```
755

用户:
rwx

组:
r-x

其他:
r-x
```

---

## chown

```
改变归属

这个东西是谁的？
```

例：

```
devops:dev

用户:
devops

组:
dev
```

---

## Linux 权限管理核心模型

```
文件/目录

        属主(user)
             |
             |
        属组(group)
             |
             |
        权限(rwx)
```

记住：

```
chown → 分配主人
chmod → 设置能力
passwd → 设置登录密码
su → 切换身份
id → 查看身份信息
```
