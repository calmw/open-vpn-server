# OpenVPN Server 云服务器部署指南

本文档介绍如何在云服务器上使用 Docker Compose 部署 OpenVPN 服务端，创建带权限验证的 VPN 账户，并生成可供客户端直接导入的 `.ovpn` 配置文件。

## 架构说明

```
┌─────────────────┐         UDP 1194          ┌──────────────────────┐
│  VPN 客户端      │ ◄──────────────────────► │  云服务器             │
│  (.ovpn 导入)   │    TLS + 证书 + 账密       │  docker-compose      │
└─────────────────┘                           │  openvpn-server      │
                                              └──────────────────────┘
```

**安全模型（双重验证）：**

1. **客户端证书**：每个账户拥有独立的客户端证书（CN = 用户名）
2. **用户名 + 密码**：连接时需输入与证书 CN 一致的用户名及对应密码
3. **证书吊销**：可通过脚本吊销账户，立即失效

## 前置要求

| 项目 | 要求 |
|------|------|
| 云服务器 | Linux（推荐 Ubuntu 22.04+ / Debian 12+），1 核 1G 内存即可 |
| 公网 IP | 有固定公网 IP 或已解析到服务器的域名 |
| 软件 | Docker 20.10+、Docker Compose v2 |
| 防火墙 | 放行 UDP 1194（或你在 `.env` 中自定义的端口） |

## 目录结构

```
open-vpn-server/
├── DEPLOY.md                 # 本文档
└── deploy/
    ├── docker-compose.yml    # Docker Compose 编排
    ├── .env.example          # 环境变量模板
    ├── config/
    │   └── auth/
    │       ├── check-user.sh # 账密验证脚本（容器内调用）
    │       └── passwd        # 账户密码哈希（运行时生成，勿提交 Git）
    ├── scripts/
    │   ├── init-server.sh    # 初始化服务端
    │   ├── add-user.sh       # 创建账户并生成 .ovpn
    │   ├── revoke-user.sh    # 吊销账户
    │   └── list-users.sh     # 列出账户
    ├── data/                 # PKI 与服务端配置（运行时生成）
    └── clients/              # 客户端 .ovpn 文件（运行时生成）
```

## 一、安装 Docker（云服务器）

以 Ubuntu 为例：

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装 Docker
curl -fsSL https://get.docker.com | sudo sh

# 将当前用户加入 docker 组（重新登录后生效）
sudo usermod -aG docker "$USER"

# 验证
docker --version
docker compose version
```

## 二、上传部署文件

将本仓库克隆或上传到云服务器：

```bash
git clone <your-repo-url> open-vpn-server
cd open-vpn-server/deploy
```

或仅上传 `deploy/` 目录亦可。

## 三、配置环境变量

```bash
cd deploy
cp .env.example .env
```

编辑 `.env`，至少修改以下项：

```bash
# 云服务器公网 IP 或域名（客户端连接地址，不要加 udp:// 前缀）
OVPN_SERVER=203.0.113.10

# OpenVPN 监听端口
OVPN_PORT=1194

