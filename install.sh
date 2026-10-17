#!/bin/bash
umask 077


red="\033[31m\033[01m"
green="\033[32m\033[01m"
yellow="\033[33m\033[01m"
reset="\033[0m"
bold="\e[1m"

warning() { echo -e "${red}$*${reset}"; }
error() { warning "$*" && exit 1; }
info() { echo -e "${green}$*${reset}"; }
hint() { echo -e "${yellow}$*${reset}"; }

SING_BOX_VERSION_TAG="v1.14.3"
PERSONAL_REPO_RAW_URL="https://raw.githubusercontent.com/yikkrrtykj/singboxhysteria2-personal/main"
SB_DIR="/root/sbox"
SB_SERVER_CONFIG="$SB_DIR/sbconfig_server.json"
SB_STATE_FILE="$SB_DIR/config"
SB_BIN="$SB_DIR/sing-box"
SB_SHORTCUT_FILE="$SB_DIR/mianyang.sh"
SB_SHORTCUT_LINK="/usr/bin/mianyang"

version_at_least() {
    local version="${1#v}"
    local minimum="${2#v}"
    local v_major v_minor v_patch m_major m_minor m_patch

    IFS='.' read -r v_major v_minor v_patch _ <<< "$version"
    IFS='.' read -r m_major m_minor m_patch _ <<< "$minimum"
    v_major=${v_major:-0}; v_minor=${v_minor:-0}; v_patch=${v_patch:-0}
    m_major=${m_major:-0}; m_minor=${m_minor:-0}; m_patch=${m_patch:-0}
    v_patch=${v_patch%%[^0-9]*}
    m_patch=${m_patch%%[^0-9]*}

    if ((10#$v_major > 10#$m_major)); then return 0; fi
    if ((10#$v_major < 10#$m_major)); then return 1; fi
    if ((10#$v_minor > 10#$m_minor)); then return 0; fi
    if ((10#$v_minor < 10#$m_minor)); then return 1; fi
    ((10#${v_patch:-0} >= 10#${m_patch:-0}))
}

show_notice() {
    local message="$1"
    local terminal_width=$(tput cols)
    local line=$(printf "%*s" "$terminal_width" | tr ' ' '*')
    local padding=$(( (terminal_width - ${#message}) / 2 ))
    local padded_message="$(printf "%*s%s" $padding '' "$message")"
    warning "${bold}${line}${reset}"
    echo ""
    warning "${bold}${padded_message}${reset}"
    echo ""
    warning "${bold}${line}${reset}"
}

print_with_delay() {
    text="$1"
    delay="$2"
    for ((i = 0; i < ${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
    echo
}


show_status(){
    singbox_pid=$(pgrep -o -x sing-box 2>/dev/null || true)
    singbox_status=$(systemctl is-active sing-box 2>/dev/null || true)
    if [ -n "$singbox_pid" ]; then
        cpu_usage=$(ps -p "$singbox_pid" -o %cpu= | xargs)
        memory_usage_kb=$(ps -p "$singbox_pid" -o rss= | xargs)
        memory_usage_mb=$(( ${memory_usage_kb:-0} / 1024 ))

        latest_version_tag=$(curl -fsS --connect-timeout 5 --max-time 15 "https://api.github.com/repos/SagerNet/sing-box/releases" | jq -r '[.[] | select(.prerelease==false)][0].tag_name' 2>/dev/null)
        if [ -n "$latest_version_tag" ] && [ "$latest_version_tag" != "null" ]; then
            latest_version=${latest_version_tag#v}
        else
            latest_version="查询失败"
        fi

        hyhop=$(grep '^HY_HOPPING=' /root/sbox/config | cut -d'=' -f2)

        info "SING-BOX服务状态信息:"
        hint "========================="
        info "状态: 运行中"
        if [ "$singbox_status" == "active" ]; then
            info "启动方式: systemd (sing-box.service)"
        else
            warning "启动方式: 手工进程（旧安装，未由 systemd 管理）"
        fi
        info "CPU 占用: $cpu_usage%"
        info "内存 占用: ${memory_usage_mb}MB"
        info "singbox正式版最新版本: $latest_version"
		info "singbox当前版本: $(/root/sbox/sing-box version 2>/dev/null | awk '/version/{print $NF}')"
        info "hy2端口跳跃(输入6管理): $(if [ "$hyhop" == "TRUE" ]; then echo "开启"; else echo "关闭"; fi)"
        hint "========================="
    else
        warning "SING-BOX 未运行！"
    fi

}

install_pkgs() {
  local manager spec executable package
  local ip_package=iproute2 ps_package=procps
  local -a missing=()
  [ "$(id -u)" -eq 0 ] || { warning "请以 root 运行。"; return 1; }
  if command -v apt-get >/dev/null; then
    manager=apt-get
  elif command -v dnf >/dev/null; then
    manager=dnf; ip_package=iproute; ps_package=procps-ng
  elif command -v yum >/dev/null; then
    manager=yum; ip_package=iproute; ps_package=procps-ng
  else
    warning "未找到支持的软件包管理器。"; return 1
  fi
  # Only tools used by this script; no Monitor ACL/runuser dependencies.
  local -a dependencies=("qrencode:qrencode" "jq:jq" "iptables:iptables"
    "curl:curl" "openssl:openssl" "tar:tar" "sha256sum:coreutils"
    "ss:$ip_package" "ip:$ip_package" "pgrep:$ps_package" "flock:util-linux")
  for spec in "${dependencies[@]}"; do
    executable=${spec%%:*}; package=${spec#*:}
    command -v "$executable" >/dev/null || missing+=("$package")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    hint "安装缺少的基础工具..."
    if [ "$manager" = apt-get ]; then
      apt-get update -qq || return 1
    fi
    "$manager" install -y "${missing[@]}" ca-certificates || return 1
  fi
  for spec in "${dependencies[@]}"; do
    executable=${spec%%:*}
    command -v "$executable" >/dev/null || { warning "工具安装失败: $executable"; return 1; }
  done
}

install_shortcut() {
  cat > "$SB_SHORTCUT_FILE" << EOF
#!/usr/bin/env bash
set -euo pipefail
umask 077
task_script=\$(mktemp)
trap 'rm -f -- "\$task_script"' EXIT
curl -fsSL --connect-timeout 15 --max-time 120 -o "\$task_script" "${PERSONAL_REPO_RAW_URL}/install.sh"
bash "\$task_script" "\$@"
EOF
  chmod 0700 "$SB_SHORTCUT_FILE" || return 1
  ln -sf "$SB_SHORTCUT_FILE" "$SB_SHORTCUT_LINK" || return 1
}

reload_singbox() {
    if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
        echo "检查配置文件成功，开始重新加载服务..."
        if systemctl is-active --quiet sing-box; then
            if systemctl reload sing-box; then
                echo "systemd 服务重新加载成功."
            else
                error "systemd 服务重新加载失败，请检查日志"
            fi
        elif pgrep -x sing-box >/dev/null 2>&1; then
            singbox_pid=$(pgrep -o -x sing-box)
            if kill -HUP "$singbox_pid"; then
                echo "手工启动的 sing-box 进程已重新加载配置."
            else
                error "无法重新加载手工启动的 sing-box 进程"
            fi
        else
            error "未找到正在运行的 sing-box 进程"
        fi

        if systemctl is-active --quiet sing-box-hy2-hopping.service; then
            if systemctl reload sing-box-hy2-hopping.service; then
                info "Hysteria2 端口跳跃规则已同步刷新."
            else
                error "Hysteria2 端口跳跃规则刷新失败"
            fi
        fi
    else
        error "配置文件检查错误，请检查配置文件"
    fi
}


install_singbox() (
    # Download only the pinned official stable release; do not change config.
    local version="${SING_BOX_VERSION_TAG#v}" arch package metadata url digest actual temp candidate
    [[ "$SING_BOX_VERSION_TAG" =~ ^v1\.14\.[0-9]+$ ]] || { warning "版本必须是正式版 1.14.x"; return 1; }
    case "$(uname -m)" in
      x86_64) arch=amd64 ;;
      aarch64) arch=arm64 ;;
      armv7l) arch=armv7 ;;
      *) warning "不支持的 CPU 架构"; return 1 ;;
    esac
    package="sing-box-${version}-linux-${arch}"
    temp=$(mktemp -d "${SB_DIR}/.kernel-download.XXXXXX") || return 1
    trap 'rm -rf -- "$temp"' EXIT
    metadata="$temp/release.json"
    curl --proto '=https' -fsSL --connect-timeout 10 --max-time 60 \
      -o "$metadata" "https://api.github.com/repos/SagerNet/sing-box/releases/tags/$SING_BOX_VERSION_TAG" || return 1
    jq -e --arg tag "$SING_BOX_VERSION_TAG" \
      '.tag_name == $tag and .draft == false and .prerelease == false' "$metadata" >/dev/null || return 1
    url=$(jq -er --arg name "$package.tar.gz" '.assets[] | select(.name == $name) | .browser_download_url' "$metadata") || return 1
    digest=$(jq -er --arg name "$package.tar.gz" '.assets[] | select(.name == $name) | .digest' "$metadata") || return 1
    [[ "$url" == "https://github.com/SagerNet/sing-box/releases/download/$SING_BOX_VERSION_TAG/$package.tar.gz" &&
       "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || { warning "官方资源地址或 SHA256 缺失"; return 1; }
    info "安装官方 sing-box $version ..."
    curl --proto '=https' -fsSL --retry 2 --connect-timeout 10 --max-time 180 \
      -o "$temp/archive.tar.gz" "$url" || return 1
    actual=$(sha256sum "$temp/archive.tar.gz") || return 1
    [ "${actual%% *}" = "${digest#sha256:}" ] || { warning "SHA256 校验失败"; return 1; }
    tar -xzf "$temp/archive.tar.gz" -C "$temp" -- "$package/sing-box" || return 1
    candidate="$temp/sing-box"
    install -m 0755 "$temp/$package/sing-box" "$candidate" || return 1
    [ "$("$candidate" version | awk '/^sing-box version / {print $3}')" = "$version" ] || {
      warning "候选内核版本不匹配"; return 1;
    }
    if [ -f "$SB_SERVER_CONFIG" ]; then
      "$candidate" check -c "$SB_SERVER_CONFIG" || { warning "新版内核不能读取现有配置，未替换"; return 1; }
    fi
    mv -f -- "$candidate" "$SB_BIN" || return 1
)

restart_singbox() {
    if systemctl is-active --quiet sing-box; then
        systemctl restart sing-box
        return $?
    fi

    if pgrep -x sing-box >/dev/null 2>&1; then
        warning "检测到 sing-box 正由手工进程运行，拒绝启动第二个 systemd 实例。"
        warning "请先安排维护窗口，将现有进程平滑迁移到 sing-box.service。"
        return 2
    fi

    systemctl start sing-box
}

valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }

port_in_use() {
    local listeners
    listeners=$(ss -H -lntu 2>/dev/null) || return 2
    grep -qE "[:.]$1[[:space:]]" <<< "$listeners"
}

generate_port() {
    local protocol="$1" port user_input result
    while :; do
        port=$((RANDOM % 10001 + 10000))
        read -r -p "请为 ${protocol} 输入监听端口(默认为随机生成): " user_input || return 1
        port=${user_input:-$port}
        valid_port "$port" || { warning "端口必须在 1～65535 之间。" >&2; continue; }
        port=$((10#$port))
        if port_in_use "$port"; then result=0; else result=$?; fi
        case "$result" in
          1) printf '%s\n' "$port"; return 0 ;;
          2) warning "无法读取监听端口，已停止。" >&2; return 1 ;;
          *) warning "端口 $port 被占用，请输入其他端口。" >&2 ;;
        esac
    done
}

modify_port() {
    local current_port="$1" protocol="$2" modified_port result
    while :; do
        read -r -p "请输入需要修改的 ${protocol} 端口，回车不修改 (当前 ${protocol} 端口为: $current_port): " modified_port || return 1
        modified_port=${modified_port:-$current_port}
        valid_port "$modified_port" || { warning "端口必须在 1～65535 之间。" >&2; continue; }
        modified_port=$((10#$modified_port))
        [ "$modified_port" != "$current_port" ] || { printf '%s\n' "$modified_port"; return 0; }
        if port_in_use "$modified_port"; then result=0; else result=$?; fi
        case "$result" in
          1) printf '%s\n' "$modified_port"; return 0 ;;
          2) warning "无法读取监听端口，已停止。" >&2; return 1 ;;
          *) warning "端口 $modified_port 被占用，请输入其他端口。" >&2 ;;
        esac
    done
}

# client configuration
show_client_configuration() {
  local link_server_ip
  server_ip=$(grep -o "SERVER_IP='[^']*'" /root/sbox/config | awk -F"'" '{print $2}')
  public_key=$(grep -o "PUBLIC_KEY='[^']*'" /root/sbox/config | awk -F"'" '{print $2}')
  reality_port=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .listen_port' /root/sbox/sbconfig_server.json)
  reality_uuid=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .users[0].uuid' /root/sbox/sbconfig_server.json)
  reality_server_name=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .tls.server_name' /root/sbox/sbconfig_server.json)
  short_id=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .tls.reality.short_id[0]' /root/sbox/sbconfig_server.json)
  link_server_ip=$server_ip
  [[ "$link_server_ip" != *:* ]] || link_server_ip="[$link_server_ip]"
  reality_link="vless://$reality_uuid@$link_server_ip:$reality_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$reality_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#SING-BOX-REALITY"
  echo ""
  show_notice "VISION_REALITY 通用链接 二维码 通用参数"
  echo ""
  info "通用链接如下"
  echo ""
  echo "$reality_link"
  echo ""
  info "二维码如下"
  echo ""
  qrencode -t UTF8 "$reality_link"
  echo ""
  info "客户端通用参数如下"
  echo "------------------------------------"
  echo "服务器ip: $server_ip"
  echo "监听端口: $reality_port"
  echo "UUID: $reality_uuid"
  echo "域名SNI: $reality_server_name"
  echo "Public Key: $public_key"
  echo "Short ID: $short_id"
  echo "------------------------------------"

  # hy2
  hy_port=$(jq -r '.inbounds[] | select(.tag == "hy2-in") | .listen_port' /root/sbox/sbconfig_server.json)
  hy_server_name=$(grep -o "HY_SERVER_NAME='[^']*'" /root/sbox/config | awk -F"'" '{print $2}')
  hy_password=$(jq -r '.inbounds[] | select(.tag == "hy2-in") | .users[0].password' /root/sbox/sbconfig_server.json)
  ishopping=$(grep '^HY_HOPPING=' /root/sbox/config | cut -d'=' -f2)
  hy_hopping_start=$(grep '^HY_HOPPING_START=' /root/sbox/config | cut -d'=' -f2)
  hy_hopping_end=$(grep '^HY_HOPPING_END=' /root/sbox/config | cut -d'=' -f2)
  hy_server_port_json="            \"server_port\": $hy_port,"
  hy_clash_port_yaml="    port: $hy_port"
  formatted_range=""
  if [ "$ishopping" = "TRUE" ] &&
     [[ "$hy_hopping_start" =~ ^[0-9]+$ ]] &&
     [[ "$hy_hopping_end" =~ ^[0-9]+$ ]]; then
      formatted_range="${hy_hopping_start}-${hy_hopping_end}"
      hy_server_port_json="            \"server_ports\": [\"${hy_hopping_start}:${hy_hopping_end}\"],"
      hy_clash_port_yaml="    port: $hy_port
    ports: ${formatted_range}
    hop-interval: 30"
      hy2_link="hysteria2://$hy_password@$link_server_ip:$hy_port?insecure=1&sni=$hy_server_name&mport=${hy_port},${formatted_range}#SING-BOX-HYSTERIA2"
  elif [ "$ishopping" = "TRUE" ]; then
      warning "端口跳跃已标记为开启，但配置中没有有效端口范围，将显示固定端口配置。"
      hy2_link="hysteria2://$hy_password@$link_server_ip:$hy_port?insecure=1&sni=$hy_server_name#SING-BOX-HYSTERIA2"
  else
      hy2_link="hysteria2://$hy_password@$link_server_ip:$hy_port?insecure=1&sni=$hy_server_name#SING-BOX-HYSTERIA2"
  fi
  echo ""
  echo ""
  show_notice "Hysteria2通用链接 二维码 通用参数"
  echo ""
  info "通用链接如下"
  echo ""
  echo "$hy2_link"
  echo ""
  info "二维码如下"
  echo ""
  qrencode -t UTF8 "$hy2_link"
  echo ""
  info "客户端通用参数如下"
  echo "------------------------------------"
  echo "服务器ip: $server_ip"
  echo "端口号: $hy_port"
  if [ "$ishopping" = "TRUE" ] && [ -n "$formatted_range" ]; then
    echo "跳跃端口为${formatted_range}"
  else
    echo "端口跳跃未开启"
  fi
  echo "密码password: $hy_password"
  echo "域名SNI: $hy_server_name"
  echo "跳过证书验证（允许不安全）: True"
  echo "------------------------------------"

  show_notice "Mihomo/Clash Meta客户端配置参数"
  mihomo_config_path="/root/sbox/mihomo_client.yaml"
cat > "$mihomo_config_path" << EOF || error "保存 Mihomo 客户端配置失败"
mixed-port: 7897
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
unified-delay: true
ipv6: true
profile:
  store-selected: true
  store-fake-ip: true
dns:
  enable: true
  listen: "0.0.0.0:53"
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

tun:
  enable: true
  stack: mixed
  device: Mihomo
  mtu: 1420
  auto-route: true
  auto-redirect: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
    - tcp://any:53

proxies:
  - name: Reality
    type: vless
    server: $server_ip
    port: $reality_port
    uuid: $reality_uuid
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: $reality_server_name
    client-fingerprint: chrome
    reality-opts:
      public-key: $public_key
      short-id: $short_id

  - name: Hysteria2
    type: hysteria2
    server: $server_ip
${hy_clash_port_yaml}
    password: $hy_password
    sni: $hy_server_name
    skip-cert-verify: true
    alpn:
      - h3

proxy-groups:
  - name: 节点选择
    type: select
    proxies:
      - Reality
      - Hysteria2
      - 自动选择
      - DIRECT

  - name: 自动选择
    type: url-test
    proxies:
      - Reality
      - Hysteria2
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50


rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,节点选择

EOF
  chmod 0600 "$mihomo_config_path" || error "设置 Mihomo 客户端配置权限失败"
  cat "$mihomo_config_path"
  echo ""
  info "Mihomo 客户端配置已保存到: $mihomo_config_path"
  echo ""
  echo ""
  show_notice "sing-box客户端配置1.13.0及以上"
  client_config_path="/root/sbox/sbconfig_client.json"
cat > "$client_config_path" << EOF || error "保存 sing-box 客户端配置失败"
{
  "log": {
    "level": "debug",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "external_ui": "ui",
      "secret": "",
      "default_mode": "rule"
    },
    "cache_file": {
      "enabled": true,
      "store_fakeip": false
    }
  },
  "dns": {
    "servers": [
      {
        "tag": "proxyDns",
        "type": "udp",
        "server": "8.8.8.8",
        "detour": "proxy"
      },
      {
        "tag": "localDns",
        "type": "udp",
        "server": "223.5.5.5",
        "detour": "direct"
      },
      {
        "tag": "fakeip",
        "type": "fakeip",
        "inet4_range": "198.18.0.0/15",
        "inet6_range": "fc00::/18"
      }
    ],
    "rules": [
      {
        "domain": [
          "ghproxy.com",
          "cdn.jsdelivr.net",
          "testingcf.jsdelivr.net"
        ],
        "server": "localDns"
      },
      {
        "rule_set": "geosite-category-ads-all",
        "action": "reject"
      },
      {
        "rule_set": "geosite-cn",
        "action": "route",
        "server": "localDns"
      },
      {
        "clash_mode": "direct",
        "action": "route",
        "server": "localDns"
      },
      {
        "clash_mode": "global",
        "action": "route",
        "server": "proxyDns"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "action": "route",
        "server": "proxyDns"
      },
      {
        "query_type": [
          "A",
          "AAAA"
        ],
        "action": "route",
        "server": "fakeip"
      }
    ],
    "final": "proxyDns"
  },
  "inbounds": [
    {
      "type": "tun",
      "address": ["172.19.0.1/30"],
      "mtu": 9000,
      "auto_route": true,
      "strict_route": true,
      "endpoint_independent_nat": false,
      "stack": "system",
      "platform": {
        "http_proxy": {
          "enabled": true,
          "server": "127.0.0.1",
          "server_port": 2080
        }
      }
    },
    {
      "type": "mixed",
      "listen": "127.0.0.1",
      "listen_port": 2080,
      "users": []
    }
  ],
    "outbounds": [
    {
      "tag": "proxy",
      "type": "selector",
      "outbounds": [
        "auto",
        "direct",
        "sing-box-reality",
        "sing-box-hysteria2"
      ]
    },
    {
      "type": "vless",
      "tag": "sing-box-reality",
      "uuid": "$reality_uuid",
      "flow": "xtls-rprx-vision",
      "packet_encoding": "xudp",
      "server": "$server_ip",
      "server_port": $reality_port,
      "tls": {
        "enabled": true,
        "server_name": "$reality_server_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
    {
            "type": "hysteria2",
            "server": "$server_ip",
${hy_server_port_json}
            "tag": "sing-box-hysteria2",
            "password": "$hy_password",
            "tls": {
                "enabled": true,
                "server_name": "$hy_server_name",
                "insecure": true,
                "alpn": [
                    "h3"
                ]
            }
        },
    {
      "tag": "direct",
      "type": "direct",
      "domain_resolver": {
        "server": "localDns"
      }
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "sing-box-reality",
        "sing-box-hysteria2"
      ],
      "url": "http://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50
    },
    {
      "tag": "WeChat",
      "type": "selector",
      "outbounds": [
        "direct",
        "sing-box-reality",
        "sing-box-hysteria2"
      ]
    },
    {
      "tag": "Apple",
      "type": "selector",
      "outbounds": [
        "direct",
        "sing-box-reality",
        "sing-box-hysteria2"
      ]
    },
    {
      "tag": "Microsoft",
      "type": "selector",
      "outbounds": [
        "direct",
        "sing-box-reality",
        "sing-box-hysteria2"
      ]
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "default_domain_resolver": "localDns",
    "final": "proxy",
    "rules": [
      {
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "rule_set": "geosite-category-ads-all",
        "action": "reject"
      },
      {
        "clash_mode": "direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "global",
        "outbound": "proxy"
      },
      {
        "domain": [
          "clash.razord.top",
          "yacd.metacubex.one",
          "yacd.haishan.me",
          "d.metacubex.one"
        ],
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-wechat",
        "outbound": "WeChat"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "proxy"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-apple",
        "outbound": "Apple"
      },
      {
        "rule_set": "geosite-microsoft",
        "outbound": "Microsoft"
      }
    ],
    "rule_set": [
      {
        "tag": "geoip-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
        "download_detour": "direct"
      },
      {
        "tag": "geosite-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/cn.srs",
        "download_detour": "direct"
      },
      {
        "tag": "geosite-geolocation-!cn",
        "type": "remote",
        "format": "binary",
        "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
        "download_detour": "direct"
      },
      {
        "tag": "geosite-category-ads-all",
        "type": "remote",
        "format": "binary",
        "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/category-ads-all.srs",
        "download_detour": "direct"
      },
      {
        "tag": "geosite-wechat",
        "type": "remote",
        "format": "source",
        "url": "https://testingcf.jsdelivr.net/gh/Toperlock/sing-box-geosite@main/wechat.json",
        "download_detour": "direct"
      },
      {
        "tag": "geosite-apple",
        "type": "remote",
        "format": "binary",
        "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/apple.srs",
        "download_detour": "direct"
      },
      {
        "tag": "geosite-microsoft",
        "type": "remote",
        "format": "binary",
        "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/microsoft.srs",
        "download_detour": "direct"
      }
    ]
  }
}
EOF

  chmod 0600 "$client_config_path" || error "设置 sing-box 客户端配置权限失败"
  cat "$client_config_path"
  echo ""
  info "sing-box 客户端配置已保存到: $client_config_path"

  if command -v base64 >/dev/null 2>&1; then
    mihomo_config_base64=$(base64 "$mihomo_config_path" | tr -d '\r\n')
    echo ""
    echo ""
    show_notice "Linux Mihomo 网关：复制以下命令到客户端"
    info "命令 1：把本次节点配置写入 Linux 客户端"
    printf "umask 077 && printf '%%s' '%s' | base64 -d > /tmp/mihomo_client.yaml && chmod 600 /tmp/mihomo_client.yaml\n" "$mihomo_config_base64"
    echo ""
    info "命令 2：下载 Linux 网关安装器"
    echo "curl -fsSL -o /tmp/install-linux-gateway.sh ${PERSONAL_REPO_RAW_URL}/install-linux-gateway.sh && chmod 700 /tmp/install-linux-gateway.sh"
    echo ""
    info "命令 3：安装 Mihomo、启用 TUN 网关并开放局域网 9090 UI"
    # Keep command substitution literal so it runs on the Linux client.
    # shellcheck disable=SC2016
    echo 'if [ "$(id -u)" -eq 0 ]; then bash /tmp/install-linux-gateway.sh --config /tmp/mihomo_client.yaml --ui-lan --yes; else sudo bash /tmp/install-linux-gateway.sh --config /tmp/mihomo_client.yaml --ui-lan --yes; fi'
    echo ""
    hint "安装完成后查看 UI 密钥: cat /etc/mihomo/ui-secret"
  else
    warning "未找到 base64，无法生成 Linux 客户端的一键复制命令。"
  fi

}

NETWORK_SYSCTL_FILE="/etc/sysctl.d/99-sing-box-network.conf"
UDP_BUFFER_MIN_BYTES=16777216

read_sysctl_number() {
    sysctl -n "$1" 2>/dev/null | tr -cd '0-9'
}

larger_number() {
    local first="${1:-0}"
    local second="${2:-0}"
    if (( first > second )); then
        echo "$first"
    else
        echo "$second"
    fi
}

write_network_sysctl() {
    local request_bbr="${1:-FALSE}"
    local current_rmem current_wmem target_rmem target_wmem current_cc temp_file

    current_rmem=$(read_sysctl_number net.core.rmem_max)
    current_wmem=$(read_sysctl_number net.core.wmem_max)
    target_rmem=$(larger_number "${current_rmem:-0}" "$UDP_BUFFER_MIN_BYTES")
    target_wmem=$(larger_number "${current_wmem:-0}" "$UDP_BUFFER_MIN_BYTES")
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
    if [ "$current_cc" = "bbr" ]; then
        request_bbr="TRUE"
    fi

    mkdir -p "$(dirname "$NETWORK_SYSCTL_FILE")"
    temp_file=$(mktemp) || error "无法创建网络优化临时文件"
    {
        echo "# Managed by install-singboxhysteria2"
        echo "# Keep UDP socket buffer limits at least 16 MiB for Hysteria2/QUIC."
        echo "net.core.rmem_max = $target_rmem"
        echo "net.core.wmem_max = $target_wmem"
        if [ "$request_bbr" = "TRUE" ]; then
            echo "# TCP tuning for Reality and proxied TCP traffic."
            echo "net.core.default_qdisc = fq"
            echo "net.ipv4.tcp_congestion_control = bbr"
        fi
    } > "$temp_file"

    install -m 0644 "$temp_file" "$NETWORK_SYSCTL_FILE" || {
        rm -f "$temp_file"
        error "写入网络优化配置失败"
    }
    rm -f "$temp_file"
    sysctl -p "$NETWORK_SYSCTL_FILE" || error "应用网络优化配置失败"

    info "Hysteria2 UDP 接收缓冲上限: $(sysctl -n net.core.rmem_max)"
    info "Hysteria2 UDP 发送缓冲上限: $(sysctl -n net.core.wmem_max)"
}

configure_udp_buffers() {
    write_network_sysctl "FALSE"
}

enable_bbr() {
    local available_cc

    if command -v modprobe >/dev/null 2>&1; then
        modprobe tcp_bbr >/dev/null 2>&1 || true
    fi
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)

    if grep -qw bbr <<< "$available_cc"; then
        write_network_sysctl "TRUE"
        info "TCP BBR 已启用: $(sysctl -n net.ipv4.tcp_congestion_control)"
        info "默认队列算法: $(sysctl -n net.core.default_qdisc)"
    else
        warning "当前内核不支持 TCP BBR；不会下载第三方脚本或自动更换内核。"
        configure_udp_buffers
        return 1
    fi
}

configure_install_network() {
    # Only the fresh-install path calls this. Unsupported BBR is non-fatal;
    # enable_bbr has already kept the TCP algorithm and tuned UDP buffers.
    enable_bbr || info "已保留当前 TCP 算法，继续安装 sing-box。"
}

valid_server_name() {
    [[ ${#1} -le 253 && "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ && "$1" != *..* ]]
}

reality_target_responds() {
    valid_server_name "$1" || return 1
    curl --noproxy '*' --connect-timeout 5 --max-time 15 --tlsv1.3 --tls-max 1.3 --http2 \
        -fsSI "https://$1" | grep -q 'HTTP/2'
}

reload_current_service() {
    if systemctl is-active --quiet sing-box; then
        systemctl reload sing-box || return 1
    elif [ "${1:-}" = systemd ]; then
        systemctl restart sing-box || return 1
    else
        local pid
        pid=$(pgrep -o -x sing-box) || return 1
        kill -HUP "$pid" || return 1
    fi
    if systemctl is-active --quiet sing-box-hy2-hopping.service; then
        systemctl reload sing-box-hy2-hopping.service || return 1
    fi
}

apply_config_change() (
    # Reuse the existing config check BEFORE replacing the live file. Keep
    # backups and roll back both JSON and the SNI state on any later failure.
    local description="$1" filter="$2" hy_name="$3" candidate state_candidate=""
    local backup="" state_backup="" committed=0 running=no
    shift 3
    exec 9>>"$SB_DIR/config.lock" || return 1
    flock -w 15 9 || return 1
    candidate=$(mktemp "$SB_SERVER_CONFIG.candidate.XXXXXX") || return 1
    finish_config_change() {
        local result=$? restore_candidate
        trap - EXIT
        if [ "$result" -ne 0 ] && [ "$committed" = 1 ]; then
            restore_candidate=$(mktemp "$SB_SERVER_CONFIG.restore.XXXXXX") &&
                cp -p "$backup" "$restore_candidate" && mv -f "$restore_candidate" "$SB_SERVER_CONFIG" || {
                  warning "恢复配置失败，请保留备份并人工恢复: $backup"; exit 1;
                }
            if [ -n "$state_backup" ]; then
                cp -p "$state_backup" "$SB_STATE_FILE" || { warning "恢复节点记录失败: $state_backup"; exit 1; }
            fi
            if [ "$running" != no ]; then
                reload_current_service "$running" || warning "文件已恢复，服务需人工检查。"
            fi
            warning "修改未完成，已恢复修改前文件。备份: $backup"
        fi
        rm -f -- "$candidate" ${state_candidate:+"$state_candidate"}
        exit "$result"
    }
    trap finish_config_change EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    jq "$@" "$filter" "$SB_SERVER_CONFIG" > "$candidate" || return 1
    "$SB_BIN" check -c "$candidate" || return 1
    if [ -n "$hy_name" ]; then
        valid_server_name "$hy_name" || return 1
        state_candidate=$(mktemp "$SB_STATE_FILE.candidate.XXXXXX") || return 1
        awk -v replacement="HY_SERVER_NAME='$hy_name'" '
          /^HY_SERVER_NAME=/ {print replacement; found=1; next} {print}
          END {if (!found) print replacement}
        ' "$SB_STATE_FILE" > "$state_candidate" || return 1
        state_backup=$(mktemp "$SB_STATE_FILE.bak.XXXXXX") || return 1
        cp -p "$SB_STATE_FILE" "$state_backup" || return 1
        chmod --reference="$SB_STATE_FILE" "$state_candidate" || return 1
    fi
    backup=$(mktemp "$SB_SERVER_CONFIG.bak.XXXXXX") || return 1
    cp -p "$SB_SERVER_CONFIG" "$backup" || return 1
    chmod --reference="$SB_SERVER_CONFIG" "$candidate" || return 1
    if systemctl is-active --quiet sing-box; then running=systemd
    elif pgrep -x sing-box >/dev/null; then running=manual; fi
    mv -f -- "$candidate" "$SB_SERVER_CONFIG" || return 1
    committed=1
    [ -z "$state_candidate" ] || mv -f -- "$state_candidate" "$SB_STATE_FILE" || return 1
    if [ "$running" != no ]; then
        reload_current_service "$running" || return 1
        # SIGHUP is asynchronous. Use the existing listener check after reload.
        sleep 1
        if [ "$running" = systemd ]; then wait_kernel_runtime || return 1; fi
    fi
    committed=0
    info "已完成: $description；配置备份: $backup"
)

delete_forward_rule() {
    local tag="$1"
    [[ "$tag" == direct-in* ]] || { warning "只能删除任意门中转规则。"; return 1; }
    apply_config_change "删除中转规则 $tag" '
      if any(.inbounds[]; .tag == $tag and .type == "direct") then
        del(.inbounds[] | select(.tag == $tag and .type == "direct")) |
        del(.outbounds[] | select(.tag == ($tag + "-out"))) |
        .route.rules |= map(
          if .inbound == $tag then empty
          elif (.inbound | type) == "array" then
            .inbound |= map(select(. != $tag)) | select((.inbound | length) > 0)
          else . end)
      else error("没有对应的任意门入站") end
    ' '' --arg tag "$tag"
}

modify_singbox() {
    echo ""
    warning "开始修改VISION_REALITY 端口号和域名"
    echo ""
    reality_current_port=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .listen_port' /root/sbox/sbconfig_server.json)
    reality_port=$(modify_port "$reality_current_port" "VISION_REALITY") || return 1
    info "生成的端口号为: $reality_port"
    reality_current_server_name=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .tls.server_name' /root/sbox/sbconfig_server.json)
    reality_server_name="$reality_current_server_name"
    while :; do
        read -r -p "请输入 Reality 握手域名 (默认: $reality_server_name): " input_server_name || return 1
        reality_server_name=${input_server_name:-$reality_server_name}
        if reality_target_responds "$reality_server_name"; then
            break
        else
            warning "域名 $reality_server_name 不支持 TLS 1.3 或 HTTP/2，请重新输入."
        fi
    done
    info "域名 $reality_server_name 符合标准"
    echo ""
    warning "开始修改hysteria2端口号"
    echo ""
    hy_current_port=$(jq -r '.inbounds[] | select(.tag == "hy2-in") | .listen_port' /root/sbox/sbconfig_server.json)
    hy_port=$(modify_port "$hy_current_port" "HYSTERIA2") || return 1
    info "生成的端口号为: $hy_port"
    info "修改hysteria2应用证书路径"
    hy_current_cert=$(jq -r '.inbounds[] | select(.tag == "hy2-in") | .tls.certificate_path' /root/sbox/sbconfig_server.json)
    hy_current_key=$(jq -r '.inbounds[] | select(.tag == "hy2-in") | .tls.key_path' /root/sbox/sbconfig_server.json)
    hy_current_domain=$(grep -o "HY_SERVER_NAME='[^']*'" /root/sbox/config | awk -F"'" '{print $2}')
    read -r -p "请输入证书域名 (默认: $hy_current_domain): " hy_domain || return 1
    hy_domain=${hy_domain:-$hy_current_domain}
    read -r -p "请输入证书cert路径 (默认: $hy_current_cert): " hy_cert || return 1
    hy_cert=${hy_cert:-$hy_current_cert}
    read -r -p "请输入证书key路径 (默认: $hy_current_key): " hy_key || return 1
    hy_key=${hy_key:-$hy_current_key}
    apply_config_change "修改端口和 TLS 配置" '
    (.inbounds[] | select(.tag == "vless-in") | .listen_port) = ($reality_port | tonumber) |
    (.inbounds[] | select(.tag == "hy2-in") | .listen_port) = ($hy_port | tonumber) |
    (.inbounds[] | select(.tag == "vless-in") | .tls.server_name) = $reality_server_name |
    (.inbounds[] | select(.tag == "vless-in") | .tls.reality.handshake.server) = $reality_server_name |
    (.inbounds[] | select(.tag == "hy2-in") | .tls.certificate_path) = $hy_cert |
    (.inbounds[] | select(.tag == "hy2-in") | .tls.key_path) = $hy_key
    ' "$hy_domain" --arg reality_port "$reality_port" \
    --arg hy_port "$hy_port" \
    --arg reality_server_name "$reality_server_name" \
    --arg hy_cert "$hy_cert" \
    --arg hy_key "$hy_key"
}

backup_current_installation() {
    local backup_dir backup_name unit_path

    backup_name="sbox-backup-$(date +%Y%m%d-%H%M%S)"
    backup_dir="/root/${backup_name}"
    install -d -m 0700 "$backup_dir" || return 1
    cp -a /root/sbox "$backup_dir/" || return 1
    unit_path="$(systemctl show sing-box -p FragmentPath --value 2>/dev/null || true)"
    if [ -n "$unit_path" ] && [ -e "$unit_path" ]; then
        cp -a "$unit_path" "$backup_dir/sing-box.service.source"
        printf '%s\n' "$unit_path" > "$backup_dir/sing-box.service.source-path.txt"
    elif [ -e /etc/systemd/system/sing-box.service ]; then
        cp -a /etc/systemd/system/sing-box.service "$backup_dir/sing-box.service.source"
    fi
    if [ -e /usr/bin/mianyang ] || [ -L /usr/bin/mianyang ]; then
        cp -a --no-dereference /usr/bin/mianyang "$backup_dir/usr-bin-mianyang"
    fi
    systemctl cat sing-box > "$backup_dir/sing-box.unit.txt" 2>&1 || true
    systemctl show sing-box -p LoadState -p ActiveState -p FragmentPath -p MainPID > "$backup_dir/sing-box.state.txt" 2>&1 || true
    ps -ef | grep '[s]ing-box' > "$backup_dir/sing-box.process.txt" 2>&1 || true
    sysctl net.core.rmem_max net.core.wmem_max net.core.default_qdisc net.ipv4.tcp_congestion_control > "$backup_dir/network-sysctl.txt" 2>&1 || true
    iptables-save > "$backup_dir/iptables.rules" 2>/dev/null || true
    ip6tables-save > "$backup_dir/ip6tables.rules" 2>/dev/null || true
    tar -C /root -czf "/root/${backup_name}.tar.gz" "$backup_name" || return 1
    chmod 0600 "/root/${backup_name}.tar.gz"
    sha256sum "/root/${backup_name}.tar.gz" > "/root/${backup_name}.tar.gz.sha256"
    info "完整备份已创建: /root/${backup_name}.tar.gz"
}

uninstall_singbox() {
    warning "开始卸载..."
    if pgrep -x sing-box >/dev/null 2>&1 && ! systemctl is-active --quiet sing-box; then
        error "sing-box 当前由手工进程运行。为防止删除运行中的配置，已拒绝卸载。"
    fi
    systemctl stop sing-box >/dev/null 2>&1 || { warning "停止 sing-box 失败，未删除文件。"; return 1; }
    if pgrep -x sing-box >/dev/null 2>&1; then
        warning "仍有 sing-box 进程运行，未删除文件。"; return 1
    fi
    disable_hy2hopping || return 1
    systemctl disable sing-box >/dev/null 2>&1 || return 1
    rm -f /etc/systemd/system/sing-box.service
    rm -f /root/sbox/sbconfig_server.json /root/sbox/sing-box /root/sbox/mianyang.sh
    rm -f /usr/bin/mianyang /root/sbox/self-cert/private.key /root/sbox/self-cert/cert.pem /root/sbox/config
    rm -rf /root/sbox/self-cert/ /root/sbox/
    systemctl daemon-reload || return 1
    warning "卸载完成"
}

restore_kernel_file() {
    local candidate
    candidate=$(mktemp "$SB_DIR/sing-box.restore.XXXXXX") || return 1
    cp -p "$1" "$candidate" && mv -f -- "$candidate" "$SB_BIN" && return 0
    rm -f -- "$candidate"
    return 1
}

kernel_runtime_ok() {
    local pid tcp udp listeners kind port network
    systemctl is-active --quiet sing-box || return 1
    pid=$(systemctl show sing-box -p MainPID --value) || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    tcp=$(ss -H -lntp) || return 1
    udp=$(ss -H -lnup) || return 1
    listeners=$(jq -r '.inbounds[] | select(.listen_port != null) |
      [.type,.listen_port,(.network // "")] | @tsv' "$SB_SERVER_CONFIG") || return 1
    while IFS=$'\t' read -r kind port network; do
        case "$kind" in vless) network=tcp ;; hysteria2) network=udp ;; direct|shadowsocks) ;; *) continue ;; esac
        if [ "$network" != udp ]; then
            grep -E "[:.]${port}[[:space:]]" <<< "$tcp" | grep -q "pid=$pid," || return 1
        fi
        if [ "$network" != tcp ]; then
            grep -E "[:.]${port}[[:space:]]" <<< "$udp" | grep -q "pid=$pid," || return 1
        fi
    done <<< "$listeners"
}

wait_kernel_runtime() {
    local attempt
    for ((attempt=0; attempt<10; attempt++)); do
      kernel_runtime_ok && return 0
      sleep 1
    done
    return 1
}

update_singbox() (
    local backup before_hash after_hash current_version
    systemctl is-active --quiet sing-box || {
      warning "只更新正在运行的 systemd 服务；手工进程或停止的服务请先处理。"; return 1;
    }
    exec 9>>"$SB_DIR/config.lock" || return 1
    flock -w 15 9 || { warning "配置锁等待超时"; return 1; }
    "$SB_BIN" check -c "$SB_SERVER_CONFIG" || return 1
    kernel_runtime_ok || { warning "现有监听检查失败，暂不更新。"; return 1; }
    current_version=$("$SB_BIN" version | awk '/^sing-box version / {print $3}') || return 1
    if [ "$current_version" = "${SING_BOX_VERSION_TAG#v}" ]; then
      info "已经是 ${SING_BOX_VERSION_TAG#v}，未下载、未重启、未修改配置。"
      return 0
    fi
    before_hash=$(sha256sum "$SB_SERVER_CONFIG") || return 1
    backup=$(mktemp "$SB_DIR/sing-box.backup-$(date +%Y%m%d-%H%M%S).XXXXXX") || return 1
    cp -p "$SB_BIN" "$backup" || return 1
    info "旧内核备份: $backup"
    if ! install_singbox; then
      warning "下载或候选内核检查失败，现有服务未重启。"; return 1;
    fi
    after_hash=$(sha256sum "$SB_SERVER_CONFIG") || after_hash=unreadable
    if [ "$before_hash" != "$after_hash" ]; then
      restore_kernel_file "$backup" || { warning "恢复旧内核失败，请人工恢复: $backup"; return 1; }
      warning "更新期间配置发生变化，已恢复旧内核，未重启。"; return 1;
    fi
    if systemctl restart sing-box && wait_kernel_runtime; then
      if systemctl is-active --quiet sing-box-hy2-hopping.service; then
        if ! systemctl reload sing-box-hy2-hopping.service; then
          warning "内核已启动，端口跳跃刷新失败，请检查跳跃服务。"; return 1;
        fi
      fi
      info "内核更新完成：${SING_BOX_VERSION_TAG#v}。现有 UUID、密钥、密码、端口和配置未修改。"
      return 0
    fi
    warning "新版启动失败，正在恢复旧内核..."
    restore_kernel_file "$backup" || { warning "恢复旧内核失败，请人工恢复: $backup"; return 1; }
    if systemctl restart sing-box && wait_kernel_runtime; then
      warning "已恢复旧内核并启动服务。"
    else
      warning "旧内核已恢复，但服务未能确认恢复，请人工检查。备份: $backup"
    fi
    return 1
)

generate_random_number() {
    # Generates an 8-digit random number
    echo $((10000000 + RANDOM % 90000000))
}
process_doko() {
  local choice fport ipaddress tport tag_suffix tag delete_tag
  while :; do
      echo "已配置的任意门转发规则如下:"
      jq '.inbounds[] | select((.tag // "") | startswith("direct-in")) | "\(.tag): 转发至ip \(.override_address // "未设置"), 转发至端口 \(.override_port // "未设置")"' "$SB_SERVER_CONFIG"
      echo ""
      echo "选择操作:"
      echo "1. 添加规则"
      echo "2. 删除规则"
      echo "0. 退出"
      read -r -p "请输入选择的操作数字（0-2）: " choice || return 1
      case $choice in
          1)
              fport=$(generate_port "本机任意门入站") || return 1
              echo "本机端口为: $fport"
              read -r -p "请输入转发至的vps ip或域名: " ipaddress || return 1
              read -r -p "请输入转发至的vps端口: " tport || return 1
              valid_port "$tport" || { warning "目标端口必须在 1～65535 之间。"; continue; }
              tport=$((10#$tport))
              [ -n "$ipaddress" ] || { warning "目标地址不能为空。"; continue; }

              # Generate an 8-digit random number as tag_suffix
              tag_suffix=$(generate_random_number)

              tag="direct-in${tag_suffix}"

              apply_config_change "添加任意门 $tag" '
                  .inbounds += [
                      {
                          "type": "direct",
                          "tag": $tag,
                          "listen": "::",
                          "override_address": $ipaddress,
                          "override_port": ($tport | tonumber),
                          "listen_port": ($fport | tonumber)
                      }
                  ] | .route.rules += [
                      {
                          "inbound": $tag,
                          "outbound": "direct"
                      }
                  ]' '' --arg ipaddress "$ipaddress" --arg fport "$fport" --arg tport "$tport" --arg tag "$tag" || return 1
              ;;
          2)
              echo "请输入要删除的任意门规则标签 (例如：direct-in1): "
              read -r delete_tag || return 1
              delete_forward_rule "$delete_tag" || return 1
              ;;
          0)
              echo "退出"
              return 0
              ;;
          *)
              echo "无效的选择"
              ;;
      esac
    done
}
process_dokoko() {
    local existing_port delete_option
    existing_port=$(jq -r '.inbounds[] | select(.tag == "direct-in") | .listen_port' "$SB_SERVER_CONFIG") || return 1
    if [ -n "$existing_port" ] && [ "$existing_port" != null ]; then
        info "已有旧版任意门落地入站，监听端口: $existing_port"
        read -r -p "是否删除该旧配置？ (y/n): " delete_option || return 1
        [ "$delete_option" != y ] || delete_forward_rule direct-in
        return $?
    fi
    warning "旧版任意门落地方案无法在当前配置中正确转发目标域名，已停止生成无效配置。"
    warning "请使用菜单 9 的 SS 落地方式；本次未修改现有节点。"
    return 1
}

process_ssko() {
    local config_file tag existing_port existing_pwd server_ip delete_option fport sspwd
    warning "开始SS落地机设置"
    config_file="$SB_SERVER_CONFIG"
    tag="ss-in"
    existing_port=$(jq -r --arg tag "$tag" '.inbounds[] | select(.tag == $tag) | .listen_port' "$config_file")
    existing_pwd=$(jq -r --arg tag "$tag" '.inbounds[] | select(.tag == $tag) | .password' "$config_file")
    server_ip=$(grep -o "SERVER_IP='[^']*'" /root/sbox/config | awk -F"'" '{print $2}')

    if [ -n "$existing_port" ] && [ "$existing_port" != "null" ]; then
        info "已存在ss入站配置,监听端口号为: $existing_port"
        info "已存在ss入站配置,密码为: $existing_pwd"
        info "本机ip为: $server_ip"
        echo ""
        read -r -p "是否删除已存在的配置？ (y/n): " delete_option || return 1
        if [ "$delete_option" = "y" ]; then
            apply_config_change "删除 SS 落地入站" '.inbounds |= map(select(.tag != $tag or .type != "shadowsocks"))' '' --arg tag "$tag"
        else
            echo "未删除配置"
        fi
    else
        fport=$(generate_port "SS 落地入站") || return 1
        sspwd=$("$SB_BIN" generate rand 16 --base64) || return 1
        info "监听端口号为: $fport"
        info "ss密码为：$sspwd"
        info "本机ip为: $server_ip"
        apply_config_change "添加 SS 落地入站" '
            .inbounds += [
                {
                    "type": "shadowsocks",
                    "tag": "ss-in",
                    "listen": "::",
                    "listen_port": ($fport | tonumber),
                    "method": "2022-blake3-aes-128-gcm",
                    "password": $sspwd
                }
            ]' '' --arg sspwd "$sspwd" --arg fport "$fport"
    fi
}

process_singbox() {
  while :; do
    echo ""
    echo ""
    info "请选择选项："
    echo ""
    info "1. 检查配置并重启 sing-box"
    info "2. 安全更新 sing-box 内核"
    info "3. 查看 systemd 服务状态"
    info "4. 查看实时日志（Ctrl+C 退出）"
    info "5. 查看服务端配置（包含密钥）"
    info "0. 退出"
    echo ""
    read -r -p "请输入对应数字（0-5）: " user_input || return 1
    echo ""
    case "$user_input" in
        1)
            warning "重启sing-box..."
            # 检查配置
            if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
              info "检查配置文件，启动服务..."
              restart_singbox || return 1
            fi
            break
            ;;
        2)
            update_singbox || return 1
            break
            ;;
        3)
            info "sing-box systemd 状态如下："
            systemctl status sing-box --no-pager
            break
            ;;
        4)
            warning "singbox日志如下(ctrl+c退出)："
            journalctl -u sing-box -o cat -f
            break
            ;;
        5)
            warning "以下服务端配置包含 UUID、密码和私钥，请勿公开："
            cat /root/sbox/sbconfig_server.json
            break
            ;;
        0)
          echo "退出"
          break
          ;;
        *)
            echo "请输入正确选项: 0-5"
            ;;
    esac
  done
}

process_hy2hopping(){
        while :; do
          ishopping=$(grep '^HY_HOPPING=' /root/sbox/config | cut -d'=' -f2)
          if [ "$ishopping" = "FALSE" ]; then
              warning "开始设置端口跳跃范围..."
              enable_hy2hopping || return 1
              return 0
          else
              warning "端口跳跃已开启"
              echo ""
              info "请选择选项："
              echo ""
              info "1. 关闭端口跳跃"
              info "2. 重新设置"
              info "3. 查看规则"
              info "0. 退出"
              echo ""
              read -r -p "请输入对应数字（0-3）: " hopping_input || return 1
              echo ""
              case $hopping_input in
                1)
                  disable_hy2hopping
                  echo "端口跳跃规则已删除"
                  break
                  ;;
                2)
                  disable_hy2hopping
                  echo "端口跳跃规则已删除"
                  echo "开始重新设置端口跳跃"
                  enable_hy2hopping
                  break
                  ;;
                3)
                  # 查看NAT规则
                  iptables -t nat -L PREROUTING -n -v --line-numbers 2>/dev/null | grep "$HY_HOPPING_COMMENT"
                  ip6tables -t nat -L PREROUTING -n -v --line-numbers 2>/dev/null | grep "$HY_HOPPING_COMMENT"
                  break
                  ;;
                0)
                  echo "退出"
                  break
                  ;;
                *)
                  echo "无效的选项,请重新选择"
                  ;;
              esac
          fi
        done
}
# 开启hysteria2端口跳跃
HY_HOPPING_COMMENT="sing-box-hy2-hopping"
HY_HOPPING_HELPER="/root/sbox/hy2-hopping.sh"
HY_HOPPING_SERVICE="/etc/systemd/system/sing-box-hy2-hopping.service"

set_config_value() {
    local key="$1"
    local value="$2"
    local config_file="/root/sbox/config"

    if grep -q "^${key}=" "$config_file" 2>/dev/null; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$config_file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$config_file"
    fi
}

remove_hy2_hopping_rules() {
    local firewall rule_number

    for firewall in iptables ip6tables; do
        command -v "$firewall" >/dev/null 2>&1 || continue
        while :; do
            rule_number=$("$firewall" -t nat -L PREROUTING -n -v --line-numbers 2>/dev/null |
                awk -v marker="$HY_HOPPING_COMMENT" 'index($0, marker) {print $1; exit}')
            [ -n "$rule_number" ] || break
            "$firewall" -t nat -D PREROUTING "$rule_number" >/dev/null 2>&1 || break
        done
    done
}

install_hy2_hopping_helper() {
    cat > "$HY_HOPPING_HELPER" <<'EOF'
#!/usr/bin/env bash
set -u

CONFIG_FILE="/root/sbox/config"
SERVER_CONFIG="/root/sbox/sbconfig_server.json"
RULE_COMMENT="sing-box-hy2-hopping"

remove_rules() {
    local firewall rule_number
    for firewall in iptables ip6tables; do
        command -v "$firewall" >/dev/null 2>&1 || continue
        while :; do
            rule_number=$("$firewall" -t nat -L PREROUTING -n -v --line-numbers 2>/dev/null |
                awk -v marker="$RULE_COMMENT" 'index($0, marker) {print $1; exit}')
            [ -n "$rule_number" ] || break
            "$firewall" -t nat -D PREROUTING "$rule_number" >/dev/null 2>&1 || break
        done
    done
}

apply_rules() {
    local hy_port applied firewall hy_hopping hy_hopping_start hy_hopping_end
    [ -f "$CONFIG_FILE" ] || { echo "Missing $CONFIG_FILE" >&2; return 1; }
    hy_hopping=$(sed -n 's/^HY_HOPPING=//p' "$CONFIG_FILE" | tail -n 1 | tr -d "'\"")
    hy_hopping_start=$(sed -n 's/^HY_HOPPING_START=//p' "$CONFIG_FILE" | tail -n 1 | tr -d "'\"")
    hy_hopping_end=$(sed -n 's/^HY_HOPPING_END=//p' "$CONFIG_FILE" | tail -n 1 | tr -d "'\"")
    [ "$hy_hopping" = "TRUE" ] || { remove_rules; return 0; }
    [[ "$hy_hopping_start" =~ ^[0-9]+$ ]] || { echo "Invalid HY_HOPPING_START" >&2; return 1; }
    [[ "$hy_hopping_end" =~ ^[0-9]+$ ]] || { echo "Invalid HY_HOPPING_END" >&2; return 1; }
    (( hy_hopping_start >= 1 && hy_hopping_end <= 65535 && hy_hopping_start <= hy_hopping_end )) || {
        echo "Invalid Hysteria2 hopping range" >&2
        return 1
    }

    hy_port=$(jq -r '.inbounds[] | select(.tag == "hy2-in") | .listen_port' "$SERVER_CONFIG")
    [[ "$hy_port" =~ ^[0-9]+$ ]] || { echo "Invalid Hysteria2 listen port" >&2; return 1; }

    remove_rules
    applied=0
    for firewall in iptables ip6tables; do
        command -v "$firewall" >/dev/null 2>&1 || continue
        if "$firewall" -t nat -A PREROUTING -p udp \
            --dport "${hy_hopping_start}:${hy_hopping_end}" \
            -m comment --comment "$RULE_COMMENT" \
            -j REDIRECT --to-ports "$hy_port"; then
            applied=1
        fi
    done
    (( applied == 1 )) || { echo "Failed to apply Hysteria2 hopping rules" >&2; return 1; }
}

case "${1:-apply}" in
    apply) apply_rules ;;
    remove) remove_rules ;;
    *) echo "Usage: $0 {apply|remove}" >&2; exit 2 ;;
