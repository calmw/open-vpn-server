#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
	echo "用法: $0 <用户名>"
	echo "  删除指定账户：吊销证书、移除密码、删除本地 .ovpn"
	exit 1
}

[ $# -lt 1 ] && usage

USERNAME="$1"

if ! [[ "${USERNAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
	echo "错误: 用户名只能包含字母、数字、下划线和连字符"
	exit 1
fi

read -r -p "确认删除用户 ${USERNAME}？证书将吊销且无法恢复 [y/N]: " confirm
if [[ ! "${confirm}" =~ ^[yY]$ ]]; then
	echo "已取消"
	exit 0
fi

exec "${SCRIPT_DIR}/revoke-user.sh" "${USERNAME}"
