#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
	echo "用法: $0 <用户名>"
	exit 1
}

[ $# -lt 1 ] && usage

USERNAME="$1"
cd "${DEPLOY_DIR}"

if [ ! -f data/openvpn/openvpn.conf ]; then
	echo "错误: 服务端尚未初始化"
	exit 1
fi

echo "==> 吊销用户 ${USERNAME} 的客户端证书..."
docker compose run --rm openvpn easyrsa --batch revoke "${USERNAME}"
docker compose run --rm openvpn easyrsa gen-crl

echo "==> 更新 CRL..."
docker compose exec openvpn sh -c 'cp /etc/openvpn/pki/crl.pem /etc/openvpn/crl.pem'
docker compose restart openvpn

if [ -f config/auth/passwd ]; then
	sed -i.bak "/^${USERNAME}:/d" config/auth/passwd
	rm -f config/auth/passwd.bak
fi

if [ -f "clients/${USERNAME}.ovpn" ]; then
	rm -f "clients/${USERNAME}.ovpn"
fi

echo "用户 ${USERNAME} 已吊销并移除。"
