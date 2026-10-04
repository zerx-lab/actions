#!/usr/bin/env bash
# 官网下载入口按 User-Agent 路由；默认 curl UA 会收到 HTTP 404。
set -euo pipefail

endpoint='https://dida365.com/static/getApp/download?type=linux_deb_x64'
# 只读取官网的 Location，不连接下载 CDN；版本检查不依赖 CDN 可达性。
if ! location=$(curl --fail --silent --show-error --head \
  --connect-timeout 10 --max-time 30 --user-agent 'Mozilla/5.0' \
  --output /dev/null --write-out '%{redirect_url}' "$endpoint"); then
  echo "::error::无法解析滴答清单官网下载地址：$endpoint" >&2
  exit 1
fi

echo "官网下载地址：$location" >&2
if [[ "$location" =~ ^https://cdn\.dida365\.cn/download/linux/linux_deb_x64/dida-([0-9]+(\.[0-9]+){2,3})-amd64\.deb$ ]]; then
  printf 'version=%s\n' "${BASH_REMATCH[1]}"
else
  echo "::error::无法从官方 Linux x64 DEB 地址提取版本号：$location" >&2
  exit 1
fi
