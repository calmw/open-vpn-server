# OpenVPN Server 云服务器部署指南

本文档介绍如何在云服务器上使用 Docker Compose 部署 OpenVPN 服务端，创建带权限验证的 VPN 账户，并生成可供客户端直接导入的 `.ovpn` 配置文件。

## 架构说明

```
┌─────────────────┐         UDP 1194          ┌──────────────────────┐
│  VPN 客户端      │ ◄──────────────────────► │  云服务器             │
│  (.ovpn 导入)   │    TLS + 独立客户端证书      │  docker-compose      │
└─────────────────┘                           │  (host 网络模式)      │
                                              └──────────────────────┘
                                                        │
                                              VPN 流量 NAT → eth0 → 公网
```

**安全模型：**

| 项目 | 说明 |
|------|------|
| 账户标识 | 每个用户拥有独立客户端证书（CN = 用户名） |
| 凭证形式 | `.ovpn` 文件内含私钥，**等同于账户凭证**，须妥善保管 |
| 吊销机制 | 删除账户时吊销证书并更新 CRL，旧 `.ovpn` 立即失效 |

> 兼容 OpenVPN Connect / iOS / Android 官方客户端，连接时无需输入用户名密码。

## 前置要求

| 项目 | 要求 |
|------|------|
| 云服务器 | Linux（推荐 Ubuntu 22.04+ / Debian 12+），1 核 1G 内存即可 |
| 公网 IP | 有固定公网 IP 或已解析到服务器的域名 |
| 软件 | Docker 20.10+、Docker Compose v2 |
| 防火墙 | 云安全组 + 本地防火墙均放行 **UDP 1194** |

## 目录结构

```
open-vpn-server/
├── DEPLOY.md
└── deploy/
    ├── docker-compose.yml
    ├── .env.example
    ├── scripts/
    │   ├── init-server.sh    # 初始化服务端
    │   ├── add-user.sh       # 创建账户并生成 .ovpn
    │   ├── list-users.sh     # 查看已有账户
    │   └── delete-user.sh    # 删除账户（带确认）
    ├── data/openvpn/         # PKI 与服务端配置（运行时生成）
    └── clients/              # 客户端 .ovpn（运行时生成）
```

---

## 快速部署（完整流程）

```bash
# 1. 进入目录
cd deploy
cp .env.example .env
vim .env                          # 设置 OVPN_SERVER 为公网 IP

# 2. 初始化
chmod +x scripts/*.sh
./scripts/init-server.sh

# 3. 创建账户
./scripts/add-user.sh alice

# 4. 配置云安全组：入站 UDP 1194（见第四节）

# 5. 配置 NAT（见第八节，Connected 后无法上网时必做）

# 6. 下载 .ovpn 到本地并导入客户端
scp root@<公网IP>:/path/to/deploy/clients/alice.ovpn ./

# 7. OpenVPN Connect 直接连接
```

---

## 一、安装 Docker

以 Ubuntu 为例：

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # 重新登录后生效
docker --version && docker compose version
```

## 二、上传部署文件

```bash
git clone <your-repo-url> open-vpn-server
cd open-vpn-server/deploy
```

## 三、配置环境变量

```bash
cp .env.example .env
```

编辑 `.env`：

```bash
# 公网 IP 或域名（不要加 udp:// 前缀）
OVPN_SERVER=43.160.200.71