esac
EOF
    chmod 0755 "$HY_HOPPING_HELPER"

    cat > "$HY_HOPPING_SERVICE" <<'EOF'
[Unit]
Description=Persistent Hysteria2 port hopping rules for sing-box
After=network-online.target sing-box.service
Wants=network-online.target
PartOf=sing-box.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/root/sbox/hy2-hopping.sh apply
ExecReload=/root/sbox/hy2-hopping.sh apply
ExecStop=/root/sbox/hy2-hopping.sh remove

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

enable_hy2hopping(){
    hint "开启端口跳跃..."
    warning "注意: 端口跳跃范围不要覆盖已经占用的端口，否则会错误！"
    while :; do
        read -r -p "输入UDP端口范围的起始值(默认50000): " start_port || return 1
        start_port=${start_port:-50000}
        read -r -p "输入UDP端口范围的结束值(默认51000): " end_port || return 1
        end_port=${end_port:-51000}
        if valid_port "$start_port" && valid_port "$end_port" &&
           (( 10#$start_port <= 10#$end_port )); then
            start_port=$((10#$start_port)); end_port=$((10#$end_port))
            break
        fi
        warning "端口范围无效，必须满足 1 <= 起始端口 <= 结束端口 <= 65535。"
    done

    set_config_value HY_HOPPING_START "$start_port"
    set_config_value HY_HOPPING_END "$end_port"
    set_config_value HY_HOPPING TRUE
    install_hy2_hopping_helper

    if systemctl enable --now sing-box-hy2-hopping.service; then
        info "端口跳跃已开启并设置为重启后自动恢复: ${start_port}-${end_port}"
        warning "请同时确认云防火墙和本机防火墙已放行该 UDP 端口范围。"
    else
        systemctl disable --now sing-box-hy2-hopping.service >/dev/null 2>&1 || true
        set_config_value HY_HOPPING FALSE
        remove_hy2_hopping_rules
        rm -f "$HY_HOPPING_SERVICE" "$HY_HOPPING_HELPER"
        systemctl daemon-reload
        error "端口跳跃规则应用失败，已回退为关闭状态"
    fi
}

disable_hy2hopping(){
  echo "正在关闭端口跳跃..."
  if [ -f "$HY_HOPPING_SERVICE" ]; then
      systemctl disable --now sing-box-hy2-hopping.service >/dev/null 2>&1 || true
  fi
  remove_hy2_hopping_rules
  set_config_value HY_HOPPING FALSE
  set_config_value HY_HOPPING_START ""
  set_config_value HY_HOPPING_END ""
  rm -f "$HY_HOPPING_SERVICE" "$HY_HOPPING_HELPER"
  systemctl daemon-reload
  echo "关闭完成"
}

#--------------------------------
INSTALLATION_MARKERS=(
    /root/sbox/sbconfig_server.json
    /root/sbox/config
    /root/sbox/mianyang.sh
    /usr/bin/mianyang
    /root/sbox/sing-box
    /etc/systemd/system/sing-box.service
    /lib/systemd/system/sing-box.service
    /usr/lib/systemd/system/sing-box.service
)

has_any_installation_marker() {
    local marker
    for marker in "${INSTALLATION_MARKERS[@]}"; do
        if [ -e "$marker" ] || [ -L "$marker" ]; then
            return 0
        fi
    done
    return 1
}

show_installation_markers() {
    local marker service_unit=""
    for marker in \
        /root/sbox/sbconfig_server.json \
        /root/sbox/config \
        /root/sbox/sing-box; do
        if [ -e "$marker" ] || [ -L "$marker" ]; then
            info "存在: $marker"
        else
            warning "缺失: $marker"
        fi
    done

    if [ -x /root/sbox/mianyang.sh ] && { [ -e /usr/bin/mianyang ] || [ -L /usr/bin/mianyang ]; }; then
        info "管理命令: /usr/bin/mianyang"
    else
        warning "管理命令不完整: /usr/bin/mianyang"
    fi

    service_unit=$(systemctl show sing-box -p FragmentPath --value 2>/dev/null || true)
    if [ -z "$service_unit" ] || [ ! -e "$service_unit" ]; then
        for marker in \
            /etc/systemd/system/sing-box.service \
            /lib/systemd/system/sing-box.service \
            /usr/lib/systemd/system/sing-box.service; do
            if [ -e "$marker" ]; then
                service_unit="$marker"
                break
            fi
        done
    fi
    if [ -n "$service_unit" ] && [ -e "$service_unit" ]; then
        info "systemd 服务文件: $service_unit"
    else
        warning "未找到 sing-box.service"
    fi
}

main() {
[ "$(id -u)" -eq 0 ] || error "请在 VPS 的 root 会话中运行。"
print_with_delay "Reality Hysteria2 二合一脚本" 0.03
echo ""
echo ""

# Any existing marker blocks the automatic fresh-install path. This prevents a
# missing shortcut or service file from causing silent key/config regeneration.
if has_any_installation_marker; then
    if [ ! -f /root/sbox/sbconfig_server.json ] ||
       [ ! -f /root/sbox/config ] ||
       [ ! -x /root/sbox/sing-box ]; then
        warning "检测到不完整或非标准的现有安装。为防止覆盖 Reality/Hysteria2 配置，脚本已停止。"
        show_installation_markers
        error "请先备份并修复缺失文件，不会自动执行全新安装"
    fi

    install_pkgs || error "基础工具安装失败，已停止。"
    install_shortcut || error "修复 Personal 管理入口失败。"
    echo ""
    info "sing-box-reality-hysteria2 已安装"
    show_status
    echo ""
    hint "=======常规配置========="
    hint "请选择选项:"
    echo ""
    info "1. 重新安装"
    info "2. 修改配置"
    info "3. 显示客户端配置和 Linux 安装命令"
    info "4. sing-box基础操作"
    info "5. 启用本地 BBR + 优化 Hysteria2 UDP 缓冲"
    info "6. Hysteria2 端口跳跃"
    info "7. 本机添加任意门中转规则（本机做中转机）"
    info "0. 卸载"
    echo ""
    hint "=======落地机解锁配置======"
    echo ""
    info "8. 清理旧任意门落地配置（新建请用 SS）"
    info "9. 落地机 SS 解锁（本机做解锁机）"
    echo ""
    hint "========================="
    echo ""
    read -r -p "请输入对应数字 (0-9): " choice || return 1

    case $choice in
      1)
          warning "重新安装会生成新的 Reality 密钥、UUID、端口和 Hysteria2 密码。"
          read -r -p "如已确认，请输入 REINSTALL 继续: " reinstall_confirm
          if [ "$reinstall_confirm" != "REINSTALL" ]; then
              warning "输入不匹配，已取消重新安装"
              exit 0
          fi
          backup_current_installation || error "重新安装前备份失败，已停止"
          uninstall_singbox || error "卸载未完成，已停止重新安装。"
        ;;
      2)
          modify_singbox || return 1
          show_client_configuration
          exit 0
        ;;
      3)
          show_client_configuration
          exit 0
      ;;
      4)
          process_singbox
          exit $?
          ;;
      5)
          enable_bbr
          exit 0
          ;;
      6)
          process_hy2hopping
          exit $?
          ;;
      7)
          process_doko
          exit $?
          ;;
      8)
          process_dokoko
          exit $?
          ;;
      9)
          process_ssko
          exit $?
          ;;
      0)
          uninstall_singbox
	        exit $?
          ;;
      *)
          echo "选择错误，退出"
          exit 1
          ;;
	esac
	fi

