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
tab_icon="$(tmux_test show-option -gqv @tmux_attention_tab_icon)"
assert_contains "@agent_attention" "$tab_icon" "tab icon prioritizes attention state"
assert_contains "@agent_context_active" "$tab_icon" "tab icon reads active agent state"
assert_contains "@tmux_attention_icon_working" "$tab_icon" "tab icon uses configurable working icon"
context_status="$(tmux_test show-option -gqv @tmux_attention_context)"
assert_contains "@agent_context_active" "$context_status" "context format reads active agent state"
assert_contains "pane_current_path" "$context_status" "context format falls back to pane current path"

assert_contains "after-select-window[90]" "$(tmux_test show-hook -g after-select-window)" "after-select-window hook is installed at stable index"
assert_contains "client-attached[90]" "$(tmux_test show-hook -g client-attached)" "client-attached hook is installed at stable index"
# switch-client (e.g. tmux-fzf-jump) fires neither of the above; these cover it.
assert_contains "client-session-changed[90]" "$(tmux_test show-hook -g client-session-changed)" "client-session-changed hook is installed at stable index"
assert_contains "pane-focus-in[90]" "$(tmux_test show-hook -g pane-focus-in)" "pane-focus-in hook is installed at stable index"
assert_contains "after-kill-pane[90]" "$(tmux_test show-hook -g after-kill-pane)" "after-kill-pane refresh hook is installed at stable index"

# clear-after-delay no-ops on a pane with no marker (so frequent focus hooks
# don't spawn a sleep). With a marker set, it schedules the clear.
nomark_pane="$(tmux_test display-message -p '#{pane_id}')"
tmux_test set-option -p -t "$nomark_pane" @agent_pane_attention ''
nomark_rc=0
"$ROOT_DIR/scripts/clear-after-delay" "$nomark_pane" >/dev/null 2>&1 || nomark_rc=$?
assert_eq "0" "$nomark_rc" "clear-after-delay exits cleanly when no marker is set"

pane="$(tmux_test display-message -p '#{pane_id}')"
target_pane="$(tmux_test new-window -d -P -F '#{pane_id}' -n target)"
other_pane="$(tmux_test split-window -d -t "$target_pane" -P -F '#{pane_id}')"

tmux_test set-option -gq @tmux_attention_clear_delay "1"
tmux_test set-option -p -t "$pane" @agent_pane_attention input
tmux_test set-option -p -t "$pane" @agent_pane_attention_updated_at "$(date +%s)"
"$ROOT_DIR/scripts/clear-after-delay" "$pane"
tmux_test set-option -p -t "$pane" @agent_pane_attention blocked
sleep 2
assert_eq "blocked" "$(tmux_test show-options -pqv -t "$pane" @agent_pane_attention)" "stale delayed clear does not erase a newer pane marker"
assert_not_contains "returned 1" "$(tmux_test show-messages)" "stale delayed clear does not emit a tmux command failure"
tmux_test set-option -gqu @tmux_attention_clear_delay

# With clear-on-view disabled, a set marker must persist: clear-after-delay
# (used by both the focus hooks and the CLI's post-set path) should no-op.
tmux_test set-option -gq @tmux_attention_clear_on_view "off"
tmux_test set-option -gq @tmux_attention_clear_delay "1"
tmux_test set-option -p -t "$pane" @agent_pane_attention review
"$ROOT_DIR/scripts/clear-after-delay" "$pane"
sleep 2
assert_eq "review" "$(tmux_test show-options -pqv -t "$pane" @agent_pane_attention)" "clear-on-view off keeps the pane marker in place"
tmux_test set-option -p -t "$pane" @agent_pane_attention ''
tmux_test set-option -gqu @tmux_attention_clear_delay
tmux_test set-option -gq @tmux_attention_clear_on_view "on"

TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" blocked
assert_eq "blocked" "$(tmux_test show-options -pqv -t "$pane" @agent_pane_attention)" "CLI sets pane-local blocked state"
assert_eq "blocked" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "CLI derives blocked window summary"

TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" review
assert_eq "review" "$(tmux_test show-options -pqv -t "$pane" @agent_pane_attention)" "CLI sets pane-local review state"

TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" clear
assert_eq "" "$(tmux_test show-options -pqv -t "$pane" @agent_pane_attention)" "CLI clears pane-local state"
assert_eq "" "$(tmux_test show-window-option -t "$pane" -v @agent_attention)" "CLI clears derived window summary"

TMUX_PANE= "$ROOT_DIR/scripts/tmux-attention" blocked --target "$target_pane"
assert_eq "blocked" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "CLI sets pane state on explicit target without TMUX_PANE"

"$ROOT_DIR/scripts/tmux-attention" --target "$target_pane" clear
assert_eq "" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "CLI clears explicit pane target before state argument"

"$ROOT_DIR/scripts/tmux-attention" input --target "$target_pane"
"$ROOT_DIR/scripts/tmux-attention" turn-start --target "$target_pane" --project FLYWL-2533
assert_eq "" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "turn-start clears its pane attention marker"
assert_eq "1" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_context_active)" "turn-start marks its pane context active"
assert_eq "1" "$(tmux_test show-window-option -t "$target_pane" -v @agent_context_active)" "turn-start derives active window summary"
assert_eq "FLYWL-2533" "$(tmux_test show-window-option -t "$target_pane" -v @agent_context_project)" "turn-start stores an explicit project"
assert_eq "FLYWL-2533" "$(tmux_test display-message -p -t "$target_pane" '#{E:@tmux_attention_context}')" "context format renders active project"

"$ROOT_DIR/scripts/tmux-attention" turn-start --target "$other_pane" --project ORC
assert_eq "1" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_context_active)" "first pane stays active when second agent starts"
assert_eq "1" "$(tmux_test show-options -pqv -t "$other_pane" @agent_pane_context_active)" "second pane tracks its own active agent"

"$ROOT_DIR/scripts/tmux-attention" review --target "$other_pane" --reason needs_review
"$ROOT_DIR/scripts/tmux-attention" input --target "$target_pane" --reason approval_required
assert_eq "review" "$(tmux_test show-options -pqv -t "$other_pane" @agent_pane_attention)" "second pane keeps its independent review state"
assert_eq "input" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "first pane keeps its independent input state"
assert_eq "input" "$(tmux_test show-window-option -t "$target_pane" -v @agent_attention)" "window summary chooses highest-priority pane state"
assert_eq "approval_required" "$(tmux_test show-window-option -t "$target_pane" -v @agent_attention_reason)" "window summary carries winning pane reason"

"$ROOT_DIR/scripts/tmux-attention" clear --target "$target_pane"
assert_eq "review" "$(tmux_test show-window-option -t "$target_pane" -v @agent_attention)" "clearing one pane reveals the next-highest window state"

"$ROOT_DIR/scripts/tmux-attention" turn-stop --target "$target_pane"
assert_eq "" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_context_active)" "turn-stop clears only its pane context"
assert_eq "1" "$(tmux_test show-window-option -t "$target_pane" -v @agent_context_active)" "window stays active while another pane agent works"

"$ROOT_DIR/scripts/tmux-attention" turn-stop --target "$other_pane"
assert_eq "" "$(tmux_test show-window-option -t "$target_pane" -v @agent_context_active)" "window summary clears after the final pane agent stops"
expected_path="$(tmux_test display-message -p -t "$target_pane" '#{b:pane_current_path}')"
assert_eq "$expected_path" "$(tmux_test display-message -p -t "$target_pane" '#{E:@tmux_attention_context}')" "context format falls back to pane directory"

