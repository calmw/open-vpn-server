#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${DEPLOY_DIR}"

echo "==> 已签发的客户端证书:"
if [ -d data/openvpn/pki/issued ]; then
	count=0
	for cert in data/openvpn/pki/issued/*.crt; do
		[ -f "${cert}" ] || continue
		username=$(basename "${cert}" .crt)
		case "${username}" in
			ca | server | OpenVPN-CA) continue ;;
		esac
		if [ -f .env ]; then
			# shellcheck disable=SC1091
			source .env
			[ "${username}" = "${OVPN_SERVER:-}" ] && continue
		fi
		echo "  - ${username}"
		count=$((count + 1))
	done
	if [ "${count}" -eq 0 ]; then
		echo "  （无）"
	else
		echo ""
		echo "  共 ${count} 个账户"
	fi
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
