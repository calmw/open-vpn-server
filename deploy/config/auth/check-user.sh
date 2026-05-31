#!/bin/sh
# OpenVPN auth-user-pass-verify 脚本
# 环境变量: username, password（由 OpenVPN 注入）

PASSWD_FILE="/etc/openvpn/auth/passwd"

if [ ! -f "$PASSWD_FILE" ] || [ -z "$username" ] || [ -z "$password" ]; then
	exit 1
fi

input_hash=$(printf '%s' "$password" | sha256sum | awk '{print $1}')
stored_hash=$(grep "^${username}:" "$PASSWD_FILE" 2>/dev/null | cut -d: -f2-)

if [ -n "$stored_hash" ] && [ "$input_hash" = "$stored_hash" ]; then
	exit 0
fi

exit 1