"$ROOT_DIR/scripts/tmux-attention" clear --target "$other_pane"
"$ROOT_DIR/scripts/tmux-attention" turn-start --target "$target_pane" --project RESPONSE-READY
"$ROOT_DIR/scripts/tmux-attention" turn-done --target "$target_pane" --source codex --reason response_ready
assert_eq "" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_context_active)" "turn-done clears pane context"
assert_eq "" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_context_project)" "turn-done clears pane project"
assert_eq "done" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "turn-done sets pane-local done state"
assert_eq "codex" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention_source)" "turn-done records integration source"
assert_eq "response_ready" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention_reason)" "turn-done records response-ready reason"
assert_eq "done" "$(tmux_test show-window-option -t "$target_pane" -v @agent_attention)" "turn-done derives done window summary"
assert_eq "" "$(tmux_test show-window-option -t "$target_pane" -v @agent_context_active)" "turn-done clears derived window context"
assert_eq "$expected_path" "$(tmux_test display-message -p -t "$target_pane" '#{E:@tmux_attention_context}')" "turn-done restores pane-directory context"

"$ROOT_DIR/scripts/tmux-attention" turn-active --target "$target_pane" --project CONTINUED
assert_eq "" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "turn-active clears a premature response-ready marker"
assert_eq "1" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_context_active)" "turn-active restores pane context after continued activity"
assert_eq "CONTINUED" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_context_project)" "turn-active restores the continued project"

"$ROOT_DIR/scripts/tmux-attention" review --target "$target_pane" --reason needs_review
"$ROOT_DIR/scripts/tmux-attention" turn-active --target "$target_pane" --project IGNORED
assert_eq "review" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "turn-active leaves an already-active pane untouched"
assert_eq "CONTINUED" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_context_project)" "turn-active preserves the existing project"
"$ROOT_DIR/scripts/tmux-attention" clear --target "$target_pane"
"$ROOT_DIR/scripts/tmux-attention" turn-stop --target "$target_pane"

"$ROOT_DIR/scripts/tmux-attention" turn-start --target "$target_pane"
assert_eq "" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "next turn-start clears response-ready marker"
assert_eq "tmux-attention" "$(tmux_test show-window-option -t "$target_pane" -v @agent_context_project)" "turn-start derives the Git repository name"
"$ROOT_DIR/scripts/tmux-attention" turn-stop --target "$target_pane"

"$ROOT_DIR/scripts/tmux-attention" blocked --target "$target_pane" --source moshi --reason approval_required
assert_eq "blocked" "$("$ROOT_DIR/scripts/tmux-attention" get --target "$target_pane")" "CLI gets explicit target state"

target_json="$("$ROOT_DIR/scripts/tmux-attention" get --target "$target_pane" --format json)"
assert_contains '"scope":"pane"' "$target_json" "CLI JSON get reports pane scope"
assert_contains "\"target\":\"$target_pane\"" "$target_json" "CLI JSON get includes pane target"
assert_contains '"state":"blocked"' "$target_json" "CLI JSON get includes state"
assert_contains '"source":"moshi"' "$target_json" "CLI JSON get includes source metadata"
assert_contains '"reason":"approval_required"' "$target_json" "CLI JSON get includes reason metadata"
assert_contains '"updated_at":"' "$target_json" "CLI JSON get includes updated_at metadata"

list_text="$("$ROOT_DIR/scripts/tmux-attention" list --session tmux-attention-test)"
assert_contains " blocked" "$list_text" "CLI list includes marked windows"

list_json="$("$ROOT_DIR/scripts/tmux-attention" list --session tmux-attention-test --format json)"
assert_contains '"window_name":"target"' "$list_json" "CLI JSON list includes window name"
assert_contains "\"pane_id\":\"$target_pane\"" "$list_json" "CLI JSON list includes pane identity"
assert_contains '"source":"moshi"' "$list_json" "CLI JSON list includes metadata"

