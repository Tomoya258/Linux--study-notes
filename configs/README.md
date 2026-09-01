# 服务器配置文件备份

本目录存放各服务器组件的配置文件，供环境重建时参考。

## 文件清单

| 文件名 | 用途 | 目标路径 |
|--------|------|----------|
| nginx.repo | Nginx 官方 yum 仓库配置 | /etc/yum.repos.d/ |

## 使用说明

将对应的 .repo 文件复制到 /etc/yum.repos.d/ 目录下，执行 yum repolist 验证。