install_pkgs || error "基础工具安装失败，已停止。"
mkdir -p "/root/sbox/"
exec 9>>"$SB_DIR/config.lock" || return 1
flock -w 15 9 || error "另一个安装或修改正在运行，请稍后再试。"
has_any_installation_marker && error "检测到已有安装文件，未执行全新安装。"
pgrep -x sing-box >/dev/null 2>&1 && error "已有 sing-box 进程运行，未执行全新安装。"

install_singbox || error "内核下载或验证失败，已停止。"
echo ""
echo ""

warning "开始配置VISION_REALITY..."
echo ""
key_pair=$(/root/sbox/sing-box generate reality-keypair) || return 1
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
info "生成的公钥为:  $public_key"
reality_uuid=$(/root/sbox/sing-box generate uuid) || return 1
short_id=$(/root/sbox/sing-box generate rand --hex 8) || return 1
info "生成的uuid为:  $reality_uuid"
info "生成的短id为:  $short_id"
echo ""
reality_port=$(generate_port "VISION_REALITY") || return 1
info "生成的端口号为: $reality_port"
reality_server_name="itunes.apple.com"
while :; do
    read -r -p "请输入 Reality 握手域名 (默认: $reality_server_name): " input_server_name || return 1
    reality_server_name=${input_server_name:-$reality_server_name}

    if reality_target_responds "$reality_server_name"; then
        break
    else
        echo "域名 $reality_server_name 不支持 TLS 1.3 或 HTTP/2，请重新输入."
    fi
