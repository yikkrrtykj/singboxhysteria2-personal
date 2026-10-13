#!/usr/bin/env bash
# Execute the real menu functions against temporary files and mocked services.
# No server config, package installation, or network access is used by this suite.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE="$HERE/../install.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }
expect() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
extract() { awk -v name="$1" '$0 ~ "^" name "\\(\\) *\\{" {found=1} found {print} found && /^}/ {exit}' "$SOURCE"; }

export SB_SERVER_CONFIG="$TMP/server.json" SB_STATE_FILE="$TMP/state"
export SB_LOCK_FILE="$TMP/config.lock" SB_CLIENTS_DIR="$TMP/clients"
export SB_SING_BOX_BIN="$TMP/sing-box"
export SB_SHORTCUT_FILE="$TMP/manager.sh" SB_SHORTCUT_LINK="$TMP/mianyang"
export SB_HOPPING_SERVICE="$TMP/hopping.service"
awk '/# >>> phase-c client-management >>>/,/# <<< phase-d singbox-1.14-api <<</' "$SOURCE" > "$TMP/library.sh"
awk '/# >>> maintenance-config >>>/,/# <<< maintenance-config <<</' "$SOURCE" >> "$TMP/library.sh"
for task_function in install_pkgs install_shortcut validate_port port_in_use generate_port modify_port modify_singbox generate_random_number process_doko process_dokoko process_ssko; do
    extract "$task_function" >> "$TMP/library.sh"
done
# shellcheck source=/dev/null
source "$TMP/library.sh"
PERSONAL_REPO_RAW_URL="https://raw.githubusercontent.com/yikkrrtykj/singboxhysteria2-personal/main"
info() { printf '%s\n' "$*"; }
warning() { printf '%s\n' "$*"; }
hint() { printf '%s\n' "$*"; }
error() { printf '%s\n' "$*" >&2; return 1; }
sleep() { :; }
SERVICE_ACTIVE=yes RELOAD_MODE=ok SS_MODE=ok
systemctl() {
    case "$1" in
        is-active) [ "$SERVICE_ACTIVE" = yes ] ;;
        reload)
            printf '%s\n' "$*" >> "$TMP/service.calls"
            if [ "$RELOAD_MODE" = fail_new ] && jq -e 'any(.inbounds[]; .listen_port == 12001)' "$SB_SERVER_CONFIG" >/dev/null; then return 1; fi
            if [ "$RELOAD_MODE" = die_new ] && jq -e 'any(.inbounds[]; .listen_port == 12001)' "$SB_SERVER_CONFIG" >/dev/null; then SERVICE_ACTIVE=no; return 1; fi
            return 0 ;;
        restart) printf '%s\n' "$*" >> "$TMP/service.calls"; SERVICE_ACTIVE=yes ;;
        *) return 1 ;;
    esac
}
pgrep() { return 1; }
ss() {
    [ "$SS_MODE" = error ] && return 1
    [ "$SS_MODE" = collision ] && { printf 'LISTEN 0 128 0.0.0.0:12000 0.0.0.0:*\n'; return 0; }
    [ "$SS_MODE" = missing_new ] && jq -e 'any(.inbounds[]; .listen_port == 12001)' "$SB_SERVER_CONFIG" >/dev/null && return 0
    local kind port network
    while IFS=$'\t' read -r kind port network; do
        case "$kind" in vless) network=tcp ;; hysteria2) network=udp ;; esac
        [ "$1 $2" = '-H -lnt' ] && [ "$network" = udp ] && continue
        [ "$1 $2" = '-H -lnu' ] && [ "$network" = tcp ] && continue
        printf 'LISTEN 0 128 [::]:%s [::]:*\n' "$port"
    done < <(jq -r '.inbounds[] | [.type, .listen_port, (.network // "")] | @tsv' "$SB_SERVER_CONFIG")
    return 0
}
export MOCK_CHECK_FAIL="$TMP/check.fail"
cat > "$SB_SING_BOX_BIN" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = check ]; then
    [ -f "$MOCK_CHECK_FAIL" ] && exit 1
    jq -e 'all(.inbounds[]; .listen_port >= 1 and .listen_port <= 65535) and all(.inbounds[] | select(.type == "hysteria2"); .tls.certificate_path != "/bad/cert")' "$3" >/dev/null
