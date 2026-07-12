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

assert_not_contains() {
	needle="$1"
	haystack="$2"
	label="$3"

	case "$haystack" in
		*"$needle"*)
			printf 'unexpected: %s\nin:         %s\n' "$needle" "$haystack" >&2
			fail "$label"
			;;
		*)
			pass "$label"
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

sh -n "$ROOT_DIR/scripts/setup"
pass "scripts/setup has valid sh syntax"

bash -n "$ROOT_DIR/tmux-attention.tmux"
pass "tmux-attention.tmux has valid bash syntax"

"$ROOT_DIR/tmux-attention.tmux"

assert_eq "8" "$(tmux_test show-option -gqv @tmux_attention_clear_delay)" "default clear delay is set"
assert_eq "on" "$(tmux_test show-option -gqv @tmux_attention_clear_on_view)" "default clear-on-view is set"

status="$(tmux_test show-option -gqv @tmux_attention_status)"
assert_contains "@agent_attention" "$status" "status format reads @agent_attention"
assert_contains "@tmux_attention_icon_blocked" "$status" "status format uses configurable icons"

assert_contains "after-select-window[90]" "$(tmux_test show-hook -g after-select-window)" "after-select-window hook is installed at stable index"
assert_contains "client-attached[90]" "$(tmux_test show-hook -g client-attached)" "client-attached hook is installed at stable index"
# switch-client (e.g. tmux-fzf-jump) fires neither of the above; these cover it.
assert_contains "client-session-changed[90]" "$(tmux_test show-hook -g client-session-changed)" "client-session-changed hook is installed at stable index"
assert_contains "pane-focus-in[90]" "$(tmux_test show-hook -g pane-focus-in)" "pane-focus-in hook is installed at stable index"

# clear-after-delay no-ops on a window with no marker (so frequent focus hooks
# don't spawn a sleep). With a marker set, it schedules the clear.
nomark_win="$(tmux_test display-message -p '#{window_id}')"
tmux_test set-window-option -t "$nomark_win" @agent_attention ''
nomark_rc=0
"$ROOT_DIR/scripts/clear-after-delay" "$nomark_win" >/dev/null 2>&1 || nomark_rc=$?
assert_eq "0" "$nomark_rc" "clear-after-delay exits cleanly when no marker is set"

pane="$(tmux_test display-message -p '#{pane_id}')"
target_pane="$(tmux_test new-window -d -P -F '#{pane_id}' -n target)"

tmux_test set-option -gq @tmux_attention_clear_delay "1"
tmux_test set-window-option -t "$pane" @agent_attention input
"$ROOT_DIR/scripts/clear-after-delay" "$pane"
tmux_test set-window-option -t "$pane" @agent_attention blocked
sleep 2
assert_eq "blocked" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "stale delayed clear does not erase a newer marker"
assert_not_contains "returned 1" "$(tmux_test show-messages)" "stale delayed clear does not emit a tmux command failure"
tmux_test set-option -gqu @tmux_attention_clear_delay

# With clear-on-view disabled, a set marker must persist: clear-after-delay
# (used by both the focus hooks and the CLI's post-set path) should no-op.
tmux_test set-option -gq @tmux_attention_clear_on_view "off"
tmux_test set-option -gq @tmux_attention_clear_delay "1"
tmux_test set-window-option -t "$pane" @agent_attention review
"$ROOT_DIR/scripts/clear-after-delay" "$pane"
sleep 2
assert_eq "review" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "clear-on-view off keeps the marker in place"
tmux_test set-window-option -t "$pane" @agent_attention ''
tmux_test set-option -gqu @tmux_attention_clear_delay
tmux_test set-option -gq @tmux_attention_clear_on_view "on"

TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" blocked
assert_eq "blocked" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "CLI sets blocked state"

TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" review
assert_eq "review" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "CLI sets review state"

TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" clear
assert_eq "" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "CLI clears state"

TMUX_PANE= "$ROOT_DIR/scripts/tmux-attention" blocked --target "$target_pane"
assert_eq "blocked" "$(tmux_test show-window-option -t "$target_pane" -v @agent_attention)" "CLI sets state on explicit target without TMUX_PANE"

"$ROOT_DIR/scripts/tmux-attention" --target "$target_pane" clear
assert_eq "" "$(tmux_test show-window-option -t "$target_pane" -v @agent_attention)" "CLI clears explicit target before state argument"