done
info "域名 $reality_server_name 符合."
echo ""
echo ""
# hysteria2
warning "开始配置hysteria2..."
echo ""
hy_password=$(/root/sbox/sing-box generate rand --hex 8) || return 1
info "password: $hy_password"
echo ""
hy_port=$(generate_port "HYSTERIA2") || return 1
info "生成的端口号为: $hy_port"
read -r -p "输入自签证书域名 (默认为: bing.com): " hy_server_name || return 1
hy_server_name=${hy_server_name:-bing.com}
valid_server_name "$hy_server_name" || error "证书域名格式不正确。"
mkdir -p /root/sbox/self-cert/ && openssl ecparam -genkey -name prime256v1 -out /root/sbox/self-cert/private.key && openssl req -new -x509 -days 36500 -key /root/sbox/self-cert/private.key -out /root/sbox/self-cert/cert.pem -subj "/CN=${hy_server_name}" || error "生成自签证书失败，已停止。"
info "自签证书生成完成,保存于/root/sbox/self-cert/"
echo ""
echo ""
#get ip
server_ip=$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org) || \
    server_ip=$(curl -6fsS --connect-timeout 5 --max-time 10 https://api64.ipify.org) || error "无法取得服务器公网 IP，已停止。"

#generate config
cat > /root/sbox/config <<EOF
# VPS ip
SERVER_IP='$server_ip'
# Reality
PUBLIC_KEY='$public_key'
# Hysteria2
HY_SERVER_NAME='$hy_server_name'
HY_HOPPING=FALSE
HY_HOPPING_START=
HY_HOPPING_END=
EOF
[ $? -eq 0 ] || error "保存节点信息失败，已停止。"

#generate singbox server config
cat > /root/sbox/sbconfig_server.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-local",
        "type": "local"
      }
    ]
  },
  "route": {
    "rules": [
      {
        "action": "sniff"
      }
    ]
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $reality_port,
      "users": [
        {
          "uuid": "$reality_uuid",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$reality_server_name",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$reality_server_name",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
    {
        "type": "hysteria2",
        "tag": "hy2-in",
        "listen": "::",
        "listen_port": $hy_port,
        "ignore_client_bandwidth": true,
        "users": [
            {
                "password": "$hy_password"
            }
        ],
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "/root/sbox/self-cert/cert.pem",
            "key_path": "/root/sbox/self-cert/private.key"
        }
    }
  ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct",
            "domain_resolver": {
                "server": "dns-local",
                "strategy": "ipv4_only"
            }
        }
    ]
}
EOF

configure_install_network

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root/sbox
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/root/sbox/sing-box run -c /root/sbox/sbconfig_server.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF

if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
    hint "check config profile..."
    systemctl daemon-reload || error "刷新 systemd 失败"
    systemctl enable sing-box > /dev/null 2>&1 || error "设置开机启动失败"
    systemctl start sing-box || error "启动失败，请查看 journalctl -u sing-box"
    wait_kernel_runtime || error "监听检查失败，请查看 journalctl -u sing-box"
    install_shortcut || error "写入 Personal 管理入口失败。"
    show_client_configuration
    warning "输入mianyang,即可打开菜单"
else
    error "配置文件检查失败，启动失败!"
fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