# VPN 内网网段（一般无需修改）
OVPN_SUBNET=192.168.255.0
```

> **注意**：`OVPN_SERVER` 必须填写客户端能访问到的公网地址，否则生成的 `.ovpn` 无法连接。

## 四、开放防火墙与安全组

### 云厂商安全组

在控制台入站规则中放行：

- 协议：**UDP**
- 端口：**1194**（与 `OVPN_PORT` 一致）
- 来源：`0.0.0.0/0`（或按需限制 IP 段）

### 服务器本地防火墙（如启用 ufw）

```bash
sudo ufw allow 1194/udp
sudo ufw reload
sudo ufw status
```

## 五、初始化 OpenVPN 服务端

```bash
cd deploy
chmod +x scripts/*.sh config/auth/check-user.sh
./scripts/init-server.sh
```

该脚本会依次执行：

1. 生成 OpenVPN 服务端配置（推送默认网关与 DNS）
2. 初始化 PKI（CA 证书、服务端证书、Diffie-Hellman 参数）
3. 启用 **证书 + 用户名密码** 双重验证
4. 启动 Docker 容器

> **若上次初始化中途失败**，需先清理不完整数据再重跑：
> ```bash
> rm -rf data/openvpn/*
> ./scripts/init-server.sh
> ```
>
> PKI 初始化阶段**无需手动输入**任何内容；若出现 `Common Name [OpenVPN-CA]:` 提示，说明脚本版本过旧，请更新后重试。

初始化成功后输出类似：

```
初始化完成！
  服务端地址: 203.0.113.10:1194/udp
  添加账户:   ./scripts/add-user.sh <用户名> [密码]
  客户端配置: deploy/clients/<用户名>.ovpn
```

### 常用运维命令

```bash
# 查看容器状态
docker compose ps

# 查看日志
docker compose logs -f openvpn

# 重启服务
docker compose restart openvpn

# 停止服务
docker compose down
```

## 六、创建 VPN 账户

### 交互式创建（推荐）

```bash
./scripts/add-user.sh alice
# 按提示输入密码（不回显）
```

### 命令行指定密码

```bash
./scripts/add-user.sh alice 'YourSecurePassword123'
```

### 脚本做了什么

1. 以 `alice` 为 CN 签发客户端证书
2. 将 `alice` 的密码 SHA256 哈希写入 `config/auth/passwd`
3. 生成 `clients/alice.ovpn`（已嵌入证书，并启用 `auth-user-pass`）

### 查看已有账户

```bash
./scripts/list-users.sh
```

### 吊销账户

```bash
./scripts/revoke-user.sh alice
```

吊销后该用户的证书进入 CRL，旧 `.ovpn` 立即无法连接。

## 七、客户端导入与连接

### 获取 .ovpn 文件

创建账户后，从服务器下载配置文件：

```bash
# 在本地电脑执行（替换 IP 和用户名）
scp root@203.0.113.10:~/open-vpn-server/deploy/clients/alice.ovpn ./
```

或通过 SFTP、云控制台等方式下载 `deploy/clients/<用户名>.ovpn`。

### 各平台导入方式

| 平台 | 客户端 | 导入步骤 |
|------|--------|----------|
| Windows | [OpenVPN Connect](https://openvpn.net/client/) | 导入 `.ovpn` 文件 → 连接时输入用户名和密码 |
| macOS | [OpenVPN Connect](https://openvpn.net/client/) 或 Tunnelblick | 双击 `.ovpn` 或拖入客户端 |
| iOS | App Store「OpenVPN Connect」 | 通过 AirDrop / 邮件 / Files 导入 |
| Android | Google Play「OpenVPN Connect」 | 导入 `.ovpn` 文件 |
| Linux | NetworkManager 或 `openvpn --config alice.ovpn` | 导入配置后连接 |

### 连接时的凭据

| 字段 | 填写内容 |
|------|----------|
| 用户名 | 创建账户时的用户名（如 `alice`） |
| 密码 | 创建账户时设置的密码 |

> 用户名必须与证书 CN 一致，这是 `username-as-common-name` 的安全策略。

## 八、验证 VPN 是否生效

连接成功后，在客户端执行：

```bash
# 查看是否获得 VPN 内网 IP（默认网段 192.168.255.x）
ip addr

# 测试外网（若配置了 redirect-gateway，流量会走 VPN）
curl ifconfig.me
```

在服务端查看在线客户端：

```bash
docker compose exec openvpn cat /tmp/openvpn-status.log
```

## 九、进阶配置

### 修改 VPN 内网网段

编辑 `.env` 中的 `OVPN_SUBNET`，**删除** `data/openvpn` 后重新执行 `./scripts/init-server.sh`（会重建 PKI，已有账户需重新创建）。

### 修改监听端口

1. 修改 `.env` 中 `OVPN_PORT`
2. 更新防火墙 / 安全组规则
3. 删除 `data/openvpn` 后重新初始化，或手动修改 `data/openvpn/openvpn.conf` 中的 `port` 并重启

### 仅路由特定网段（分流，不接管全部流量）

编辑 `data/openvpn/openvpn.conf`，注释掉初始化时写入的 `push "redirect-gateway ..."` 行，改为推送指定路由，例如：

```
push "route 10.0.0.0 255.0.0.0"
```

修改后执行 `docker compose restart openvpn`。

### 启用 IPv6

当前 Compose 已保留 IPv6 sysctl。如需完整 IPv6 支持，需在 `openvpn.conf` 中额外配置 `server-ipv6` 等参数，并确保云服务器有 IPv6 地址。

## 十、备份与恢复

**需要备份的目录：**

```bash
deploy/data/openvpn/    # PKI、CA 私钥、服务端配置（极其重要）
deploy/config/auth/passwd  # 账户密码哈希
```

备份示例：

```bash
tar czvf openvpn-backup-$(date +%Y%m%d).tar.gz data/openvpn config/auth/passwd
```

> **警告**：丢失 CA 私钥后，所有已签发的客户端证书将无法在新服务端上使用，必须重新初始化并重新分发 `.ovpn`。

## 十一、故障排查

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| 客户端一直连接中 | 安全组未放行 UDP 1194 | 检查云厂商安全组与 ufw |
| AUTH_FAILED | 用户名/密码错误或用户名与证书 CN 不一致 | 确认凭据；重新 `./scripts/add-user.sh` |
| TLS 握手失败 | `OVPN_SERVER` 填写错误 | 检查 `.env` 并重新生成客户端配置 |
| 能连上但无法上网 | 未开启 IP 转发或 NAT | 见下方「启用 IP 转发」 |
| 容器启动失败 | 端口被占用 | `ss -ulnp \| grep 1194` 检查 |

### 启用 IP 转发（云服务器必做）

OpenVPN 容器使用 `--net host` 模式以外的 bridge 网络时，宿主机需开启转发并做 NAT：

```bash
# 临时启用
sudo sysctl -w net.ipv4.ip_forward=1

# 永久启用
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-openvpn.conf
sudo sysctl --system

# NAT（将 eth0 替换为你的公网网卡名，可用 ip route 查看）
sudo iptables -t nat -A POSTROUTING -s 192.168.255.0/24 -o eth0 -j MASQUERADE
```

若使用 `ufw`，还需在 `/etc/ufw/before.rules` 中添加 NAT 规则，或使用 `iptables-persistent` 保存规则。

> **提示**：部分云镜像默认已开启 `ip_forward`；若客户端能获取 VPN IP 但无法访问外网，优先检查 NAT 规则。

## 十二、安全建议

1. **强密码**：账户密码建议 16 位以上，含大小写字母、数字和符号
2. **最小权限**：仅给需要的人员创建账户，离职立即 `revoke-user.sh`
3. **勿泄露 .ovpn**：配置文件内含私钥，等同于账户凭证
4. **定期备份** `data/openvpn`，并离线保存 CA 私钥
5. **限制 SSH**：云服务器仅允许密钥登录，禁用密码登录
6. **可选**：在安全组中将 UDP 1194 来源限制为可信 IP 段

## 快速命令参考

```bash
# 进入 deploy 目录
cd deploy

# 首次部署
cp .env.example .env && vim .env
./scripts/init-server.sh

# 创建账户
./scripts/add-user.sh alice

# 列出账户
./scripts/list-users.sh

# 吊销账户
./scripts/revoke-user.sh alice

# 查看服务日志
docker compose logs -f openvpn
```

---

如有问题，请检查 `docker compose logs openvpn` 输出，或提交 Issue。