"$ROOT_DIR/scripts/tmux-attention" event approval_required --target "$target_pane" --source moshi
assert_eq "input" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "CLI event maps approval_required to pane-local input"
event_json="$("$ROOT_DIR/scripts/tmux-attention" get --target "$target_pane" --format json)"
assert_contains '"reason":"approval_required"' "$event_json" "CLI event stores default reason"

"$ROOT_DIR/scripts/tmux-attention" event session_started --target "$target_pane" --source moshi
assert_eq "" "$(tmux_test show-options -pqv -t "$target_pane" @agent_pane_attention)" "CLI event maps session_started to pane-local clear"
cleared_json="$("$ROOT_DIR/scripts/tmux-attention" get --target "$target_pane" --format json)"
assert_contains '"source":null' "$cleared_json" "CLI clear removes source metadata"
assert_contains '"reason":null' "$cleared_json" "CLI clear removes reason metadata"

missing_target_rc=0
"$ROOT_DIR/scripts/tmux-attention" --target >/dev/null 2>&1 || missing_target_rc=$?
assert_eq "2" "$missing_target_rc" "CLI rejects missing target argument"

assert_contains "window-status-format" "$("$ROOT_DIR/scripts/tmux-attention" status-format)" "CLI prints default status format"
assert_contains "@catppuccin_window_text" "$("$ROOT_DIR/scripts/tmux-attention" catppuccin-format)" "CLI prints Catppuccin status format"
assert_contains "@tmux_attention_context" "$("$ROOT_DIR/scripts/tmux-attention" context-format)" "CLI prints agent context format"

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

tmux_test set-window-option -t "$pane" @agent_attention ''
tmux_test set-window-option -t "$pane" @agent_context_active ''
assert_eq "" "$(tmux_test display-message -p -t "$pane" '#{E:@tmux_attention_tab_icon}')" "tab icon is empty without attention or active agent"
tmux_test set-window-option -t "$pane" @agent_context_active '1'
assert_eq "󰚩" "$(tmux_test display-message -p -t "$pane" '#{E:@tmux_attention_tab_icon}')" "tab icon renders working agent"
tmux_test set-window-option -t "$pane" @agent_attention blocked
assert_eq "" "$(tmux_test display-message -p -t "$pane" '#{E:@tmux_attention_tab_icon}')" "attention icon takes precedence over working agent"
tmux_test set-window-option -t "$pane" @agent_attention ''
tmux_test set-window-option -t "$pane" @agent_context_active ''

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
assert_contains "tmux-attention turn-start" "$absolute_print" "Claude hooks start agent context"
assert_not_contains "--agent" "$absolute_print" "Claude hooks do not send agent identity"
assert_contains "turn-done --source claude --reason response_ready" "$absolute_print" "Claude Stop hook marks a completed response"
assert_not_contains "turn-stop" "$absolute_print" "Claude Stop hook uses the atomic completed-turn transition"

absolute_codex_print="$(
	TMUX_ATTENTION_CLI="/opt/tmux-attention/tmux-attention" \
		"$ROOT_DIR/scripts/install-hooks" --print codex
)"
assert_contains '"PreToolUse"' "$absolute_codex_print" "Codex hooks observe resumed tool activity"
assert_contains '"matcher": ".*"' "$absolute_codex_print" "Codex activity hook matches every tool"
assert_contains "turn-active" "$absolute_codex_print" "Codex activity hook restores working context"
assert_contains "turn-done --source codex --reason response_ready" "$absolute_codex_print" "Codex Stop hook marks a completed response"

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
assert_eq "8" "$hook_marker_count" "hook installer is idempotent"

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

# --reason/--source metadata is stored as tab-separated fields elsewhere (see
# `list`), so a literal tab or newline in either would misalign columns.
clean_rc=0
TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" input --reason "agent needs approval" >/dev/null 2>&1 || clean_rc=$?
assert_eq "0" "$clean_rc" "CLI accepts a --reason with no control characters"