"$ROOT_DIR/scripts/tmux-attention" blocked --target "$target_pane" --source moshi --reason approval_required
assert_eq "blocked" "$("$ROOT_DIR/scripts/tmux-attention" get --target "$target_pane")" "CLI gets explicit target state"

target_json="$("$ROOT_DIR/scripts/tmux-attention" get --target "$target_pane" --format json)"
assert_contains '"state":"blocked"' "$target_json" "CLI JSON get includes state"
assert_contains '"source":"moshi"' "$target_json" "CLI JSON get includes source metadata"
assert_contains '"reason":"approval_required"' "$target_json" "CLI JSON get includes reason metadata"
assert_contains '"updated_at":"' "$target_json" "CLI JSON get includes updated_at metadata"

list_text="$("$ROOT_DIR/scripts/tmux-attention" list --session tmux-attention-test)"
assert_contains " blocked" "$list_text" "CLI list includes marked windows"

list_json="$("$ROOT_DIR/scripts/tmux-attention" list --session tmux-attention-test --format json)"
assert_contains '"window_name":"target"' "$list_json" "CLI JSON list includes window name"
assert_contains '"source":"moshi"' "$list_json" "CLI JSON list includes metadata"

"$ROOT_DIR/scripts/tmux-attention" event approval_required --target "$target_pane" --source moshi
assert_eq "input" "$(tmux_test show-window-option -t "$target_pane" -v @agent_attention)" "CLI event maps approval_required to input"
event_json="$("$ROOT_DIR/scripts/tmux-attention" get --target "$target_pane" --format json)"
assert_contains '"reason":"approval_required"' "$event_json" "CLI event stores default reason"

"$ROOT_DIR/scripts/tmux-attention" event session_started --target "$target_pane" --source moshi
assert_eq "" "$(tmux_test show-window-option -t "$target_pane" -v @agent_attention)" "CLI event maps session_started to clear"
cleared_json="$("$ROOT_DIR/scripts/tmux-attention" get --target "$target_pane" --format json)"
assert_contains '"source":null' "$cleared_json" "CLI clear removes source metadata"
assert_contains '"reason":null' "$cleared_json" "CLI clear removes reason metadata"

missing_target_rc=0
"$ROOT_DIR/scripts/tmux-attention" --target >/dev/null 2>&1 || missing_target_rc=$?
assert_eq "2" "$missing_target_rc" "CLI rejects missing target argument"

assert_contains "window-status-format" "$("$ROOT_DIR/scripts/tmux-attention" status-format)" "CLI prints default status format"
assert_contains "@catppuccin_window_text" "$("$ROOT_DIR/scripts/tmux-attention" catppuccin-format)" "CLI prints Catppuccin status format"

tmux_test set-option -gq window-status-format "#{E:@tmux_attention_status}#I:#W"
doctor_output="$(
	TMUX_PANE="$pane" \
	TMUX_ATTENTION_CLAUDE_SETTINGS="$TMP_BIN/doctor-claude.json" \
	TMUX_ATTENTION_CODEX_HOOKS="$TMP_BIN/doctor-codex.json" \
		"$ROOT_DIR/scripts/tmux-attention" doctor
)"
assert_contains "ok - tmux command is available" "$doctor_output" "doctor checks tmux availability"
assert_contains "ok - plugin status option is loaded" "$doctor_output" "doctor checks plugin status option"
assert_contains "ok - tmux status line includes tmux-attention" "$doctor_output" "doctor checks status-line wiring"
assert_contains "python3" "$doctor_output" "doctor reports python3 availability"
assert_contains "codex: not installed" "$doctor_output" "doctor reports hook status"

doctor_probe_output="$(
	TMUX_PANE="$pane" \
	TMUX_ATTENTION_CLAUDE_SETTINGS="$TMP_BIN/doctor-probe-claude.json" \
	TMUX_ATTENTION_CODEX_HOOKS="$TMP_BIN/doctor-probe-codex.json" \
		"$ROOT_DIR/scripts/tmux-attention" doctor --probe
)"
assert_contains "marker probe rendered a marker" "$doctor_probe_output" "doctor probe still accepts --probe"

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

