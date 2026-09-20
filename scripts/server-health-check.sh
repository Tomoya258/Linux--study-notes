#!/usr/bin/env bash

# Linux 服务器基础信息采集脚本
# 只收集和显示状态，不自动修改或修复系统配置。

echo "======================================"
echo "        Linux 服务器基础检查"
echo "======================================"

echo
echo "===== 检查时间 ====="
date

echo
echo "===== 主机信息 ====="
hostnamectl --static 2>/dev/null || hostname
uptime

echo
echo "===== 系统版本 ====="
if [ -r /etc/os-release ]; then
    grep -E '^(PRETTY_NAME|VERSION_ID|VERSION_CODENAME)=' /etc/os-release
else
    uname -a
fi

echo
echo "===== IP 地址 ====="
ip -br addr

echo
echo "===== 路由表 ====="
ip route

echo
echo "===== DNS 配置 ====="
if command -v resolvectl >/dev/null 2>&1; then
    resolvectl status | grep -E 'DNS Servers|Current DNS Server' || true
elif [ -r /etc/resolv.conf ]; then
    cat /etc/resolv.conf
else
    echo "无法读取 DNS 配置"
fi

echo
echo "===== 内存 ====="
free -h

echo
echo "===== 磁盘 ====="
df -hT

echo
echo "===== CPU ====="
lscpu | grep -E '^(Architecture|CPU\(s\)|On-line CPU|Model name|NUMA node[0-9]+ CPU)'

echo
echo "===== SSH 服务 ====="
if systemctl list-unit-files ssh.service 2>/dev/null | grep -q '^ssh.service'; then
    echo -n "当前状态："
    systemctl is-active ssh
    echo -n "开机启动："
    systemctl is-enabled ssh
elif systemctl list-unit-files sshd.service 2>/dev/null | grep -q '^sshd.service'; then
    echo -n "当前状态："
    systemctl is-active sshd
    echo -n "开机启动："
    systemctl is-enabled sshd
else
    echo "未找到 ssh 或 sshd 服务"
fi

echo
echo "===== TCP 监听端口 ====="
if [ "$(id -u)" -eq 0 ]; then
    ss -lntp
else
    sudo -n ss -lntp 2>/dev/null || ss -lnt
fi

echo
echo "===== 防火墙 ====="
if command -v ufw >/dev/null 2>&1; then
    sudo -n ufw status verbose 2>/dev/null || \
        echo "无法无密码读取 UFW 状态，请手动执行：sudo ufw status verbose"
elif command -v firewall-cmd >/dev/null 2>&1; then
    sudo -n firewall-cmd --state 2>/dev/null && \
        sudo -n firewall-cmd --list-all 2>/dev/null || \
        echo "无法无密码读取 firewalld 状态，请手动使用 sudo 检查"
else
    echo "未检测到 ufw 或 firewalld"
fi

echo
echo "===== 时间同步 ====="
timedatectl 2>/dev/null || date
if command -v chronyc >/dev/null 2>&1; then
    echo
    echo "Chrony 当前跟踪状态："
    chronyc tracking 2>/dev/null | grep -E 'Reference ID|Stratum|System time|Leap status' || true
fi

echo
echo "===== 本次启动最近 20 条警告 ====="
journalctl -b -p warning --no-pager -n 20 2>/dev/null || \
    echo "无法读取 systemd 日志"

echo
echo "===== 检查完成 ====="
