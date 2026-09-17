# Ubuntu Server 安装、SSH、固定 IP 与用户权限学习笔记

日期：2026-09-16 ～ 2026-09-18  
环境：Windows、VMware Workstation、Ubuntu Server 26.04、WindTerm / Windows OpenSSH  
虚拟机名称：`ubuntu-server-01`  
普通用户：`admin01`

---

## 一、本阶段完成的内容

本阶段完成了以下工作：

1. 下载 Ubuntu Server ISO，并在 VMware 中创建 Ubuntu Server 虚拟机。
2. 处理安装过程中 Ubuntu 软件镜像源检测失败的问题。
3. 安装 Ubuntu Server 26.04，并启用 OpenSSH Server。
4. 从 Windows 通过 SSH 登录 Ubuntu。
5. 排查 WindTerm 显示 `OSC 3008` 控制字符的问题。
6. 查看 VMware NAT、DHCP、网关和 Ubuntu 网卡信息。
7. 将 Ubuntu 地址从 DHCP 动态地址改为静态地址。
8. 排查 Netplan 的 YAML 格式错误、命令拼写错误和网络不可达问题。
9. 理解私有 IP、公网访问和服务器项目入口之间的关系。
10. 学习 Linux 用户、UID、root 和 sudo 的基本区别。

最终 Ubuntu 的固定 IPv4 地址为：

```text
192.168.136.10/24
```

VMware NAT 网关为：

```text
192.168.136.2
```

---

## 二、创建 Ubuntu Server 虚拟机

### 2.1 ISO 镜像是什么

创建虚拟机需要 Ubuntu Server 的 ISO 镜像文件。ISO 可以理解为一张虚拟安装光盘，VMware 会通过它启动 Ubuntu 安装程序。

本次实际安装的是 Ubuntu Server 26.04，安装器日志中显示的发行版代号为：

```text
resolute
```

镜像文件名通常类似：

```text
ubuntu-26.04-live-server-amd64.iso
```

其中 `amd64` 表示常见的 x86-64 处理器架构，Intel 和 AMD 的普通 64 位电脑通常都使用这一版本。

### 2.2 VMware 初始配置

本地电脑有 32GB 内存。为了后续练习 Java、MySQL、Redis、Nginx 等服务，Ubuntu 虚拟机可以使用：

```text
CPU：1 个处理器、4 个内核
内存：8GB
磁盘：60GB 左右
网络：NAT
```

VMware 中“1 个处理器、4 个内核”表示总共 4 个虚拟 CPU。如果设置成“4 个处理器、每个处理器 4 核”，总数会变成 16 个虚拟 CPU。

虚拟磁盘设置为 60GB，一般不代表立即占用 60GB，磁盘文件通常会随着实际使用逐渐增长。

### 2.3 安装时的主要选择

安装过程中使用了以下思路：

- 安装 Ubuntu Server，不安装桌面环境。
- 网络使用 VMware NAT 和 DHCP 自动配置。
- 磁盘选择整块虚拟磁盘。
- 创建普通用户 `admin01`。
- 主机名设置为 `ubuntu-server-01`。
- 勾选安装 OpenSSH Server。
- 暂时不选择额外的软件套装，后续根据项目需要自己安装。

Ubuntu 默认更推荐使用普通用户登录，再通过 `sudo` 执行管理命令，而不是直接用 root 登录。

---

## 三、安装时软件镜像源检测失败

### 3.1 遇到的现象

安装器在 Ubuntu archive mirror configuration 阶段检测镜像源失败，日志中出现：

```text
403 Forbidden
Mirror check failed
```

当时使用的地址与国内 Ubuntu 镜像有关。`403 Forbidden` 表示服务器收到了请求，但拒绝提供相应内容。

安装器提示，如果继续安装，只会使用 ISO 安装介质中已有的软件包；安装完成后需要再检查软件源并安装更新。

### 3.2 可采用的处理方式

可以尝试改用官方地址：

```text
https://archive.ubuntu.com/ubuntu/
```

也可以尝试其他可用镜像，例如：

```text
https://mirrors.aliyun.com/ubuntu/
```

