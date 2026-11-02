#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
source "$ROOT/install.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[[ "$SB_SHORTCUT_LINK" == /usr/bin/xun ]] || fail 'wrong Personal command'
[[ "$SB_SHORTCUT_FILE" == /root/sbox/xun.sh ]] || fail 'shared manager path'
SB_SHORTCUT_FILE="$TMP/xun.sh" SB_SHORTCUT_LINK="$TMP/xun"
SB_LEGACY_SHORTCUT_FILE="$TMP/mianyang.sh" SB_LEGACY_SHORTCUT_LINK="$TMP/mianyang"

# Fresh install and an original/custom legacy command must coexist.
printf 'original manager\n' > "$SB_LEGACY_SHORTCUT_FILE"
ln -s "$SB_LEGACY_SHORTCUT_FILE" "$SB_LEGACY_SHORTCUT_LINK"
install_shortcut
bash -n "$SB_SHORTCUT_FILE"
[[ "$(cat "$SB_LEGACY_SHORTCUT_FILE")" == 'original manager' ]] || fail 'original overwritten'
[[ -L "$SB_LEGACY_SHORTCUT_LINK" ]] || fail 'original link removed'
[[ "$(readlink "$SB_SHORTCUT_LINK")" == "$SB_SHORTCUT_FILE" ]] || fail 'new link missing'

# Use the actual generated Personal downloader as a legacy deployment fixture.
cp "$SB_SHORTCUT_FILE" "$SB_LEGACY_SHORTCUT_FILE"
install_shortcut
[[ ! -e "$SB_LEGACY_SHORTCUT_FILE" && ! -L "$SB_LEGACY_SHORTCUT_LINK" ]] || fail 'legacy Personal entry remains'
install_shortcut
[[ -x "$SB_SHORTCUT_FILE" ]] || fail 'repeated repair broke manager'

# An unrelated link must survive even if a Personal wrapper is present.
cp "$SB_SHORTCUT_FILE" "$SB_LEGACY_SHORTCUT_FILE"
printf 'custom\n' > "$TMP/custom"
ln -s "$TMP/custom" "$SB_LEGACY_SHORTCUT_LINK"
install_shortcut
[[ "$(readlink "$SB_LEGACY_SHORTCUT_LINK")" == "$TMP/custom" ]] || fail 'custom link removed'
[[ -f "$SB_LEGACY_SHORTCUT_FILE" ]] || fail 'ambiguous wrapper removed'
rm -- "$SB_LEGACY_SHORTCUT_LINK"
install_shortcut
[[ ! -e "$SB_LEGACY_SHORTCUT_FILE" ]] || fail 'orphan Personal wrapper remains'

# Run the real new entry without network; verify source and argument forwarding.
mkdir "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
[[ "${*: -1}" == https://raw.githubusercontent.com/yikkrrtykj/singboxhysteria2-personal/main/install.sh ]]
while [[ "$1" != -o ]]; do shift; done
printf 'printf "<%%s>\\n" "$@"\n' > "$2"
EOF
chmod +x "$TMP/bin/curl"
result=$(PATH="$TMP/bin:$PATH" bash "$SB_SHORTCUT_LINK" 'two words' --check)
[[ "$result" == $'<two words>\n<--check>' ]] || fail 'wrong download source or lost arguments'
printf 'PASS: Personal command, legacy migration, original/custom preservation and dispatch\n'
