#!/usr/bin/env bash
# 修复 OpenVPN Connect 3.x 无法连接的问题（TLS: Auth Username/Password was not provided）
# 原因：Connect 在 TLS 阶段不提交账密，与 auth-user-pass-verify 冲突
# 处理：切换为「仅客户端证书」认证（每用户独立证书，仍具备账户隔离）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${DEPLOY_DIR}"

if [ ! -f data/openvpn/openvpn.conf ]; then
	echo "错误: 服务端尚未初始化"
	exit 1
fi

CONF_FILE="${DEPLOY_DIR}/data/openvpn/openvpn.conf"

echo "==> 移除服务端账密验证（保留客户端证书验证）..."
grep -v -E '^(# 账户权限验证|script-security 3|auth-user-pass-verify|username-as-common-name)' \
	"${CONF_FILE}" > "${CONF_FILE}.tmp"
mv "${CONF_FILE}.tmp" "${CONF_FILE}"

if grep -q 'auth-user-pass-verify' "${CONF_FILE}"; then
	echo "错误: openvpn.conf 仍含 auth-user-pass-verify，请手动检查 ${CONF_FILE}"
	exit 1
fi

if ! grep -q "^verify-client-cert require" "${CONF_FILE}"; then
	echo "verify-client-cert require" >> "${CONF_FILE}"
fi

if ! grep -q "^crl-verify" "${CONF_FILE}"; then
	echo "crl-verify /etc/openvpn/crl.pem" >> "${CONF_FILE}"
fi

echo "==> 重新生成客户端 .ovpn（不含 auth-user-pass）..."
mkdir -p clients

if [ -d data/openvpn/pki/issued ]; then
	for cert in data/openvpn/pki/issued/*.crt; do
		[ -f "${cert}" ] || continue
		username=$(basename "${cert}" .crt)
		case "${username}" in
			ca | server | OpenVPN-CA) continue ;;
		esac
		# 跳过服务端证书（CN 通常为公网 IP 或域名）
		if [ -f .env ]; then
			# shellcheck disable=SC1091
			source .env
			[ "${username}" = "${OVPN_SERVER:-}" ] && continue
		fi
		echo "  - ${username}"
		docker compose run --rm openvpn ovpn_getclient "${username}" > "clients/${username}.ovpn"
		grep -v -E '^(auth-user-pass|auth-nocache)' "clients/${username}.ovpn" > "clients/${username}.ovpn.tmp"
		mv "clients/${username}.ovpn.tmp" "clients/${username}.ovpn"
	done
fi

echo "==> 重启 OpenVPN..."
docker compose restart openvpn

echo ""
echo "修复完成！"
echo "  认证方式: 仅客户端证书（兼容 OpenVPN Connect 3.x）"
echo "  请重新导入 clients/ 下的 .ovpn 到客户端后再连接"
echo "  连接时无需输入用户名和密码"
