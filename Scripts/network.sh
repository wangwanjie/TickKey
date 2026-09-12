#!/usr/bin/env bash
# 仅对子进程启用代理，不修改用户的全局网络配置。
if nc -z -w 2 127.0.0.1 7890 >/dev/null 2>&1; then
  export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
  export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy"
  export no_proxy='kugou.net,tmeoa.com' NO_PROXY='kugou.net,tmeoa.com'
  # 显式覆盖某些机器上值为空的 git proxy 配置，仍仅影响当前进程。
  export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.proxy GIT_CONFIG_VALUE_0="$http_proxy"
  export GIT_CONFIG_KEY_1=https.proxy GIT_CONFIG_VALUE_1="$https_proxy"
fi
