# open-vpn-server

基于 Docker Compose 的 OpenVPN 服务端一键部署方案。适用于腾讯云、阿里云等云服务器，支持创建多用户账户并生成可直接导入 **OpenVPN Connect** 的 `.ovpn` 配置文件。

## 特性

- Docker Compose 部署，无需手动编译 OpenVPN
- 每用户独立客户端证书（CN = 用户名），账户隔离
- 兼容 OpenVPN Connect（macOS / iOS / Windows / Android），连接无需输入密码
- 提供账户创建、查看、删除脚本
- 支持证书吊销（CRL），删除账户后立即失效

## 快速开始

```bash
cd deploy
cp .env.example .env          # 编辑 OVPN_SERVER 为公网 IP
chmod +x scripts/*.sh
./scripts/init-server.sh      # 初始化服务端
./scripts/add-user.sh alice   # 创建账户，生成 clients/alice.ovpn
```

云安全组放行 **UDP 1194**，下载 `.ovpn` 导入客户端即可连接。

```bash
# 本地下载配置（示例）
scp root@<公网IP>:/path/to/deploy/clients/alice.ovpn ./
```

## 账户管理

| 操作 | 命令 |
|------|------|
| 创建账户 | `./scripts/add-user.sh <用户名>` |
| 查看账户 | `./scripts/list-users.sh` |
| 删除账户 | `./scripts/delete-user.sh <用户名>` |

> **多设备**：每台设备应使用独立账户（如 `alice-mac`、`alice-android`），同一 `.ovpn` 不能多设备同时在线。详见 [DEPLOY.md](./DEPLOY.md#多设备使用重要)。

## 目录结构

```
open-vpn-server/
├── README.md           # 本文件
├── DEPLOY.md           # 完整部署与故障排查文档
└── deploy/
    ├── docker-compose.yml
    ├── .env.example
    ├── scripts/        # 初始化与账户管理脚本
    ├── data/openvpn/   # PKI 与服务端配置（运行时生成，勿提交 Git）
    └── clients/        # 客户端 .ovpn（运行时生成，勿提交 Git）
```

## 文档

详细步骤（防火墙、NAT、故障排查等）请参阅 **[DEPLOY.md](./DEPLOY.md)**。

## 安全提示

- `.ovpn` 内含私钥，等同于账户凭证，请妥善保管
- `data/openvpn/` 含 CA 私钥，务必备份且勿提交到 Git
- 离职或不再使用时，执行 `./scripts/delete-user.sh` 吊销证书

## 环境要求

- Linux 云服务器（推荐 Ubuntu 22.04+）
- Docker 20.10+、Docker Compose v2
- 公网 IP，安全组放行 UDP 1194
