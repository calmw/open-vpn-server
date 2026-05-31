#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
	echo "用法: $0 <用户名> [密码]"
	echo "  默认仅证书认证，无需密码（兼容 OpenVPN Connect）"
	echo "  若 .env 中 OVPN_PASSWORD_AUTH=1，则必须提供密码"
	exit 1
}

[ $# -lt 1 ] && usage

USERNAME="$1"
PASSWORD="${2:-}"

if ! [[ "${USERNAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
	echo "错误: 用户名只能包含字母、数字、下划线和连字符"
	exit 1
fi

cd "${DEPLOY_DIR}"

if [ -f .env ]; then
	# shellcheck disable=SC1091
	source .env
fi
OVPN_PASSWORD_AUTH="${OVPN_PASSWORD_AUTH:-0}"

if [ "${OVPN_PASSWORD_AUTH}" = "1" ]; then
	if [ -z "${PASSWORD}" ]; then
		read -r -s -p "请输入 ${USERNAME} 的 VPN 密码: " PASSWORD
		echo
		read -r -s -p "请再次输入密码: " PASSWORD2
		echo
		if [ "${PASSWORD}" != "${PASSWORD2}" ]; then
			echo "错误: 两次密码不一致"
			exit 1
		fi
	fi
	if [ -z "${PASSWORD}" ]; then
		echo "错误: 密码不能为空"
		exit 1
	fi
fi

if [ ! -f data/openvpn/openvpn.conf ]; then
	echo "错误: 服务端尚未初始化，请先运行 ./scripts/init-server.sh"
	exit 1
fi

mkdir -p config/auth clients
touch config/auth/passwd

if grep -q "^${USERNAME}:" config/auth/passwd 2>/dev/null; then
	echo "错误: 用户 ${USERNAME} 已存在"
	exit 1
fi

if [ -f "data/openvpn/pki/issued/${USERNAME}.crt" ]; then
	echo "错误: 用户 ${USERNAME} 的证书已存在"
	exit 1
fi

echo "==> 为用户 ${USERNAME} 签发客户端证书..."
docker compose run --rm openvpn easyrsa --batch build-client-full "${USERNAME}" nopass

if [ "${OVPN_PASSWORD_AUTH}" = "1" ]; then
	echo "==> 写入账户密码..."
	PASS_HASH=$(printf '%s' "${PASSWORD}" | sha256sum | awk '{print $1}')
	echo "${USERNAME}:${PASS_HASH}" >> config/auth/passwd
	chmod 600 config/auth/passwd
else
	echo "${USERNAME}:" >> config/auth/passwd
	chmod 600 config/auth/passwd
fi

echo "==> 生成客户端导入文件..."
docker compose run --rm openvpn ovpn_getclient "${USERNAME}" > "clients/${USERNAME}.ovpn"

if [ "${OVPN_PASSWORD_AUTH}" = "1" ]; then
	if ! grep -q "^auth-user-pass" "clients/${USERNAME}.ovpn"; then
		awk '/^client/ { print; print "auth-user-pass"; print "auth-nocache"; next }1' \
			"clients/${USERNAME}.ovpn" > "clients/${USERNAME}.ovpn.tmp"
		mv "clients/${USERNAME}.ovpn.tmp" "clients/${USERNAME}.ovpn"
	fi
fi

echo ""
echo "账户创建成功！"
echo "  用户名:     ${USERNAME}"
echo "  客户端文件: ${DEPLOY_DIR}/clients/${USERNAME}.ovpn"
echo ""
if [ "${OVPN_PASSWORD_AUTH}" = "1" ]; then
	echo "客户端导入说明:"
	echo "  - 建议使用 Tunnelblick 或 openvpn CLI（OpenVPN Connect 可能不支持账密）"
	echo "  - 连接时用户名: ${USERNAME}，密码为创建时设置的密码"
else
	echo "客户端导入说明:"
	echo "  - OpenVPN Connect / Tunnelblick: 直接导入 .ovpn，连接时无需输入密码"
	echo "  - .ovpn 内含私钥，请妥善保管，等同于账户凭证"
fi
