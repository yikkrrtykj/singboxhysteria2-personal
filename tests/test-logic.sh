#!/usr/bin/env bash
# Real functions use variables and mocks indirectly through sourced code.
# shellcheck disable=SC1091,SC2034,SC2317
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
source "$ROOT/install.sh"
info() { printf '%s\n' "$*"; }
warning() { printf '%s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
(
    ss() { return 0; }
    task_port=$(generate_port test <<< $'nonsense\n70000\n0080')
    [[ "$task_port" == 80 ]] || fail 'port output polluted or leading zero mishandled'
    task_port=$(modify_port 443 test <<< '')
    [[ "$task_port" == 443 ]] || fail 'unchanged port failed'
    if generate_port test < /dev/null; then fail 'EOF accepted'; fi
    ss() { return 1; }
    if generate_port test <<< '12345'; then fail 'ss failure accepted'; fi
)

SB_DIR="$TMP/server" SB_SERVER_CONFIG="$TMP/server/server.json" SB_STATE_FILE="$TMP/server/state" SB_BIN="$TMP/server/sing-box"
mkdir "$SB_DIR"
cat > "$SB_BIN" <<'EOF'
#!/usr/bin/env bash
jq -e '(.reject_test // false) == false' "$3" >/dev/null
EOF
chmod +x "$SB_BIN"
cat > "$SB_SERVER_CONFIG" <<'EOF'
{"inbounds":[{"type":"vless","tag":"vless-in","listen_port":11605,"users":[{"uuid":"keep"}]},{"type":"hysteria2","tag":"hy2-in","listen_port":10159,"users":[{"password":"keep-password"}]},{"type":"direct","tag":"direct-in1","listen_port":18000},{"type":"direct","tag":"direct-in2","listen_port":18001}],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[{"inbound":["direct-in1","vless-in"],"outbound":"direct"}]}}
EOF
printf "HY_SERVER_NAME='old.example'\n" > "$SB_STATE_FILE"
cp "$SB_SERVER_CONFIG" "$TMP/original.json"
cp "$SB_STATE_FILE" "$TMP/original.state"
(
    MODE=normal
    sleep() { :; }
    pgrep() { return 1; }
    wait_kernel_runtime() { return 0; }
    systemctl() {
        case "$1" in
            is-active) [[ "${*: -1}" != *hopping* ]] ;;
            reload)
                printf '%s\n' "$*" >> "$TMP/reload.calls"
                if [[ "$MODE" == failed-reload ]] && jq -e 'any(.inbounds[]; .listen_port == 12001)' "$SB_SERVER_CONFIG" >/dev/null; then return 1; fi
                return 0 ;;
            *) return 0 ;;
        esac
    }
    if apply_config_change rejected '.reject_test=true' ''; then fail 'bad candidate accepted'; fi
    cmp "$TMP/original.json" "$SB_SERVER_CONFIG" || fail 'bad candidate overwrote config'
    [[ ! -e "$TMP/reload.calls" ]] || fail 'bad candidate triggered reload'
    MODE=failed-reload
    if apply_config_change failed '(.inbounds[] | select(.tag=="vless-in") | .listen_port)=12001' new.example; then fail 'reload failure ignored'; fi
    cmp "$TMP/original.json" "$SB_SERVER_CONFIG" || fail 'config rollback failed'
    cmp "$TMP/original.state" "$SB_STATE_FILE" || fail 'SNI rollback failed'
    MODE=normal
    apply_config_change success '(.inbounds[] | select(.tag=="vless-in") | .listen_port)=12002' new.example
    jq -e '.inbounds[0].users[0].uuid == "keep" and .inbounds[1].users[0].password == "keep-password"' "$SB_SERVER_CONFIG" >/dev/null || fail 'credentials changed'
    grep -q "^HY_SERVER_NAME='new.example'$" "$SB_STATE_FILE" || fail 'SNI state not updated'
    if delete_forward_rule vless-in; then fail 'proxy inbound deletion allowed'; fi
    delete_forward_rule direct-in1
    jq -e 'any(.inbounds[];.tag=="vless-in") and any(.inbounds[];.tag=="direct-in2") and .route.rules[0].inbound==["vless-in"]' "$SB_SERVER_CONFIG" >/dev/null || fail 'shared rule or unrelated inbound deleted'
    process_doko <<< '0'
    cp "$SB_SERVER_CONFIG" "$TMP/before-landing.json"
    if process_dokoko < /dev/null; then fail 'broken landing mode accepted'; fi
    cmp "$TMP/before-landing.json" "$SB_SERVER_CONFIG" || fail 'disabled landing changed config'
)
(
    systemctl() { [[ "$1" != stop ]]; }
    pgrep() { return 1; }
    rm() { printf 'delete called\n' >> "$TMP/delete.calls"; }
    if uninstall_singbox; then fail 'failed stop reported success'; fi
    [[ ! -e "$TMP/delete.calls" ]] || fail 'uninstall deleted files while service could be running'
)

# A backup missing a later source must not delete earlier live files.
mkdir -p "$TMP/gateway-backup/manifest" "$TMP/gateway-backup/rootfs"
printf 'live config\n' > "$TMP/live-config"
printf 'live binary\n' > "$TMP/live-binary"
printf 'service_active=active\n' > "$TMP/gateway-backup/state"
printf 'present\n' > "$TMP/gateway-backup/manifest/0"
printf 'present\n' > "$TMP/gateway-backup/manifest/1"
mkdir -p "$TMP/gateway-backup/rootfs$TMP"
cp "$TMP/live-config" "$TMP/gateway-backup/rootfs$TMP/live-config"
if (
    source "$ROOT/install-linux-gateway.sh"
    MANAGED_PATHS=("$TMP/live-config" "$TMP/live-binary")
    CONFIG_DIR="$TMP/live-config"
    MIHOMO_BIN="$TMP/live-binary"
    systemctl() { printf '%s\n' "$*" >> "$TMP/gateway.calls"; }
    restore_backup "$TMP/gateway-backup"
); then fail 'incomplete backup restored'; fi
[[ "$(cat "$TMP/live-config")" == 'live config' && "$(cat "$TMP/live-binary")" == 'live binary' ]] || fail 'incomplete backup deleted live files'
[[ ! -e "$TMP/gateway.calls" ]] || fail 'incomplete backup stopped live service'
cp "$TMP/live-binary" "$TMP/gateway-backup/rootfs$TMP/live-binary"
printf 'net.ipv4.ip_forward=0\n' > "$TMP/gateway-backup/network.state"
(
    source "$ROOT/install-linux-gateway.sh"
    MANAGED_PATHS=("$TMP/live-config" "$TMP/live-binary")
    CONFIG_DIR="$TMP/live-config" MIHOMO_BIN="$TMP/live-binary"
    NETWORK_KEYS=(net.ipv4.ip_forward)
    systemctl() { return 0; }
    pgrep() { return 1; }
    sysctl() { printf '%s\n' "$*" >> "$TMP/restored-network"; }
    restore_backup "$TMP/gateway-backup"
)
grep -q '^-w net.ipv4.ip_forward=0$' "$TMP/restored-network" || fail 'runtime forwarding setting not restored'
printf 'PASS: ports, config rollback, shared-rule deletion, menu exit, uninstall and incomplete gateway backup\n'
