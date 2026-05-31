#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${DEPLOY_DIR}"

if [ ! -f .env ]; then
	echo "错误: 未找到 .env 文件，请先复制 .env.example 并填写 OVPN_SERVER"
	echo "  cp .env.example .env"
	exit 1
fi

# shellcheck disable=SC1091
source .env

if [ -z "${OVPN_SERVER:-}" ] || [ "${OVPN_SERVER}" = "your.server.public.ip" ]; then
	echo "错误: 请在 .env 中设置 OVPN_SERVER（云服务器公网 IP 或域名）"
	exit 1
fi

OVPN_PORT="${OVPN_PORT:-1194}"
OVPN_SUBNET="${OVPN_SUBNET:-192.168.255.0}"
OVPN_CN="${OVPN_CN:-OpenVPN-CA}"

mkdir -p data/openvpn config/auth clients
touch config/auth/passwd
chmod 600 config/auth/passwd
chmod +x config/auth/check-user.sh

echo "==> 生成 OpenVPN 服务端配置..."
docker compose run --rm openvpn ovpn_genconfig \
	-u "udp://${OVPN_SERVER}:${OVPN_PORT}" \
	-s "${OVPN_SUBNET}/24" \
	-e "push \"redirect-gateway def1 bypass-dhcp\""

echo "==> 初始化 PKI（CA 与服务器证书）..."
docker compose run --rm -T \
	-e EASYRSA_BATCH=1 \
	-e EASYRSA_REQ_CN="${OVPN_CN}" \
	openvpn ovpn_initpki nopass

echo "==> 启用用户名/密码 + 客户端证书双重验证..."
CONF_FILE="${DEPLOY_DIR}/data/openvpn/openvpn.conf"
if ! grep -q "auth-user-pass-verify" "${CONF_FILE}"; then
	cat >> "${CONF_FILE}" <<'EOF'

# 账户权限验证：证书 CN 须与登录用户名一致，且密码正确
script-security 3
auth-user-pass-verify /etc/openvpn/auth/check-user.sh via-env
username-as-common-name
verify-client-cert require
crl-verify /etc/openvpn/crl.pem
EOF
fi

docker compose run --rm openvpn easyrsa gen-crl
docker compose run --rm openvpn sh -c 'cp /etc/openvpn/pki/crl.pem /etc/openvpn/crl.pem'

echo "==> 启动 OpenVPN 服务..."
docker compose up -d

echo ""
echo "初始化完成！"
echo "  服务端地址: ${OVPN_SERVER}:${OVPN_PORT}/udp"
echo ""
echo "账户管理:"
echo "  查看账户:   ./scripts/list-users.sh"
echo "  创建账户:   ./scripts/add-user.sh <用户名> [密码]"
echo "  修改密码:   ./scripts/change-password.sh <用户名> [新密码]"
echo "  删除账户:   ./scripts/delete-user.sh <用户名>"