如果安装器仍然无法检查镜像，可以选择继续，先使用 ISO 中的软件完成基础安装。进入系统后再执行：

```bash
sudo apt update
```

这条命令用于重新下载软件仓库的包索引，不会直接升级所有已安装的软件。

需要注意：本次对话没有记录安装完成后 `apt update` 的最终输出，因此后续部署项目前仍需确认软件源可以正常使用。

---

## 四、安装完成、重启和 SSH 连接

### 4.1 安装内核

安装界面显示：

```text
kernel installing
```

表示安装器正在安装 Linux 内核和基础系统。这一阶段应等待完成，不要关闭虚拟机或断开 ISO。

完成后选择：

```text
Reboot Now
```

如果提示移除安装介质，可以在 VMware 中断开虚拟 CD/DVD，再按回车。

如果重启后又进入安装界面，说明虚拟机仍然从 ISO 启动。可以关闭虚拟机，在 CD/DVD 设置中取消“启动时连接”，然后重新启动。

### 4.2 检查 Ubuntu 地址

登录 Ubuntu 后，可以执行：

```bash
ip addr
```

或者简洁查看地址：

```bash
hostname -I
```

本次初始 DHCP 地址为：

```text
192.168.136.135
```

### 4.3 检查 SSH 服务

```bash
systemctl status ssh --no-pager
```

参数含义：

- `systemctl`：管理 systemd 服务。
- `status`：查看服务状态。
- `ssh`：Ubuntu 中 OpenSSH Server 的服务名。
- `--no-pager`：直接输出，不进入分页查看器。

如果看到：

```text
Active: active (running)
```

表示 SSH 服务正在运行。

Ubuntu 中常见服务名是 `ssh`，而 CentOS 中常见的是 `sshd`。

### 4.4 从 Windows 登录

WindTerm、Xshell 等客户端需要填写：

```text
协议：SSH
地址：192.168.136.135（当时的 DHCP 地址）
端口：22
用户：admin01
密码：安装 Ubuntu 时设置的 admin01 密码
```

Windows 自带 OpenSSH 也可以连接：

```powershell
ssh admin01@192.168.136.135
```

密码输入时终端不显示星号或字符，这是正常的安全设计。

---

## 五、WindTerm 显示 OSC 3008 字符

### 5.1 现象

通过 WindTerm 登录 Ubuntu 后，命令前后出现大量内容，例如：

```text
[ESC]3008;start=...
machineid=...
user=admin01
hostname=ubuntu-server-01
type=command
cwd=/home/admin01
```

真正的 Bash 提示符仍然是：

```text
admin01@ubuntu-server-01:~$
```

这些内容不是主机名，也不是 Ubuntu 命令报错，而是终端控制序列。

### 5.2 OSC 3008 的用途

Ubuntu 26.04 中的 systemd Shell 集成会发送 OSC 3008 标记，用来告诉终端：

- Shell 会话何时开始。
- 一条命令何时开始和结束。
- 命令是否执行成功。
- 当前用户、主机和工作目录。

支持该协议的终端会读取并隐藏这些内容。当前版本的 WindTerm 没有正确处理，所以将它们直接显示出来。

### 5.3 查找来源

执行：

```bash
grep -RnsE '3008|osc|OSC|shell.integration' /etc/profile /etc/bash.bashrc /etc/profile.d ~/.bashrc ~/.profile 2>/dev/null
```

主要参数：

- `grep`：搜索文字。
- `-R`：递归搜索目录。
- `-n`：显示行号。
- `-s`：不显示部分错误信息。
- `-E`：启用扩展匹配，`|` 表示“或者”。
- `2>/dev/null`：隐藏错误输出。

最终定位到：

```text
/etc/profile.d/80-systemd-osc-context.sh
```

查看完整脚本：

```bash
sed -n '1,110p' /etc/profile.d/80-systemd-osc-context.sh
```

其中：

- `sed`：处理文本。
- `-n`：不自动输出全部内容。
- `1,110p`：只显示第 1～110 行。

脚本中的两个关键位置是：