OVPN_PORT=1194
OVPN_SUBNET=192.168.255.0
OVPN_CN=OpenVPN-CA
```

> `OVPN_SERVER` 必须填写客户端能访问的**公网地址**。可在服务器上验证：
> ```bash
> curl -4 ifconfig.me
> ```

## 四、开放防火墙与安全组

### 云厂商安全组（必做）

腾讯云 / 阿里云 / AWS 等控制台 → 云服务器 → 安全组 → **入站规则**：

| 协议 | 端口 | 来源 | 说明 |
|------|------|------|------|
| **UDP** | **1194** | 0.0.0.0/0 | 必须是 UDP，不是 TCP |

### 服务器本地防火墙

```bash
sudo ufw allow 1194/udp
sudo ufw reload
sudo ufw status
```

### 外网连通性自测

在**本地电脑**执行（非服务器）：

```bash
nc -vzu <公网IP> 1194
# 期望：Connection to ... port 1194 [udp/openvpn] succeeded!
```

## 五、初始化 OpenVPN 服务端

```bash
cd deploy
chmod +x scripts/*.sh
./scripts/init-server.sh
```

脚本依次完成：

1. 生成服务端配置（全流量走 VPN + DNS 推送）
2. 初始化 PKI（CA、服务端证书，全自动无需手动输入）
3. 启用客户端证书验证
4. 启动 Docker 容器（`network_mode: host`）

> **初始化失败时**，清理后重试：
> ```bash
> rm -rf data/openvpn/*
> ./scripts/init-server.sh
> ```

初始化成功后：

```bash
docker compose ps                        # 状态 Up
sudo ss -ulnp | grep 1194               # 监听 0.0.0.0:1194
docker compose logs -f openvpn          # 实时日志（不要用 | tail）
```

### 常用运维命令

```bash
docker compose ps
docker compose logs -f openvpn
docker compose restart openvpn
docker compose down
```

---

## 六、VPN 账户管理

| 操作 | 命令 |
|------|------|
| 创建账户 | `./scripts/add-user.sh <用户名>` |
| 查看账户 | `./scripts/list-users.sh` |
| 删除账户 | `./scripts/delete-user.sh <用户名>` |

### 创建账户

```bash
./scripts/add-user.sh alice
```

生成 `clients/alice.ovpn`，内含服务端地址、CA 证书、客户端证书和私钥。

### 查看已有账户

```bash
./scripts/list-users.sh
```

### 删除账户

```bash
./scripts/delete-user.sh alice   # 输入 y 确认
```

### 下载 .ovpn 到本地

```bash
# 在本地电脑执行
scp root@<公网IP>:/data/openvpn/open-vpn-server/deploy/clients/alice.ovpn ./
```

---

## 七、客户端导入与连接

### 推荐客户端

| 平台 | 客户端 |
|------|--------|
| macOS / iOS / Windows / Android | [OpenVPN Connect](https://openvpn.net/client/) |
| macOS | Tunnelblick |
| Linux | `openvpn --config alice.ovpn` |

### 连接步骤

1. 导入 `alice.ovpn`
2. 点击 **Connect**
3. 无需输入用户名和密码

> 若之前导入过旧版含账密验证的配置，须**删除旧配置**后重新导入新生成的 `.ovpn`。

### 连接成功标志

**服务端日志**（`docker compose logs -f openvpn`）：

```
VERIFY OK: depth=0, CN=alice
...
Peer Connection Initiated with [AF_INET]...
alice/<客户端IP>:xxxxx MULTI: Learn: ...
```

**客户端**：

```bash
curl ifconfig.me    # 应显示服务器公网 IP
ping 8.8.8.8
```

---

## 八、NAT 与 IP 转发（Connected 后无法上网时必做）

云服务器（如腾讯云）内网 IP 经 NAT 出公网，需确保：

```bash
# 1. IP 转发（应为 1）
cat /proc/sys/net/ipv4/ip_forward

# 若不是 1：
sudo sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-openvpn.conf
sudo sysctl --system

# 2. 查看公网网卡名
ip route | grep default
# 示例：default via 10.3.0.1 dev eth0 ...

# 3. 添加 NAT（eth0 替换为实际网卡名）
sudo iptables -t nat -A POSTROUTING -s 192.168.255.0/24 -o eth0 -j MASQUERADE

# 4. 验证
sudo iptables -t nat -L POSTROUTING -n -v | grep 192.168.255
```

**持久化**（重启后不丢失）：

```bash
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
```

---

## 九、故障排查

### 排查流程

```
连接失败
  ├─ 服务端无日志 → 安全组/端口/remote 地址错误
  ├─ TLS Error: Auth Username/Password was not provided → 旧版账密配置残留（见下方）
  └─ Connected 但无法上网 → IP 转发 / NAT（见第八节）
```

### 常见问题

| 现象 | 处理 |
|------|------|
| 客户端 Timeout，服务端无日志 | 检查云安全组 **UDP 1194**；`nc -vzu <IP> 1194` |
| TLS Error: Auth Username/Password was not provided | 旧版初始化残留账密验证，见下方 |
| Connected 但无法上网 | 配置 NAT（第八节） |
| 证书错误 | 重新 `./scripts/add-user.sh` 生成 .ovpn |

### 旧版账密配置残留

若服务端日志出现 `Auth Username/Password was not provided`，说明 `openvpn.conf` 中仍有旧版 `auth-user-pass-verify` 配置：

```bash
# 移除账密验证行
grep -v -E '^(# 账户权限验证|script-security 3|auth-user-pass-verify|username-as-common-name)' \
  data/openvpn/openvpn.conf > /tmp/openvpn.conf.tmp
mv /tmp/openvpn.conf.tmp data/openvpn/openvpn.conf

# 重新生成客户端配置
docker compose run --rm openvpn ovpn_getclient <用户名> > clients/<用户名>.ovpn
docker compose restart openvpn
```

或清理后重新初始化：

```bash
rm -rf data/openvpn/*
./scripts/init-server.sh
./scripts/add-user.sh <用户名>
```

### 诊断命令汇总

```bash
docker compose ps
sudo ss -ulnp | grep 1194
curl -4 ifconfig.me
grep ^remote clients/*.ovpn
docker compose logs -f openvpn
```

---

## 十、进阶配置

### 修改 VPN 内网网段

修改 `.env` 中 `OVPN_SUBNET`，删除 `data/openvpn/*` 后重新 `./scripts/init-server.sh`（会重建 PKI，账户需重新创建）。

### 分流（不接管全部流量）

编辑 `data/openvpn/openvpn.conf`，注释 `push "redirect-gateway ..."` 行，改为：

```
push "route 10.0.0.0 255.0.0.0"
```

然后 `docker compose restart openvpn`。

---

## 十一、备份与恢复

```bash
tar czvf openvpn-backup-$(date +%Y%m%d).tar.gz data/openvpn
```

> **警告**：丢失 `data/openvpn/pki/` 中的 CA 私钥后，所有 `.ovpn` 失效，必须重新初始化并重新分发。

---

## 十二、安全建议

1. **`.ovpn` 即账户凭证**：内含私钥，勿通过不安全渠道传输或提交到 Git
2. **最小权限**：按需创建账户，离职立即 `./scripts/delete-user.sh`
3. **定期备份** `data/openvpn/`，CA 私钥离线保存
4. **SSH 安全**：仅允许密钥登录，禁用密码登录
5. **安全组**：生产环境可将 UDP 1194 来源限制为可信 IP 段

---

## 快速命令参考

```bash
cd deploy

cp .env.example .env && vim .env
./scripts/init-server.sh

./scripts/add-user.sh alice
./scripts/list-users.sh
./scripts/delete-user.sh alice

docker compose logs -f openvpn
docker compose restart openvpn
```

---

如有问题，请执行 `docker compose logs openvpn` 并将相关日志一并反馈。
