#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
	echo "用法: $0 <用户名>"
	echo "  删除指定账户：吊销证书并删除本地 .ovpn"
	exit 1
}

[ $# -lt 1 ] && usage

USERNAME="$1"

if ! [[ "${USERNAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
	echo "错误: 用户名只能包含字母、数字、下划线和连字符"
	exit 1
fi

cd "${DEPLOY_DIR}"

if [ ! -f data/openvpn/openvpn.conf ]; then
	echo "错误: 服务端尚未初始化"
	exit 1
fi

if [ ! -f "data/openvpn/pki/issued/${USERNAME}.crt" ]; then
	echo "错误: 用户 ${USERNAME} 不存在"
	exit 1
fi

read -r -p "确认删除用户 ${USERNAME}？证书将吊销且无法恢复 [y/N]: " confirm
if [[ ! "${confirm}" =~ ^[yY]$ ]]; then
	echo "已取消"
	exit 0
fi

echo "==> 吊销用户 ${USERNAME} 的客户端证书..."
docker compose run --rm openvpn easyrsa --batch revoke "${USERNAME}"
docker compose run --rm openvpn easyrsa gen-crl

echo "==> 更新 CRL..."
if docker compose ps --status running --services 2>/dev/null | grep -q openvpn; then
	docker compose exec openvpn sh -c 'cp /etc/openvpn/pki/crl.pem /etc/openvpn/crl.pem'
	docker compose restart openvpn
else
	docker compose run --rm openvpn sh -c 'cp /etc/openvpn/pki/crl.pem /etc/openvpn/crl.pem'
fi

if [ -f "clients/${USERNAME}.ovpn" ]; then
	rm -f "clients/${USERNAME}.ovpn"
fi

echo "用户 ${USERNAME} 已删除。"