```bash
PROMPT_COMMAND+=(__systemd_osc_context_precmdline)
PS0='$(__systemd_osc_context_ps0)'
```

它们让 Bash 在显示提示符前、执行命令前调用相应函数，并输出 OSC 3008 内容。

### 5.4 用 Windows 自带 SSH 对比

使用 Windows 自带 SSH 登录后执行：

```bash
pwd
ls
ls -la
```

显示完全正常，没有出现 `3008` 字符。这证明：

- Ubuntu 系统本身正常。
- SSH 服务正常。
- 问题主要是 WindTerm 与 OSC 3008 的显示兼容性。

### 5.5 临时关闭输出

在当前 Shell 中执行：

```bash
__systemd_osc_context_precmdline() { :; }; __systemd_osc_context_ps0() { :; }
```

这是重新定义两个同名 Shell 函数：

```bash
函数名() {
    :
}
```

Shell 中的 `:` 表示什么也不做并返回成功。因此，系统调用这两个函数时不再打印控制字符。

这个修改只在当前 SSH 会话中有效，重新登录后会恢复。

### 5.6 对当前用户永久生效

先备份用户配置：

```bash
cp -p ~/.profile ~/.profile.bak-$(date +%Y%m%d-%H%M%S)
```

然后编辑：

```bash
nano ~/.profile
```

在文件末尾添加：

```bash
# Disable OSC 3008 output for terminal compatibility.
if [ -n "${BASH_VERSION:-}" ]; then
    __systemd_osc_context_precmdline() { :; }
    __systemd_osc_context_ps0() { :; }
fi
```

Nano 保存操作：

```text
Ctrl+O → 回车 → Ctrl+X
```

含义分别是：

- `Ctrl+O`：写入文件。
- 回车：确认当前文件名。
- `Ctrl+X`：退出 Nano。

重新连接 WindTerm 后，不再显示 OSC 3008 字符。

这项修改只影响 `admin01` 用户的终端上下文标记，不影响 SSH、系统服务和普通命令执行。

---

## 六、为什么需要固定服务器 IP

初始地址由 DHCP 自动分配：

```text
192.168.136.135
```

通过下面的输出可以确认：

```text
inet 192.168.136.135/24 ... scope global dynamic ens33
```

其中 `dynamic` 表示动态地址。

DHCP 地址可能在重启、租约变化或网络环境变化后改变。一旦改变，以下配置都可能需要修改：

- WindTerm、Xshell、Xftp 保存的服务器地址。
- 浏览器访问项目的地址。
- Nginx、监控工具或其他服务器中的目标地址。

所以长期作为本地项目服务器时，固定地址更方便。

---

## 七、查看 VMware NAT 和 DHCP 参数

### 7.1 VMware 虚拟网络设置

在 VMware 的“编辑 → 虚拟网络编辑器”中查看 VMnet8，得到：

| 项目 | 实际值 |
|---|---|
| 网络模式 | NAT |
| 网络名称 | VMnet8 |
| 子网地址 | `192.168.136.0` |
| 子网掩码 | `255.255.255.0` |
| NAT 网关 | `192.168.136.2` |
| DHCP 起始地址 | `192.168.136.128` |
| DHCP 结束地址 | `192.168.136.254` |
| Windows VMnet8 地址 | `192.168.136.1` |

### 7.2 当前网络关系

```text
Windows VMnet8：192.168.136.1
        │
        ├── Ubuntu 虚拟机：原 DHCP 地址 192.168.136.135
        │
        └── VMware NAT 网关：192.168.136.2
                                  │
                                  └── 外部网络
```

### 7.3 为什么选择 192.168.136.10

固定地址选择为：

```text
192.168.136.10
```

原因：

1. 它属于 `192.168.136.0/24` 网段。
2. 不在 DHCP 自动分配的 `.128～.254` 范围内。
3. 避开了 Windows VMnet8 的 `.1`。
4. 避开了 VMware NAT 网关 `.2`。
5. 没有使用网络地址 `.0` 和广播地址 `.255`。