relocated_status="$(
	TMUX_ATTENTION_CLI="/some/other/location/tmux-attention" \
	TMUX_ATTENTION_CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
	TMUX_ATTENTION_CODEX_HOOKS="$CODEX_HOOKS" \
		"$ROOT_DIR/scripts/install-hooks" --status claude
)"
assert_contains "claude: installed" "$relocated_status" "hook status ignores the CLI path"

# A CLI under $HOME is emitted as a portable "$HOME"-relative command so the
# generated hook config does not embed a machine-specific absolute path.
portable_print="$(
	TMUX_ATTENTION_CLI="$HOME/.config/tmux/plugins/tmux-attention/scripts/tmux-attention" \
		"$ROOT_DIR/scripts/install-hooks" --print claude
)"
# The literal characters $HOME must survive into the command (expanded by the
# hook runner's shell, not at install time); single quotes are intentional.
# shellcheck disable=SC2016
assert_contains '$HOME' "$portable_print" "managed command references \$HOME"
assert_contains "/.config/tmux/plugins/tmux-attention/scripts/tmux-attention" \
	"$portable_print" "managed command keeps the relative CLI path"
case "$portable_print" in
	*"$HOME/.config/tmux/plugins/tmux-attention"*)
		fail "managed command embedded the literal home path"
		;;
	*)
		pass "managed command does not embed the literal home path"
		;;
esac

# A CLI outside $HOME keeps its absolute path (no false $HOME rewrite).
absolute_print="$(
	TMUX_ATTENTION_CLI="/opt/tmux-attention/tmux-attention" \
		"$ROOT_DIR/scripts/install-hooks" --print claude
)"
assert_contains "/opt/tmux-attention/tmux-attention" \
	"$absolute_print" "managed command keeps an absolute CLI path outside \$HOME"

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

# install-hooks argument parsing: flags may follow the target, extras are
# rejected, and uninstall never creates or rewrites files with nothing to remove.
ARGS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-attention-args.XXXXXX")"
ARGS_CLAUDE="$ARGS_TMP/claude/settings.json"
ARGS_CODEX="$ARGS_TMP/codex/hooks.json"

TMUX_ATTENTION_CLAUDE_SETTINGS="$ARGS_CLAUDE" \
TMUX_ATTENTION_CODEX_HOOKS="$ARGS_CODEX" \
	"$ROOT_DIR/scripts/install-hooks" claude >/dev/null
TMUX_ATTENTION_CLAUDE_SETTINGS="$ARGS_CLAUDE" \
TMUX_ATTENTION_CODEX_HOOKS="$ARGS_CODEX" \
	"$ROOT_DIR/scripts/install-hooks" claude --uninstall >/dev/null
assert_contains "claude: not installed" "$(
	TMUX_ATTENTION_CLAUDE_SETTINGS="$ARGS_CLAUDE" \
	TMUX_ATTENTION_CODEX_HOOKS="$ARGS_CODEX" \
		"$ROOT_DIR/scripts/install-hooks" --status claude
)" "install-hooks accepts --uninstall after the target"

extra_args_rc=0
TMUX_ATTENTION_CLAUDE_SETTINGS="$ARGS_CLAUDE" \
TMUX_ATTENTION_CODEX_HOOKS="$ARGS_CODEX" \
	"$ROOT_DIR/scripts/install-hooks" claude codex >/dev/null 2>&1 || extra_args_rc=$?
assert_eq "2" "$extra_args_rc" "install-hooks rejects extra target arguments"

unknown_arg_rc=0
TMUX_ATTENTION_CLAUDE_SETTINGS="$ARGS_CLAUDE" \
TMUX_ATTENTION_CODEX_HOOKS="$ARGS_CODEX" \
	"$ROOT_DIR/scripts/install-hooks" --uninstall claude bogus >/dev/null 2>&1 || unknown_arg_rc=$?
assert_eq "2" "$unknown_arg_rc" "install-hooks rejects unknown arguments"

TMUX_ATTENTION_CLAUDE_SETTINGS="$ARGS_TMP/never/claude.json" \
TMUX_ATTENTION_CODEX_HOOKS="$ARGS_TMP/never/codex.json" \
	"$ROOT_DIR/scripts/install-hooks" --uninstall all >/dev/null
if [ ! -e "$ARGS_TMP/never/claude.json" ] && [ ! -e "$ARGS_TMP/never/codex.json" ]; then
	pass "uninstall does not create missing config files"