elif [ "$1" = generate ]; then
    printf 'dGVzdC1zcy1zZWNyZXQhIQ==\n'
else
    exit 1
fi
MOCK
chmod +x "$SB_SING_BOX_BIN"
cat > "$TMP/original.json" <<'JSON'
{"inbounds":[{"type":"vless","tag":"vless-in","listen":"::","listen_port":11605,"users":[{"uuid":"original-uuid","flow":"xtls-rprx-vision"}],"tls":{"enabled":true,"server_name":"itunes.apple.com","reality":{"enabled":true,"private_key":"original-private-key","short_id":["original-short-id"],"handshake":{"server":"itunes.apple.com","server_port":443}}}},{"type":"hysteria2","tag":"hy2-in","listen":"::","listen_port":11606,"users":[{"password":"original-password"}],"tls":{"enabled":true,"certificate_path":"/original/cert","key_path":"/original/key"}}],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[{"action":"sniff"}]}}
JSON
cat > "$TMP/original.state" <<'STATE'
SERVER_IP='192.0.2.10'
PUBLIC_KEY='original-public-key'
HY_SERVER_NAME='bing.com'
HY_HOPPING=FALSE
STATE
reset_fixture() {
    cp "$TMP/original.json" "$SB_SERVER_CONFIG"
    cp "$TMP/original.state" "$SB_STATE_FILE"
    rm -f "$MOCK_CHECK_FAIL" "$TMP/service.calls"
    SERVICE_ACTIVE=yes RELOAD_MODE=ok SS_MODE=ok
}
identities() { jq -S '[.inbounds[] | select(.tag == "vless-in" or .tag == "hy2-in") | {tag,users,reality:.tls.reality.private_key,short_id:.tls.reality.short_id}]' "$1"; }
preserved() { diff -u <(identities "$TMP/original.json") <(identities "$SB_SERVER_CONFIG"); }
reset_fixture

expect 'port limits: 1 and 65535 accepted' bash -c 'source "$1"; validate_port 1 && validate_port 65535' _ "$TMP/library.sh"
for task_port in 0 65536 70000 abc -1 123456 '12 34'; do
    expect "invalid port refused: $task_port" test ! "$(validate_port "$task_port"; printf '%s' "$?")" = 0
done
SS_MODE=collision
task_port=$(modify_port 11605 Reality <<< $'abc\n70000\n12000\n01201' 2>"$TMP/port.err")
expect 'port retries keep stdout numeric and normalize leading zero' test "$task_port" = 1201
SS_MODE=error
expect 'socket query failure stops port generation' test ! "$(generate_port test <<< 12002 2>/dev/null; printf '%s' "$?")" = 0
SS_MODE=ok
expect 'port input EOF stops promptly' test ! "$(generate_port test </dev/null; printf '%s' "$?")" = 0
expect 'forwarding menu option 0 returns on first input' process_doko <<< 0

touch "$MOCK_CHECK_FAIL"
if apply_server_change 'invalid' '.inbounds[0].listen_port=12001' 'example.com' >"$TMP/result"; then fail 'failed check returns failure'; else pass 'failed check returns failure'; fi
expect 'failed check preserves config bytes' cmp -s "$TMP/original.json" "$SB_SERVER_CONFIG"
expect 'failed check preserves state bytes' cmp -s "$TMP/original.state" "$SB_STATE_FILE"
expect 'failed check never reloads' test ! -e "$TMP/service.calls"
reset_fixture
expect 'valid transaction succeeds for unnamed legacy users' apply_server_change 'port' '.inbounds[0].listen_port=12001' 'example.com'
expect 'transaction updates JSON' jq -e '.inbounds[0].listen_port == 12001' "$SB_SERVER_CONFIG"
expect 'paired state updated' grep -q "HY_SERVER_NAME='example.com'" "$SB_STATE_FILE"
expect 'node identities preserved' preserved
expect 'backup contains original JSON' bash -c 'cmp -s "$1" "$2"' _ "$TMP/original.json" "$(find "$TMP" -name 'server.json.bak.*' | head -n1)"