直接把原来的 `.135` 设置为静态地址不够稳妥，因为 `.135` 位于 DHCP 地址池中，未来可能被 DHCP 分配给其他虚拟机，引起 IP 冲突。

---

## 八、固定 IP 前的只读检查

### 8.1 查看网卡 IPv4 地址

```bash
ip -4 addr show ens33
```

解释：

- `ip`：查看和管理 Linux 网络。
- `-4`：只显示 IPv4。
- `addr`：查看地址。
- `show ens33`：只查看 `ens33` 网卡。

当时输出包含：

```text
inet 192.168.136.135/24 metric 100 brd 192.168.136.255 scope global dynamic ens33
```

关键含义：

- `192.168.136.135`：当前地址。
- `/24`：子网前缀，对应 `255.255.255.0`。
- `brd 192.168.136.255`：广播地址。
- `dynamic`：地址来自 DHCP。
- `ens33`：网卡名。

### 8.2 查看路由

```bash
ip route
```

当时输出包含：

```text
default via 192.168.136.2 dev ens33 proto dhcp src 192.168.136.135 metric 100
192.168.136.0/24 dev ens33 proto kernel scope link src 192.168.136.135 metric 100
192.168.136.2 dev ens33 proto dhcp scope link src 192.168.136.135 metric 100
```

核心理解：

- `default via 192.168.136.2`：访问其他网络时把数据交给 `.2` 网关。
- `dev ens33`：使用 `ens33` 网卡发送。
- `src 192.168.136.135`：当时使用 `.135` 作为源地址。
- `proto dhcp`：该路由来自 DHCP 配置。

### 8.3 找到 Netplan 文件

```bash
ls -l /etc/netplan/
```

得到：

```text
00-installer-config.yaml
```

Ubuntu 使用 Netplan 管理网络，配置文件位于：

```text
/etc/netplan/
```

### 8.4 查看原配置

```bash
sudo cat /etc/netplan/00-installer-config.yaml
```

原始内容为：

```yaml
# This is the network config written by 'subiquity'
network:
  ethernets:
    ens33:
      dhcp4: true
      dhcp6: true
      match:
        macaddress: 00:0c:29:cc:c7:17
      set-name: ens33
  version: 2
```

其中：

```yaml
dhcp4: true
```

表示 IPv4 地址由 DHCP 自动获取。

---

## 九、修改 Netplan 固定 IP

### 9.1 为什么要使用 VMware 控制台

WindTerm 和 Windows OpenSSH 都通过网络连接 Ubuntu。切换 IP 时，原来的 SSH 连接会断开。

VMware 控制台是 VMware 中直接显示 Ubuntu 屏幕的窗口，它不依赖虚拟机的网络。即使 IP 配置错误，仍然能通过控制台登录并恢复配置。

所以修改网络时应保持 VMware 控制台可用。

### 9.2 修改前备份

正确命令：

```bash
sudo cp -p /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
```

解释：

- `sudo`：以管理员权限执行。
- `cp`：复制文件。
- `-p`：尽量保留原文件权限、所有者和时间。
- 第一个路径：原配置。
- 第二个路径：备份配置。

验证：

```bash
ls -l /etc/netplan/
```

应该能看到：

```text
00-installer-config.yaml
00-installer-config.yaml.bak
```

#### 遇到的问题：反斜杠使用错误

第一次输入成了类似：

```bash
sudo cp -p /etc/netplan/00-installer-config.yaml \ /etc/netplan/00-installer-config.yaml.bak
```

出现：

```text
cp: cannot create regular file ... No such file or directory
```

