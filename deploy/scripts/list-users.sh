#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${DEPLOY_DIR}"

echo "==> 已注册账户（passwd）:"
if [ -f config/auth/passwd ] && [ -s config/auth/passwd ]; then
	awk -F: '{print "  - " $1}' config/auth/passwd
else
	echo "  （无）"
fi

echo ""
echo "==> 已签发的客户端证书:"
if [ -d data/openvpn/pki/issued ]; then
	ls -1 data/openvpn/pki/issued/*.crt 2>/dev/null | xargs -n1 basename | sed 's/\.crt$//' | grep -v '^server$' | grep -v '^ca$' | sed 's/^/  - /' || echo "  （无）"
else
	echo "  （服务端尚未初始化）"
fi

echo ""
echo "==> 本地客户端配置文件:"
if [ -d clients ] && ls clients/*.ovpn >/dev/null 2>&1; then
	ls -1 clients/*.ovpn | xargs -n1 basename | sed 's/^/  - /'
else
	echo "  （无）"
fi