else
	fail "uninstall does not create missing config files"
fi

printf '{"hooks": {"Stop": []}}\n' >"$ARGS_TMP/unmanaged.json"
before_unmanaged="$(cat "$ARGS_TMP/unmanaged.json")"
TMUX_ATTENTION_CLAUDE_SETTINGS="$ARGS_TMP/unmanaged.json" \
TMUX_ATTENTION_CODEX_HOOKS="$ARGS_TMP/never/codex.json" \
	"$ROOT_DIR/scripts/install-hooks" --uninstall claude >/dev/null
assert_eq "$before_unmanaged" "$(cat "$ARGS_TMP/unmanaged.json")" "uninstall leaves configs without managed entries untouched"
unmanaged_backup_count=0
for f in "$ARGS_TMP/unmanaged.json".bak.*; do
	[ -e "$f" ] || continue
	unmanaged_backup_count=$((unmanaged_backup_count + 1))
done
assert_eq "0" "$unmanaged_backup_count" "uninstall does not back up configs without managed entries"

rm -rf "$ARGS_TMP"

SETUP_TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-attention-setup.XXXXXX")"
SETUP_TMUX_CONF="$SETUP_TMP/.tmux.conf"
SETUP_CLAUDE_SETTINGS="$SETUP_TMP/claude/settings.json"
SETUP_CODEX_HOOKS="$SETUP_TMP/codex/hooks.json"

TMUX_ATTENTION_TMUX_CONF="$SETUP_TMUX_CONF" \
TMUX_ATTENTION_CLAUDE_SETTINGS="$SETUP_CLAUDE_SETTINGS" \
TMUX_ATTENTION_CODEX_HOOKS="$SETUP_CODEX_HOOKS" \
	"$ROOT_DIR/scripts/setup" >/dev/null

assert_contains "window-status-format" "$(cat "$SETUP_TMUX_CONF")" "setup writes default tmux status snippet"
assert_contains "codex: installed" "$(
	TMUX_ATTENTION_CLAUDE_SETTINGS="$SETUP_CLAUDE_SETTINGS" \
	TMUX_ATTENTION_CODEX_HOOKS="$SETUP_CODEX_HOOKS" \
		"$ROOT_DIR/scripts/install-hooks" --status codex
)" "setup defaults to Codex hooks"

custom_setup_output="$(
	TMUX_ATTENTION_TMUX_CONF="$SETUP_TMUX_CONF" \
	TMUX_ATTENTION_CLAUDE_SETTINGS="$SETUP_CLAUDE_SETTINGS" \
	TMUX_ATTENTION_CODEX_HOOKS="$SETUP_CODEX_HOOKS" \
		"$ROOT_DIR/scripts/setup" codex
)"
assert_contains "tmux source-file $SETUP_TMUX_CONF" "$custom_setup_output" "setup prints custom tmux reload path"

TMUX_ATTENTION_TMUX_CONF="$SETUP_TMUX_CONF" \
TMUX_ATTENTION_CLAUDE_SETTINGS="$SETUP_CLAUDE_SETTINGS" \
TMUX_ATTENTION_CODEX_HOOKS="$SETUP_CODEX_HOOKS" \
	"$ROOT_DIR/scripts/setup" codex --status-line catppuccin >/dev/null

setup_block_count="$(
	python3 - "$SETUP_TMUX_CONF" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
print(text.count("# tmux-attention: begin"))
PY
)"
assert_eq "1" "$setup_block_count" "setup updates one managed tmux config block"
assert_contains "@catppuccin_window_text" "$(cat "$SETUP_TMUX_CONF")" "setup can switch to Catppuccin status snippet"

TMUX_ATTENTION_TMUX_CONF="$SETUP_TMUX_CONF" \
TMUX_ATTENTION_CLAUDE_SETTINGS="$SETUP_CLAUDE_SETTINGS" \
TMUX_ATTENTION_CODEX_HOOKS="$SETUP_CODEX_HOOKS" \
	"$ROOT_DIR/scripts/setup" codex --uninstall >/dev/null

assert_contains "codex: not installed" "$(
	TMUX_ATTENTION_CLAUDE_SETTINGS="$SETUP_CLAUDE_SETTINGS" \
	TMUX_ATTENTION_CODEX_HOOKS="$SETUP_CODEX_HOOKS" \
		"$ROOT_DIR/scripts/install-hooks" --status codex
)" "setup uninstall removes selected hooks"