原因：反斜杠 `\` 用于表示命令在下一行继续，它必须是当前行最后一个字符。`\` 后面不能再跟空格和目标路径。

正确的跨行写法是：

```bash
sudo cp -p /etc/netplan/00-installer-config.yaml \
/etc/netplan/00-installer-config.yaml.bak
```

初学阶段直接写成一行更清楚：

```bash
sudo cp -p /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
```

### 9.3 `.yaml` 和 `.bak` 的含义

```text
00-installer-config.yaml
```

`.yaml` 表示 YAML 格式配置文件。Netplan 会读取 `/etc/netplan/` 下以 `.yaml` 结尾的正式配置。

```text
00-installer-config.yaml.bak
```

`.bak` 是 `backup` 的缩写，表示人工创建的备份。文件里面仍然是 YAML 内容，但因为最后以 `.bak` 结尾，Netplan 通常不会把它作为正式配置加载。

当前只需要记住：

```text
.yaml = 当前正式配置
.bak  = 修改前的备用副本
```

### 9.4 使用 Nano 打开文件

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

解释：

- `sudo`：获得修改 `/etc` 配置所需的权限。
- `nano`：启动 Nano 文本编辑器。
- 后面是需要修改的文件路径。

Nano 打开后可以直接用方向键移动光标、退格删除并输入文字，不需要像 Vim 一样先按 `i`。

常用按键：

| 按键 | 用途 |
|---|---|
| `Ctrl+O` | 保存 |
| 回车 | 确认保存到当前文件名 |
| `Ctrl+X` | 退出 |
| `Ctrl+W` | 搜索 |
| `Ctrl+K` | 剪切当前行 |
| `Ctrl+U` | 粘贴剪切内容 |

如果还没有保存并且想放弃修改，可以按 `Ctrl+X`，在是否保存时选择 `N`。

### 9.5 最终静态配置

配置修改为：

```yaml
# This is the network config written by 'subiquity'
network:
  ethernets:
    ens33:
      dhcp4: false
      dhcp6: true
      addresses:
        - 192.168.136.10/24
      routes:
        - to: default
          via: 192.168.136.2
      nameservers:
        addresses:
          - 192.168.136.2
      match:
        macaddress: 00:0c:29:cc:c7:17
      set-name: ens33
  version: 2
```

### 9.6 重点配置解释

```yaml
dhcp4: false
```

关闭 IPv4 DHCP，不再自动获取 IPv4 地址。

```yaml
addresses:
  - 192.168.136.10/24
```

给 `ens33` 配置固定地址 `.10`。`/24` 对应子网掩码 `255.255.255.0`。

```yaml
routes:
  - to: default
    via: 192.168.136.2
```

设置默认路由。访问本地网段以外的地址时，把数据交给 VMware NAT 网关 `.2`。

```yaml
nameservers:
  addresses:
    - 192.168.136.2
```

设置 DNS 地址。VMware 的 NAT 网关可以帮助虚拟机转发 DNS 查询。

```yaml
match:
  macaddress: 00:0c:29:cc:c7:17
set-name: ens33
```

根据网卡 MAC 地址匹配真实设备，并将它命名为 `ens33`。这是安装器原来生成的内容，本次保留不变。

```yaml
version: 2
```

表示使用 Netplan 配置格式版本 2。

### 9.7 YAML 格式注意事项

YAML 依赖缩进表示层级：

- 使用空格，不要使用 Tab。
- 同一层级必须对齐。
- 冒号后通常要有空格。
- 列表项的短横线后必须有空格。

例如正确列表：

```yaml
addresses:
  - 192.168.136.2
```

错误写法：

```yaml
addresses:
  -192.168.136.2
```

---

## 十、检查并应用 Netplan

### 10.1 检查配置格式

```bash
sudo netplan generate
```

`generate` 会读取 YAML 配置并生成底层网络配置。没有输出通常表示格式检查通过，但并不代表地址、网关和 DNS 一定都能正常通信。

### 10.2 遇到的 YAML 错误

第一次检查出现：

```text
/etc/netplan/00-installer-config.yaml:14:12: Error in network definition: expected sequence
    -192.168.136.2