for task_failure in reload listener service_exit; do
    reset_fixture
    case "$task_failure" in reload) RELOAD_MODE=fail_new ;; listener) SS_MODE=missing_new ;; service_exit) RELOAD_MODE=die_new ;; esac
    if apply_server_change 'failure' '.inbounds[0].listen_port=12001' 'example.com' >"$TMP/result"; then fail "$task_failure returns failure"; else pass "$task_failure returns failure"; fi
    expect "$task_failure restores JSON bytes" cmp -s "$TMP/original.json" "$SB_SERVER_CONFIG"
    expect "$task_failure restores state bytes" cmp -s "$TMP/original.state" "$SB_STATE_FILE"
    expect "$task_failure recovers running service" test "$SERVICE_ACTIVE" = yes
done
reset_fixture
mv() {
    if [ "${*: -1}" = "$SB_STATE_FILE" ]; then return 1; fi
    command mv "$@"
}
if apply_server_change 'state move failure' '.inbounds[0].listen_port=12001' 'example.com' >"$TMP/result"; then fail 'state commit failure returns failure'; else pass 'state commit failure returns failure'; fi
unset -f mv
expect 'state move failure restores JSON' cmp -s "$TMP/original.json" "$SB_SERVER_CONFIG"
expect 'state move failure preserves state' cmp -s "$TMP/original.state" "$SB_STATE_FILE"
expect 'state move failure never reloads' test ! -e "$TMP/service.calls"

reset_fixture
# Abort bad cert input without overwriting either file; probe is isolated.
check_reality_target() { return 0; }
if modify_singbox <<< $'\n\n\nchanged.example\n/bad/cert\n\n' >"$TMP/result"; then fail 'bad cert rejected by menu'; else pass 'bad cert rejected by menu'; fi
expect 'bad certificate menu keeps old config' cmp -s "$TMP/original.json" "$SB_SERVER_CONFIG"
expect 'bad certificate menu keeps old domain' cmp -s "$TMP/original.state" "$SB_STATE_FILE"
expect 'bad certificate menu keeps identities' preserved

reset_fixture
expect 'landing menu corrects bad port and IP' process_dokoko <<< $'70000\n12002\n999.1.1.1\n192.0.2.20'
expect 'landing listener binds a local wildcard' jq -e 'any(.inbounds[]; .tag == "direct-in" and .listen == "::" and .listen_port == 12002)' "$SB_SERVER_CONFIG"
expect 'landing routes sniff then allow selected source then reject others' jq -e '.route.rules[0].action == "sniff" and .route.rules[0].source_ip_cidr == "192.0.2.20/32" and .route.rules[1].action == "route" and .route.rules[1].source_ip_cidr == "192.0.2.20/32" and .route.rules[2] == {inbound:"direct-in",action:"reject"} and .route.rules[3] == {action:"sniff"}' "$SB_SERVER_CONFIG"
expect 'landing menu preserves node identities' preserved
expect 'forwarding delete cannot remove Reality' test ! "$(delete_forward_rule vless-in >/dev/null; printf '%s' "$?")" = 0
expect 'landing delete removes its access rules' process_dokoko <<< y
expect 'landing delete preserves original global sniff' jq -e '.route.rules == [{action:"sniff"}] and all(.inbounds[]; .tag != "direct-in")' "$SB_SERVER_CONFIG"
expect 'forwarding menu validates target port and exits' process_doko <<< $'1\n12003\n192.0.2.30\n70000\n443\n0'
task_tag=$(jq -r '.inbounds[] | select(.type == "direct") | .tag' "$SB_SERVER_CONFIG")
# An inbound array may be shared with another node. Deletion must retain it.
jq --arg tag "$task_tag" '.route.rules += [{inbound:[$tag,"vless-in"],outbound:"direct"}]' "$SB_SERVER_CONFIG" > "$TMP/shared.json"
command mv "$TMP/shared.json" "$SB_SERVER_CONFIG"
expect 'delete forwarding with shared route' delete_forward_rule "$task_tag"
expect 'delete retains unrelated member in route array' jq -e '.route.rules[-1].inbound == ["vless-in"]' "$SB_SERVER_CONFIG"
expect 'SS menu adds validated port' process_ssko <<< $'abc\n12004'
expect 'SS config present and identities unchanged' jq -e 'any(.inbounds[]; .tag == "ss-in" and .listen_port == 12004)' "$SB_SERVER_CONFIG"
expect 'SS menu preserves node identities' preserved
expect 'SS menu deletes entry' process_ssko <<< y
expect 'SS entry removed' jq -e 'all(.inbounds[]; .tag != "ss-in")' "$SB_SERVER_CONFIG"