uninstall_block_count="$(
	python3 - "$SETUP_TMUX_CONF" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
print(text.count("# tmux-attention: begin"))
PY
)"
assert_eq "0" "$uninstall_block_count" "setup uninstall removes managed tmux config block"

TMUX_ATTENTION_TMUX_CONF="$SETUP_TMUX_CONF" \
TMUX_ATTENTION_CLAUDE_SETTINGS="$SETUP_CLAUDE_SETTINGS" \
TMUX_ATTENTION_CODEX_HOOKS="$SETUP_CODEX_HOOKS" \
	"$ROOT_DIR/scripts/setup" codex --reload >/dev/null

assert_contains "@tmux_attention_status" "$(tmux_test show-option -gqv window-status-format)" "setup reload sources custom tmux config"

TMUX_ATTENTION_TMUX_CONF="$SETUP_TMP/no-status.conf" \
TMUX_ATTENTION_CLAUDE_SETTINGS="$SETUP_TMP/no-status-claude.json" \
TMUX_ATTENTION_CODEX_HOOKS="$SETUP_TMP/no-status-codex.json" \
	"$ROOT_DIR/scripts/setup" codex --status-line none >/dev/null

if [ ! -e "$SETUP_TMP/no-status.conf" ]; then
	pass "setup can skip tmux status config"
else
	fail "setup can skip tmux status config"
fi

rm -rf "$SETUP_TMP"

# CLI subcommands and exit codes.
assert_contains "tmux-attention" "$("$ROOT_DIR/scripts/tmux-attention" version)" "CLI version prints a version string"
assert_contains "Usage:" "$("$ROOT_DIR/scripts/tmux-attention" --help)" "CLI help prints usage"

if TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" bogus-state >/dev/null 2>&1; then
	unknown_rc=0
else
	unknown_rc=$?
fi
assert_eq "2" "$unknown_rc" "CLI exits 2 on unknown state"

bell_char="$(printf '\a')"
bell_output="$(env -u TMUX_PANE "$ROOT_DIR/scripts/tmux-attention" input 2>/dev/null || true)"
assert_eq "$bell_char" "$bell_output" "CLI rings the bell when run outside tmux"

# Backup pruning keeps only the five newest backups.
PRUNE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-attention-prune.XXXXXX")"

PRUNE_SETTINGS="$PRUNE_TMP/settings.json"
printf '{}\n' >"$PRUNE_SETTINGS"
seed=1
while [ "$seed" -le 8 ]; do
	printf '{}\n' >"$PRUNE_SETTINGS.bak.2000010100000$seed"
	seed=$((seed + 1))
done
TMUX_ATTENTION_CLAUDE_SETTINGS="$PRUNE_SETTINGS" \
TMUX_ATTENTION_CODEX_HOOKS="$PRUNE_TMP/codex.json" \
	"$ROOT_DIR/scripts/install-hooks" claude >/dev/null
install_backup_count=0
for f in "$PRUNE_SETTINGS".bak.*; do
	[ -e "$f" ] || continue
	install_backup_count=$((install_backup_count + 1))
done
assert_eq "5" "$install_backup_count" "install-hooks prunes old backups to five"

PRUNE_CONF="$PRUNE_TMP/prune.tmux.conf"
printf '# existing\n' >"$PRUNE_CONF"
seed=1
while [ "$seed" -le 8 ]; do
	printf '# old\n' >"$PRUNE_CONF.bak.2000010100000$seed"
	seed=$((seed + 1))
done
TMUX_ATTENTION_TMUX_CONF="$PRUNE_CONF" \
TMUX_ATTENTION_CLAUDE_SETTINGS="$PRUNE_TMP/prune-claude.json" \
TMUX_ATTENTION_CODEX_HOOKS="$PRUNE_TMP/prune-codex.json" \
	"$ROOT_DIR/scripts/setup" codex >/dev/null
setup_backup_count=0
for f in "$PRUNE_CONF".bak.*; do
	[ -e "$f" ] || continue
	setup_backup_count=$((setup_backup_count + 1))
done
assert_eq "5" "$setup_backup_count" "setup prunes old tmux config backups to five"

rm -rf "$PRUNE_TMP"

printf 'all checks passed\n'
