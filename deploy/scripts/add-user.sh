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

if ! [[ "${USERNAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
	echo "错误: 用户名只能包含字母、数字、下划线和连字符"
	exit 1
fi

cd "${DEPLOY_DIR}"

if [ ! -f data/openvpn/openvpn.conf ]; then
	echo "错误: 服务端尚未初始化，请先运行 ./scripts/init-server.sh"
	exit 1
fi

if [ -f "data/openvpn/pki/issued/${USERNAME}.crt" ]; then
	echo "错误: 用户 ${USERNAME} 已存在"
	exit 1
fi

mkdir -p clients

echo "==> 为用户 ${USERNAME} 签发客户端证书..."
docker compose run --rm openvpn easyrsa --batch build-client-full "${USERNAME}" nopass

echo "==> 生成客户端导入文件..."
docker compose run --rm openvpn ovpn_getclient "${USERNAME}" > "clients/${USERNAME}.ovpn"

echo ""
echo "账户创建成功！"
echo "  用户名:     ${USERNAME}"
echo "  客户端文件: ${DEPLOY_DIR}/clients/${USERNAME}.ovpn"
echo ""
echo "  导入 OpenVPN Connect 后直接连接，无需输入密码"
echo "  .ovpn 内含私钥，请妥善保管，等同于账户凭证"