tabbed_reason="$(printf 'agent\tneeds approval')"
tab_reason_rc=0
TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" input --reason "$tabbed_reason" >/dev/null 2>&1 || tab_reason_rc=$?
assert_eq "2" "$tab_reason_rc" "CLI rejects a --reason containing a tab"

newlined_reason="$(printf 'agent\nneeds approval')"
nl_reason_rc=0
TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" input --reason "$newlined_reason" >/dev/null 2>&1 || nl_reason_rc=$?
assert_eq "2" "$nl_reason_rc" "CLI rejects a --reason containing a newline"

tabbed_source="$(printf 'a\tb')"
tab_source_rc=0
TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" input --source "$tabbed_source" >/dev/null 2>&1 || tab_source_rc=$?
assert_eq "2" "$tab_source_rc" "CLI rejects a --source containing a tab"

tabbed_project="$(printf 'FLYWL-2533\tbad')"
tab_project_rc=0
TMUX_PANE="$pane" "$ROOT_DIR/scripts/tmux-attention" turn-start --project "$tabbed_project" >/dev/null 2>&1 || tab_project_rc=$?
assert_eq "2" "$tab_project_rc" "turn-start rejects a project containing a tab"

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

# Pane ownership. The guard is a staleness check, not a security boundary: only
# a mismatch refuses, so ad-hoc panes and manual use keep working untouched.
owner_pane="$(tmux_test new-window -P -F '#{pane_id}')"

"$ROOT_DIR/scripts/tmux-attention" blocked --target "$owner_pane" --source claude
assert_eq "blocked" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_attention)" "unowned pane still accepts writes"
assert_eq "" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_attention_verified)" "a write with no owner is recorded unverified"

"$ROOT_DIR/scripts/tmux-attention" claim --owner agent-1 --target "$owner_pane"
assert_eq "agent-1" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_owner)" "claim stamps the pane owner"
assert_eq "" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_attention)" "claim clears the marker the pane inherited"

"$ROOT_DIR/scripts/tmux-attention" blocked --target "$owner_pane" --owner agent-1 --source claude
assert_eq "blocked" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_attention)" "matching owner may write"
assert_eq "1" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_attention_verified)" "a matching write is recorded verified"

mismatch_rc=0
mismatch_err="$("$ROOT_DIR/scripts/tmux-attention" "done" --target "$owner_pane" --owner agent-2 2>&1)" || mismatch_rc=$?
assert_eq "1" "$mismatch_rc" "a mismatched owner is refused"
assert_contains "does not match pane owner" "$mismatch_err" "the refusal explains itself"
assert_eq "blocked" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_attention)" "a refused write leaves the marker untouched"

TMUX_ATTENTION_OWNER=agent-1 "$ROOT_DIR/scripts/tmux-attention" review --target "$owner_pane"
assert_eq "review" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_attention)" "TMUX_ATTENTION_OWNER works like --owner"

"$ROOT_DIR/scripts/tmux-attention" clear --target "$owner_pane"
assert_eq "" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_attention)" "a caller with no owner may still clear an owned pane"

"$ROOT_DIR/scripts/tmux-attention" input --target "$owner_pane" --owner agent-1
"$ROOT_DIR/scripts/tmux-attention" disown --target "$owner_pane"
assert_eq "" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_owner)" "disown removes the stamp"
assert_eq "" "$(tmux_test show-options -pqv -t "$owner_pane" @agent_pane_attention_verified)" "verified cannot outlive the owner that granted it"

"$ROOT_DIR/scripts/tmux-attention" claim --owner agent-9 --target "$owner_pane"
"$ROOT_DIR/scripts/tmux-attention" input --target "$owner_pane" --owner agent-9
owner_json="$("$ROOT_DIR/scripts/tmux-attention" get --target "$owner_pane" --format json)"
assert_contains '"owner":"agent-9"' "$owner_json" "get json reports the pane owner"
assert_contains '"verified":true' "$owner_json" "get json reports verification"