```

原因是写成了：

```yaml
-192.168.136.2
```

短横线后缺少空格。Netplan 期望这里是一个 YAML 列表，所以报 `expected sequence`。

修正为：

```yaml
- 192.168.136.2
```

保存后重新执行：

```bash
sudo netplan generate
```

### 10.3 安全试用网络配置

在 VMware 控制台中执行：

```bash
sudo netplan try --timeout 120
```

解释：

- `netplan`：Ubuntu 网络配置工具。
- `try`：临时试用新配置。
- `--timeout 120`：等待确认 120 秒。

执行后：

1. Ubuntu 临时切换到 `.10`。
2. 原来的 `.135` SSH 连接可能断开。
3. 系统等待确认。
4. 新网络正常时按回车确认。
5. 如果没有确认，超时后 Netplan 会尝试恢复原配置。

### 10.4 遇到的问题：把 `try` 写成 `tey`

第一次输入成了：

```bash
sudo netplan tey
```

`tey` 不是 Netplan 的有效子命令，所以配置没有应用。终端当时已经提示命令错误，但由于 VMware 控制台显示比较密集，没有及时注意。

随后在 Windows 测试 `.10`：

```powershell
ping 192.168.136.10
```

出现：

```text
来自 192.168.136.1 的回复：无法访问目标主机。
请求超时。
```

这里的 `.1` 是 Windows 的 VMnet8 虚拟网卡。它找不到 `.10`，因为 Ubuntu 实际仍然使用原来的 `.135`。

修正命令：

```bash
sudo netplan try --timeout 120
```

确认后固定地址成功生效。

这次排错的重要经验是：

```text
输入命令 → 看命令是否报错 → 再检查配置是否真正生效
```

不能只完成“输入命令”这一步。

---

## 十一、验证固定 IP

### 11.1 查看地址

```bash
ip -4 addr show ens33
```

预期看到：

```text
inet 192.168.136.10/24
```

### 11.2 查看路由

```bash
ip route
```

预期关键内容类似：

```text
default via 192.168.136.2 dev ens33
192.168.136.0/24 dev ens33 scope link src 192.168.136.10
```

分别表示：

- 默认网关为 `.2`。
- 本地网段使用 `.10` 作为源地址。

### 11.3 测试 VMware 网关

```bash
ping -c 4 192.168.136.2
```

- `ping`：发送 ICMP 请求，测试可达性。
- `-c 4`：只发送 4 次。

网关不通时，应先检查 IP、掩码、网卡和 VMware 网络设置。

### 11.4 测试公网 IP

```bash
ping -c 4 223.5.5.5
```

这是直接访问 IP，不依赖 DNS。若网关能通但公网 IP 不通，需要检查默认路由、VMware NAT 服务或 Windows 网络。

### 11.5 测试 DNS

```bash
ping -c 4 ubuntu.com
```

使用域名时需要 DNS 先将域名解析为 IP。

判断思路：

| 结果 | 可能方向 |
|---|---|
| 网关不通 | 地址、掩码、网卡、VMware 网络 |
| 网关通，公网 IP 不通 | 默认路由或 NAT |
| 公网 IP 通，域名不能解析 | DNS 配置 |
| 都能正常访问 | 基础网络正常 |

个别网站可能禁止响应 ping，因此还应结合是否成功解析出 IP 判断。

### 11.6 Windows 测试 SSH 端口

```powershell
Test-NetConnection 192.168.136.10 -Port 22
```

重点查看：

```text
TcpTestSucceeded : True
```

`ping` 测试 ICMP，而这条命令测试真实需要使用的 TCP 22 端口。即使某些环境禁止 ping，SSH 端口仍可能正常。

使用新地址登录：

```powershell
ssh admin01@192.168.136.10
```

WindTerm、Xshell、Xftp 中保存的目标地址也应统一改为：

```text
192.168.136.10
```

### 11.7 重启验证

```bash
sudo reboot
```

服务器重启时 SSH 会断开，这是正常现象。系统启动后重新连接：

```powershell
ssh admin01@192.168.136.10
```

再次检查：

```bash
ip -4 addr show ens33
ip route
```

如果重启后仍然使用 `.10`，说明固定配置持久生效。

---

## 十二、配置错误时如何恢复

在 VMware 控制台中执行：

```bash
sudo cp -p /etc/netplan/00-installer-config.yaml.bak /etc/netplan/00-installer-config.yaml
```

这会使用备份内容覆盖当前正式配置。

然后先检查：

```bash
sudo netplan generate
```

再安全试用：

```bash
sudo netplan try --timeout 120
```

恢复原 DHCP 配置后，Ubuntu 会重新申请地址，不保证仍然获得之前的 `.135`。

---

## 十三、私有 IP 与公网访问

### 13.1 192.168.136.10 是谁的地址

```text
192.168.136.10
```

是 Ubuntu 虚拟机在 VMnet8 私有网络中的地址，不是 Windows 的地址。

当前关系：

```text
Windows VMnet8：192.168.136.1
VMware 网关：   192.168.136.2
Ubuntu VM：     192.168.136.10
```

`192.168.x.x` 属于私有地址，互联网不会直接路由到它。因此外部设备不能直接通过互联网访问：

```text
http://192.168.136.10
```

### 13.2 云服务器项目的正常访问方式

项目部署到阿里云后，典型关系是：

```text
互联网用户
    │
    ▼