# Dependency failure: package commands are shell functions, never run for real.
(
    id() { echo 0; }
    command() { if [ "$1" = -v ]; then [ "$2" != qrencode ]; else builtin command "$@"; fi; }
    apt-get() { return 1; }
    install_pkgs
) >"$TMP/dependencies.result" 2>&1
expect 'package index failure is propagated' test "$?" != 0
expect 'package failure never announces success' test ! "$(grep -c '基础依赖检查通过' "$TMP/dependencies.result")" = 1
(
    id() { echo 0; }
    command() { if [ "$1" = -v ]; then [ "$2" != qrencode ]; else builtin command "$@"; fi; }
    apt-get() { [ "$1" = update ]; }
    install_pkgs
) >"$TMP/dependencies.result" 2>&1
expect 'package install failure is propagated' test "$?" != 0

expect 'shortcut installation succeeds in sandbox' install_shortcut
expect 'shortcut points to Personal repository' grep -q 'singboxhysteria2-personal/main/install.sh' "$SB_SHORTCUT_FILE"
expect 'shortcut uses selected sandbox link' test "$(readlink "$SB_SHORTCUT_LINK")" = "$SB_SHORTCUT_FILE"
mkdir "$TMP/mockbin"
cat > "$TMP/mockbin/curl" <<'MOCK'
#!/usr/bin/env bash
[ "${MOCK_DOWNLOAD_FAIL:-no}" = yes ] && exit 22
while [ $# -gt 0 ]; do
    if [ "$1" = -o ]; then output="$2"; shift 2; else shift; fi
done
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$MOCK_MANAGER_ARGS"\n' > "$output"
MOCK
chmod +x "$TMP/mockbin/curl"
export MOCK_MANAGER_ARGS="$TMP/args"
PATH="$TMP/mockbin:$PATH" bash "$SB_SHORTCUT_LINK" 'argument with space' test
expect 'shortcut forwards arguments intact' grep -qx 'argument with space' "$TMP/args"
rm -f "$TMP/args"
MOCK_DOWNLOAD_FAIL=yes PATH="$TMP/mockbin:$PATH" bash "$SB_SHORTCUT_LINK" >"$TMP/result" 2>&1
expect 'shortcut download failure returns error' test "$?" != 0
expect 'shortcut never executes empty download' test ! -e "$TMP/args"
expect 'generated gateway URL also uses Personal' grep -q '\${PERSONAL_REPO_RAW_URL}/install-linux-gateway.sh' "$SOURCE"
expect 'old upstream download URLs removed' test ! "$(grep -c 'raw.githubusercontent.com/yikkrrtykj/install-singboxhysteria2' "$SOURCE")" = 1
printf '\nMaintenance: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
