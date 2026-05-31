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

has_passwd=0
has_cert=0
[ -f config/auth/passwd ] && grep -q "^${USERNAME}:" config/auth/passwd 2>/dev/null && has_passwd=1
[ -f "data/openvpn/pki/issued/${USERNAME}.crt" ] && has_cert=1

if [ "${has_passwd}" -eq 0 ] && [ "${has_cert}" -eq 0 ]; then
	echo "错误: 用户 ${USERNAME} 不存在"
	exit 1
fi

if [ "${has_cert}" -eq 1 ]; then
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
else
	echo "==> 用户 ${USERNAME} 无有效证书，跳过吊销"
fi

if [ "${has_passwd}" -eq 1 ] && [ -f config/auth/passwd ]; then
	grep -v "^${USERNAME}:" config/auth/passwd > config/auth/passwd.tmp || true
	mv config/auth/passwd.tmp config/auth/passwd
	chmod 600 config/auth/passwd
fi

if [ -f "clients/${USERNAME}.ovpn" ]; then
	rm -f "clients/${USERNAME}.ovpn"
fi

echo "用户 ${USERNAME} 已删除。"
