#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
	echo "用法: $0 <用户名> [新密码]"
	echo "  若未提供新密码，将交互式输入（不回显）"
	exit 1
}

[ $# -lt 1 ] && usage

USERNAME="$1"
NEW_PASSWORD="${2:-}"

if ! [[ "${USERNAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
	echo "错误: 用户名只能包含字母、数字、下划线和连字符"
	exit 1
fi

if [ -z "${NEW_PASSWORD}" ]; then
	read -r -s -p "请输入 ${USERNAME} 的新密码: " NEW_PASSWORD
	echo
	read -r -s -p "请再次输入新密码: " NEW_PASSWORD2
	echo
	if [ "${NEW_PASSWORD}" != "${NEW_PASSWORD2}" ]; then
		echo "错误: 两次密码不一致"
		exit 1
	fi
fi

if [ -z "${NEW_PASSWORD}" ]; then
	echo "错误: 密码不能为空"
	exit 1
fi

cd "${DEPLOY_DIR}"

if [ ! -f config/auth/passwd ]; then
	echo "错误: 账户文件不存在，请先创建账户"
	exit 1
fi

if ! grep -q "^${USERNAME}:" config/auth/passwd 2>/dev/null; then
	echo "错误: 用户 ${USERNAME} 不存在，请先 ./scripts/add-user.sh ${USERNAME}"
	exit 1
fi

PASS_HASH=$(printf '%s' "${NEW_PASSWORD}" | sha256sum | awk '{print $1}')
grep -v "^${USERNAME}:" config/auth/passwd > config/auth/passwd.tmp
echo "${USERNAME}:${PASS_HASH}" >> config/auth/passwd.tmp
mv config/auth/passwd.tmp config/auth/passwd
chmod 600 config/auth/passwd

echo ""
echo "密码修改成功！"
echo "  用户名: ${USERNAME}"
echo "  说明:   客户端 .ovpn 无需重新生成，连接时使用新密码即可"
