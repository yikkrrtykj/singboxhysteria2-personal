#!/usr/bin/env bash
# Standalone, read-only VPS -> representative mainland IPv4 TCP endpoints.
# Endpoint naming/port source, checked 2026-10-30:
# https://github.com/xykt/NetQuality/blob/main/net.sh (read_ref / ping_test)
# No installation, throughput tests, route traces or configuration changes.
set -u
command -v curl >/dev/null 2>&1 || { printf '未检测：系统缺少 curl。\n'; exit 1; }

probe() {
    local region="$1" isp="$2" region_name isp_name target connected result
    case "$region" in bj) region_name=北京;; sh) region_name=上海;; gd) region_name=广东;; esac
    case "$isp" in ct) isp_name=电信;; cu) isp_name=联通;; cm) isp_name=移动;; esac
    target="${region}-${isp}-v4.ip.zstaticcdn.com"
    # A completed TCP handshake counts even if HTTP HEAD is rejected or times
    # out afterward. Each separate curl has no reused connection. -q must be
    # first: ignore curlrc; ignore explicit proxy environment settings as well.
    connected=$(curl -q -4 --noproxy '*' --connect-timeout 2 --max-time 3 --retry 0 \
        --head --silent --output /dev/null --write-out '%{time_connect}' \
        "http://${target}:80/" 2>/dev/null)
    result=未确认
    if [[ "$connected" =~ ^[0-9]+\.[0-9]+$ && "$connected" =~ [1-9] ]]; then
        result=该测试点已接通
    fi
    printf '%s %s：%s（%s:80）\n' "$region_name" "$isp_name" "$result" "$target"
}

printf '方向：当前 VPS → 大陆代表测试点；IPv4 / TCP 80。\n'
printf '9 个点并行，每个请求最多 3 秒；不测试速度、长期丢包或 HY2 UDP。\n'
for region in bj sh gd; do
    for isp in ct cu cm; do
        probe "$region" "$isp" &
    done
done
wait
printf '未确认可能是 DNS、目标服务、路由或过滤问题，不等于整个运营商不通。\n'
printf '结果只代表这些点与当前时刻，不证明大陆用户能连入 VPS 的代理端口。\n'
