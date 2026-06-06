#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REAL_TMUX="$(command -v tmux)"
TMP_BIN="$(mktemp -d "${TMPDIR:-/tmp}/tmux-attention-bin.XXXXXX")"
SOCKET_PATH="$TMP_BIN/tmux.sock"

cleanup() {
	"$REAL_TMUX" -S "$SOCKET_PATH" kill-server >/dev/null 2>&1 || true
	rm -rf "$TMP_BIN"
}

trap cleanup EXIT INT TERM

pass() {
	printf 'ok - %s\n' "$1"
}

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

assert_eq() {
	expected="$1"
	actual="$2"
	label="$3"

	if [ "$actual" = "$expected" ]; then
		pass "$label"
	else
		printf 'expected: %s\nactual:   %s\n' "$expected" "$actual" >&2
		fail "$label"
	fi
}

assert_contains() {
	needle="$1"
	haystack="$2"
	label="$3"

	case "$haystack" in
		*"$needle"*)
			pass "$label"
			;;
		*)
			printf 'missing: %s\nfrom:    %s\n' "$needle" "$haystack" >&2
			fail "$label"
			;;
	esac
}

tmux_test() {
	"$REAL_TMUX" -S "$SOCKET_PATH" "$@"
}

cat >"$TMP_BIN/tmux" <<EOF
#!/bin/sh
exec "$REAL_TMUX" -S "$SOCKET_PATH" "\$@"
EOF
chmod +x "$TMP_BIN/tmux"

PATH="$TMP_BIN:$PATH"
export PATH

tmux_test -f /dev/null new-session -d -s tmux-attention-test

sh -n "$ROOT_DIR/scripts/tmux-attention"
pass "scripts/tmux-attention has valid sh syntax"

sh -n "$ROOT_DIR/scripts/clear-after-delay"
pass "scripts/clear-after-delay has valid sh syntax"

sh -n "$ROOT_DIR/scripts/install-hooks"
pass "scripts/install-hooks has valid sh syntax"

bash -n "$ROOT_DIR/tmux-attention.tmux"
pass "tmux-attention.tmux has valid bash syntax"

"$ROOT_DIR/tmux-attention.tmux"

assert_eq "8" "$(tmux_test show-option -gqv @tmux_attention_clear_delay)" "default clear delay is set"
assert_eq "on" "$(tmux_test show-option -gqv @tmux_attention_clear_on_view)" "default clear-on-view is set"
assert_eq "$ROOT_DIR/scripts/tmux-attention" "$(tmux_test show-option -gqv @tmux_attention_cli)" "default CLI path points at plugin script"

status="$(tmux_test show-option -gqv @tmux_attention_status)"
assert_contains "@agent_attention" "$status" "status format reads @agent_attention"
assert_contains "@tmux_attention_icon_blocked" "$status" "status format uses configurable icons"

assert_contains "after-select-window[90]" "$(tmux_test show-hook -g after-select-window)" "after-select-window hook is installed at stable index"
assert_contains "client-attached[90]" "$(tmux_test show-hook -g client-attached)" "client-attached hook is installed at stable index"

pane="$(tmux_test display-message -p '#{pane_id}')"

TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" blocked
assert_eq "blocked" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "CLI sets blocked state"

TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" review
assert_eq "review" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "CLI sets review state"

TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" clear
assert_eq "" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "CLI clears state"

tmux_test set-option -gq @tmux_attention_icon_input "CUSTOM"
tmux_test set-option -gq @tmux_attention_clear_delay "3"
"$ROOT_DIR/tmux-attention.tmux"

assert_eq "CUSTOM" "$(tmux_test show-option -gqv @tmux_attention_icon_input)" "plugin preserves configured icon override"
assert_eq "3" "$(tmux_test show-option -gqv @tmux_attention_clear_delay)" "plugin preserves configured delay override"

HOOK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-attention-hooks.XXXXXX")"
CLAUDE_SETTINGS="$HOOK_TMP/claude/settings.json"
CODEX_HOOKS="$HOOK_TMP/codex/hooks.json"

TMUX_ATTENTION_CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
TMUX_ATTENTION_CODEX_HOOKS="$CODEX_HOOKS" \
	"$ROOT_DIR/scripts/install-hooks" all >/dev/null

claude_status="$(
	TMUX_ATTENTION_CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
	TMUX_ATTENTION_CODEX_HOOKS="$CODEX_HOOKS" \
		"$ROOT_DIR/scripts/install-hooks" --status claude
)"
codex_status="$(
	TMUX_ATTENTION_CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
	TMUX_ATTENTION_CODEX_HOOKS="$CODEX_HOOKS" \
		"$ROOT_DIR/scripts/install-hooks" --status codex
)"

assert_contains "claude: installed" "$claude_status" "Claude hooks install into custom settings path"
assert_contains "codex: installed" "$codex_status" "Codex hooks install into custom hooks path"

TMUX_ATTENTION_CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
TMUX_ATTENTION_CODEX_HOOKS="$CODEX_HOOKS" \
	"$ROOT_DIR/scripts/install-hooks" all >/dev/null

hook_marker_count="$(
	python3 - "$CLAUDE_SETTINGS" "$CODEX_HOOKS" <<'PY'
import json
import sys

count = 0
for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    for groups in data.get("hooks", {}).values():
        for group in groups:
            for hook in group.get("hooks", []):
                if "tmux-attention:" in hook.get("command", ""):
                    count += 1
print(count)
PY
)"
assert_eq "5" "$hook_marker_count" "hook installer is idempotent"

TMUX_ATTENTION_CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
TMUX_ATTENTION_CODEX_HOOKS="$CODEX_HOOKS" \
	"$ROOT_DIR/scripts/install-hooks" --uninstall all >/dev/null

uninstalled_marker_count="$(
	python3 - "$CLAUDE_SETTINGS" "$CODEX_HOOKS" <<'PY'
import json
import sys

count = 0
for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    for groups in data.get("hooks", {}).values():
        for group in groups:
            for hook in group.get("hooks", []):
                if "tmux-attention:" in hook.get("command", ""):
                    count += 1
print(count)
PY
)"
assert_eq "0" "$uninstalled_marker_count" "hook uninstaller removes managed entries"
rm -rf "$HOOK_TMP"

printf 'all checks passed\n'
