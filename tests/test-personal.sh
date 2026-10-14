#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
# shellcheck source=../install.sh
source "$ROOT/install.sh"
info() { printf '%s\n' "$*"; }
warning() { printf '%s\n' "$*"; }
hint() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# The core installer and update functions must not bootstrap monitoring.
if grep -qE 'maybe_migrate_existing_api_auth|repair_existing_install_security_baseline|"type": "api"|"services":|"acl:setfacl|"util-linux:runuser' "$ROOT/install.sh"; then
    fail 'monitoring bootstrap remained'
fi
if grep -q 'https://raw.githubusercontent.com/yikkrrtykj/install-singboxhysteria2/main' "$ROOT/install.sh"; then
    fail 'manager or gateway downloads upstream'
fi
if grep -q '"port": 443' "$ROOT/install.sh"; then fail 'UDP 443 policy returned'; fi
SB_SHORTCUT_FILE="$TMP/manager" SB_SHORTCUT_LINK="$TMP/mianyang"
install_shortcut
bash -n "$SB_SHORTCUT_FILE"
grep -q 'singboxhysteria2-personal/main/install.sh' "$SB_SHORTCUT_FILE" || fail 'wrong shortcut source'
grep -q 'bash "$task_script" "$@"' "$SB_SHORTCUT_FILE" || fail 'shortcut loses arguments'

# Core update must preserve config byte-for-byte, reject bad candidates, and
# recover a running old kernel when the new kernel cannot start.
mkdir "$TMP/updates"
SB_DIR="$TMP/updates" SB_BIN="$TMP/updates/sing-box" SB_SERVER_CONFIG="$TMP/updates/server.json"
cat > "$TMP/old-bin" <<'EOF'
#!/usr/bin/env bash
# old
if [[ "$1" == version ]]; then printf 'sing-box version 1.13.16\n'; fi
exit 0
EOF
cat > "$TMP/new-bin" <<'EOF'
#!/usr/bin/env bash
# new
exit 0
EOF
chmod +x "$TMP/old-bin" "$TMP/new-bin"
task_original='{"inbounds":[{"tag":"vless-in","listen_port":11605,"users":[{"uuid":"keep-uuid"}],"tls":{"reality":{"private_key":"keep-key"}}},{"tag":"hy2-in","listen_port":10159,"users":[{"password":"keep-password"}]}],"route":{"rules":[{"action":"sniff"}]},"services":[{"type":"api","tag":"existing-api"}]}'
systemctl() {
    printf '%s\n' "$*" >> "$TMP/service.calls"
    case "$1" in
        is-active) [[ "$*" != *hopping* ]] ;;
        restart) [[ "$CASE_MODE" != failed-start ]] || grep -q '# old' "$SB_BIN" ;;
        *) return 0 ;;
    esac
}
kernel_runtime_ok() { :; }
for CASE_MODE in ok rejected failed-start; do
    printf '%s\n' "$task_original" > "$SB_SERVER_CONFIG"
    cp "$SB_SERVER_CONFIG" "$TMP/original.json"
    cp "$TMP/old-bin" "$SB_BIN"
    : > "$TMP/service.calls"
    # Run overrides in a subshell so official downloader remains available below.
    if (
        install_singbox() {
            [[ "$CASE_MODE" != rejected ]] || return 1
            cp "$TMP/new-bin" "$SB_DIR/candidate"
            mv -f "$SB_DIR/candidate" "$SB_BIN"
        }
        update_singbox
    ); then
        [[ "$CASE_MODE" == ok ]] || fail "$CASE_MODE should fail"
        grep -q '# new' "$SB_BIN" || fail 'new kernel not committed'
    else
        [[ "$CASE_MODE" != ok ]] || fail 'normal update failed'
        grep -q '# old' "$SB_BIN" || fail 'old kernel not restored'
        if [[ "$CASE_MODE" == rejected ]] && grep -q '^restart' "$TMP/service.calls"; then fail 'candidate rejection restarted service'; fi
    fi
    cmp "$TMP/original.json" "$SB_SERVER_CONFIG" || fail 'update changed credentials or API'
done
unset -f systemctl kernel_runtime_ok
printf 'PASS: Personal shortcut, no monitor bootstrap, update rollback and config preservation\n'

# Validate the actual old-style installation template with the official 1.14.3 binary.
mkdir "$TMP/real"
SB_DIR="$TMP/real" SB_BIN="$TMP/real/sing-box" SB_SERVER_CONFIG="$TMP/real/server.json"
install_singbox
pair=$("$SB_BIN" generate reality-keypair)
private_key=$(awk '/PrivateKey:/ {print $2}' <<< "$pair")
public_key=$(awk '/PublicKey:/ {print $2}' <<< "$pair")
reality_uuid=$("$SB_BIN" generate uuid)
short_id=$("$SB_BIN" generate rand --hex 8)
hy_password=$("$SB_BIN" generate rand --hex 8)
reality_port=11605 hy_port=10159 reality_server_name=itunes.apple.com hy_server_name=bing.com
mkdir "$TMP/real/self-cert"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
    -keyout "$TMP/real/self-cert/private.key" -out "$TMP/real/self-cert/cert.pem" -subj '/CN=bing.com' >/dev/null 2>&1
awk '/#generate singbox server config/ {found=1;next} found {print} found && /^EOF$/ {exit}' "$ROOT/install.sh" \
    | sed "s|/root/sbox|$TMP/real|g" > "$TMP/template.sh"
# shellcheck source=/dev/null
source "$TMP/template.sh"
mv "$TMP/real/sbconfig_server.json" "$SB_SERVER_CONFIG"
"$SB_BIN" check -c "$SB_SERVER_CONFIG"
jq -e 'has("services")|not' "$SB_SERVER_CONFIG" >/dev/null || fail 'fresh config has API'
cat > "$TMP/real/config" <<EOF
SERVER_IP='178.94.14.235'
PUBLIC_KEY='$public_key'
HY_SERVER_NAME='bing.com'
HY_HOPPING=FALSE
EOF
cp "$SB_SERVER_CONFIG" "$TMP/real/sbconfig_server.json"
# Reuse the original export function with all root paths redirected to the sandbox.
declare -f show_client_configuration | sed "s|/root/sbox|$TMP/real|g" > "$TMP/export.sh"
# shellcheck source=/dev/null
source "$TMP/export.sh"
show_notice() { :; }
qrencode() { :; }
show_client_configuration > "$TMP/exports.txt"
python3 - "$TMP/real" <<'PY'
import json, pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
s = json.loads((root / 'sbconfig_server.json').read_text())
c = yaml.safe_load((root / 'mihomo_client.yaml').read_text())
v, h = s['inbounds']
cv, ch = c['proxies'][:2]
assert cv['uuid'] == v['users'][0]['uuid']
assert cv['port'] == v['listen_port']
assert cv['servername'] == v['tls']['server_name']
assert cv['reality-opts']['short-id'] == v['tls']['reality']['short_id'][0]
assert ch['password'] == h['users'][0]['password']
assert ch['port'] == h['listen_port']
assert c['tun']['stack'] == 'mixed' and c['tun']['mtu'] == 1420
assert not any(r.get('network') == 'udp' and r.get('port') == 443 for r in s['route']['rules'])
assert root.joinpath('mihomo_client.yaml').stat().st_mode & 0o077 == 0
PY
printf 'PASS: official 1.14.3 validates fresh config; old YAML credentials match\n'