claim_rc=0
"$ROOT_DIR/scripts/tmux-attention" claim --target "$owner_pane" >/dev/null 2>&1 || claim_rc=$?
assert_eq "2" "$claim_rc" "claim without an owner is a usage error"

# Shell integration. The emitted code is the only way ownership can be driven,
# since the owner id has to reach the agent's environment at launch.
init_fish="$("$ROOT_DIR/scripts/tmux-attention" shell-init fish claude)"
assert_contains "function tmux_attention_claim" "$init_fish" "fish init defines the claim helper"
assert_contains "function tmux_attention_disown" "$init_fish" "fish init defines the disown helper"
assert_contains "function claude --wraps=claude" "$init_fish" "fish init wraps a named command"

init_bash="$("$ROOT_DIR/scripts/tmux-attention" shell-init bash claude codex)"
assert_contains "tmux_attention_claim()" "$init_bash" "bash init defines the claim helper"
assert_contains "claude()" "$init_bash" "bash init wraps each named command"
assert_contains "codex()" "$init_bash" "bash init wraps every named command"

# Helpers without wrappers is the path for anyone who already wraps the command
# themselves; emitting a wrapper anyway would silently replace theirs.
init_bare="$("$ROOT_DIR/scripts/tmux-attention" shell-init bash)"
assert_contains "tmux_attention_claim()" "$init_bare" "helpers are emitted with no commands named"
assert_not_contains "claude()" "$init_bare" "no wrapper is emitted unless a command is named"

# The emitted code is generated text, so a quoting slip produces something that
# parses nowhere; check both dialects actually parse.
INIT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-attention-init.XXXXXX")"
if command -v bash >/dev/null 2>&1; then
	printf '%s\n' "$init_bash" >"$INIT_TMP/init.bash"
	init_rc=0
	bash -n "$INIT_TMP/init.bash" || init_rc=$?
	assert_eq "0" "$init_rc" "emitted bash is syntactically valid"
fi
if command -v fish >/dev/null 2>&1; then
	printf '%s\n' "$init_fish" >"$INIT_TMP/init.fish"
	init_rc=0
	fish -n "$INIT_TMP/init.fish" || init_rc=$?
	assert_eq "0" "$init_rc" "emitted fish is syntactically valid"
fi
rm -rf "$INIT_TMP"

# Symlinking the CLI onto PATH is a normal install, and dirname "$0" then points
# at the link rather than the plugin -- which silently made `version` report
# unknown and shell-init emit the symlink's path.
LINK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-attention-link.XXXXXX")"
ln -s "$ROOT_DIR/scripts/tmux-attention" "$LINK_TMP/tmux-attention"
ln -s "$LINK_TMP/tmux-attention" "$LINK_TMP/second-hop"
assert_eq "$("$ROOT_DIR/scripts/tmux-attention" version)" "$("$LINK_TMP/tmux-attention" version)" \
	"version resolves through a symlink"
assert_eq "$("$ROOT_DIR/scripts/tmux-attention" version)" "$("$LINK_TMP/second-hop" version)" \
	"version resolves through a chain of symlinks"
assert_contains "$ROOT_DIR/scripts/tmux-attention" "$("$LINK_TMP/tmux-attention" shell-init fish)" \
	"shell-init emits the real script path, not the symlink"
rm -rf "$LINK_TMP"

shell_rc=0
"$ROOT_DIR/scripts/tmux-attention" shell-init tcsh >/dev/null 2>&1 || shell_rc=$?
assert_eq "2" "$shell_rc" "an unsupported shell is a usage error"

shell_rc=0
"$ROOT_DIR/scripts/tmux-attention" shell-init >/dev/null 2>&1 || shell_rc=$?
assert_eq "2" "$shell_rc" "shell-init requires a shell name"

printf 'all checks passed\n'