域名或云服务器公网 IP
    │
    ▼
云安全组和系统防火墙
    │
    ▼
Nginx：80 / 443
    │
    ▼
Java 后端
    │
    ├── MySQL
    └── Redis
```

外部用户访问的是公网 IP 或域名。Nginx 作为公开入口，MySQL、Redis 等服务继续只在本机或私有网络中使用。

### 13.3 本地 VMware 项目如何供公网访问

如果以后希望互联网访问家里的虚拟机，可能需要：

```text
互联网
  ↓
家庭宽带公网 IP
  ↓ 路由器端口映射
Windows 宿主机
  ↓ VMware NAT 端口转发
Ubuntu：192.168.136.10
```

还会涉及公网 IP、运营商 NAT、路由器映射、Windows 防火墙、Ubuntu 防火墙、动态域名和服务器安全等问题。

目前更合适的安排是：

- 本地 Ubuntu VM 作为测试服务器。
- Windows 通过 `192.168.136.10` 访问测试项目。
- 项目本地跑通后，再复现到阿里云。
- 云服务器通过公网 IP 或域名供外部访问。

程序监听 `0.0.0.0` 只代表监听服务器所有本地网卡，不代表它自动获得了公网访问能力。

---

## 十四、Linux 如何区分不同用户

### 14.1 用户名和 UID

Linux 中可以同时存在：

```text
root
admin01
mysql
www-data
```

人主要使用用户名，Linux 内核主要使用 UID 区分用户：

```text
root     → UID 0
admin01  → 通常是 UID 1000
```

查看当前用户：

```bash
whoami
```

查看 UID、GID 和所属用户组：

```bash
id
```

查看所属用户组：

```bash
groups
```

查看用户账户记录：

```bash
getent passwd admin01
```

输出中会包含用户的 UID、主目录和登录 Shell。用户密码不会以明文保存在 `/etc/passwd` 中。

### 14.2 文件和进程属于用户

执行：

```bash
touch test.txt
ls -l test.txt
```

可能看到：

```text
-rw-r--r-- 1 admin01 admin01 0 ... test.txt
```

两个 `admin01` 分别表示文件所有者和所属组。

Linux 中运行的进程也有自己的用户身份。例如：

- MySQL 常使用 `mysql` 用户。
- Nginx 工作进程在 Ubuntu 上常使用 `www-data` 用户。
- Elasticsearch 使用自己的服务用户。

这样即使某个服务出现问题，它默认也不会拥有整个系统的最高权限。

### 14.3 root 用户

root 是超级用户：

```text
用户名：root
UID：0
```

root 可以修改系统配置、安装软件、管理用户和服务，并访问大多数文件。

普通用户提示符通常以 `$` 结尾：

```text
admin01@ubuntu-server-01:~$
```

root 提示符通常以 `#` 结尾：

```text
root@ubuntu-server-01:~#
```

### 14.4 sudo 使用谁的密码

执行：

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

系统会检查 `admin01` 是否有 sudo 权限。默认提示：

```text
[sudo] password for admin01:
```

这里输入的是 `admin01` 自己的登录密码，不是 root 密码。

流程是：

```text
admin01 执行 sudo
        ↓
检查 admin01 是否有 sudo 权限
        ↓
验证 admin01 自己的密码
        ↓
以 root 权限运行指定命令
```

查看自己是否属于 sudo 组：

```bash
groups
getent group sudo
```

查看当前账号允许执行哪些 sudo 命令：

```bash
sudo -l
```

### 14.5 root 密码与 sudo 的区别

| 操作 | 通常验证的密码 |
|---|---|
| `sudo 命令` | 当前用户自己的密码 |
| `su -` | root 密码 |
| SSH 登录 `admin01` | `admin01` 的密码 |
| SSH 登录 root | root 凭据，并且 SSH 必须允许 root 登录 |

Ubuntu 默认通常锁定 root 密码，并让管理员通过 sudo 工作。因此能够使用 sudo，不等于知道 root 密码。

只读检查 root 密码状态：

```bash
sudo passwd -S root
```

输出状态中的 `L` 通常表示 root 密码处于锁定状态。

如果 root 设置了有效密码，知道密码的人可能通过：

```bash
su -
```

切换到 root。但是否允许 root 通过 SSH 登录，还受 SSH 服务配置控制。

企业中更常见的方式是：每个人使用自己的账号登录，再根据职责授予 sudo 权限。这样更方便控制权限和审计操作。

---

## 十五、本阶段常用命令清单

### 系统与 SSH

```bash
cat /etc/os-release
uname -r
hostname -I
systemctl status ssh --no-pager
```

### 网络检查

```bash
ip -4 addr show ens33
ip route
ping -c 4 192.168.136.2
ping -c 4 223.5.5.5
ping -c 4 ubuntu.com
```

### Netplan

```bash
ls -l /etc/netplan/
sudo cat /etc/netplan/00-installer-config.yaml
sudo cp -p /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
sudo nano /etc/netplan/00-installer-config.yaml
sudo netplan generate
sudo netplan try --timeout 120
```

### Windows 测试

```powershell
ping 192.168.136.10
Test-NetConnection 192.168.136.10 -Port 22
ssh admin01@192.168.136.10
```

### 用户检查

```bash
whoami
id
groups
getent passwd admin01
getent group sudo
sudo -l
sudo passwd -S root
```

---

## 十六、本阶段遇到的问题与结论

| 问题 | 原因 | 解决办法 |
|---|---|---|
| 安装器镜像检测出现 `403 Forbidden` | 镜像服务器拒绝请求或仓库不可用 | 尝试官方或其他镜像，也可先使用 ISO 完成安装，安装后检查 `apt update` |
| WindTerm 显示大量 `3008` 内容 | WindTerm 未正确处理 systemd 的 OSC 3008 控制序列 | 确认来源后，在 `~/.profile` 中覆盖两个输出函数 |
| `cp` 提示目标目录不存在 | 错误地在反斜杠后加空格和路径 | 将复制命令写在同一行，或让 `\` 成为行末最后一个字符 |
| `netplan generate` 报 `expected sequence` | YAML 列表短横线后缺少空格 | 将 `-192...` 改为 `- 192...` |
| Windows 无法访问 `.10` | 将 `netplan try` 错写成 `netplan tey`，配置从未应用 | 正确执行 `sudo netplan try --timeout 120` 并确认 |
| SSH 切换 IP 后断开 | SSH 连接依赖旧 IP | 在 VMware 控制台操作，再使用新地址重新连接 |

---

## 十七、当前需要掌握到什么程度

固定 IP 的配置一次涉及 DHCP、子网、网关、DNS、YAML 和 Netplan，第一次觉得复杂是正常的。目前先掌握以下内容即可：

1. DHCP 自动分配的地址可能变化。
2. 静态 IPv4 需要地址、子网前缀、默认网关和 DNS。
3. 修改网络前先备份，并保留 VMware 控制台。
4. `netplan generate` 用于检查配置格式。
5. `netplan try` 用于安全试用配置。
6. 每条命令执行后都要查看有没有报错，并用 `ip`、`ping`、端口测试验证结果。
7. Ubuntu 的普通管理员通常通过 sudo 临时执行 root 权限命令。

本地 Ubuntu 现在已经具备稳定地址，可以继续进行软件源检查和项目部署准备。

