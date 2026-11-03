#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Queue load-time tmux commands so everything below is applied by a single
# tmux invocation (";"-separated commands) instead of one process per
# option/hook.
load_batch=()

queue_tmux() {
	if [ "${#load_batch[@]}" -gt 0 ]; then
		load_batch+=(";")
	fi
	load_batch+=("$@")
}

set_default_option() {
	local option="$1"
	local value="$2"

	queue_tmux set-option -goq "$option" "$value"
}

set_default_option "@tmux_attention_icon_input" "󱐋"
set_default_option "@tmux_attention_icon_blocked" ""
set_default_option "@tmux_attention_icon_review" "󰛨"
set_default_option "@tmux_attention_icon_done" ""
set_default_option "@tmux_attention_icon_working" "󰚩"
set_default_option "@tmux_attention_clear_delay" "8"
set_default_option "@tmux_attention_clear_on_view" "on"

# Optional tmux 3.8 features. Both are off by default so upgrading the plugin
# never changes how an existing setup behaves.
#
# Working animation: replace the static working icon with a spinner built on
# the #{A/<ticks>:<frames>} modifier. tmux redraws the status line every 100ms
# only while an animated branch is actually rendered, so idle windows cost
# nothing; it is still a redraw per tick per client, which matters on slow
# links such as a phone over mosh.
set_default_option "@tmux_attention_working_animation" "off"
# Style picks the frames: "spinner" uses @tmux_attention_working_frames and
# @tmux_attention_working_frame_ticks, "robot" is a built-in Nerd Font robot
# that idles, smiles, glances sideways and gets excited on a ~8s loop.
set_default_option "@tmux_attention_working_style" "spinner"
set_default_option "@tmux_attention_working_frames" "⠋,⠙,⠹,⠸,⠼,⠴,⠦,⠧,⠇,⠏"
set_default_option "@tmux_attention_working_frame_ticks" "1"

# robot_frames prints the built-in robot animation: one frame per 200ms tick,
# repeated to set how long each face is held. Faces are nf-md-robot (rest),
# robot_happy, robot_confused (glance) and
# robot_excited, all in Nerd Fonts 3.
robot_frames() {
	local rest='󰚩' happy='󱜙' glance='󱚟' excited='󱚣'
	local -a frames=()
	add_frames() {
		local face="$1" count="$2" i
		for ((i = 0; i < count; i++)); do
			frames+=("$face")
		done
	}
	add_frames "$rest" 10
	add_frames "$happy" 5
	add_frames "$rest" 10
	add_frames "$glance" 4
	add_frames "$rest" 3
	add_frames "$excited" 3
	add_frames "$rest" 4
	local IFS=,
	printf '%s' "${frames[*]}"
}
# Shell done: when an OSC 133 shell command (fish 4+, or any prompt that emits
# OSC 133) runs at least this many seconds in a pane no agent owns, mark the
# pane done on success or blocked on a non-zero exit.
set_default_option "@tmux_attention_shell_done" "off"
set_default_option "@tmux_attention_shell_done_min_seconds" "30"
# PR status: show the current branch's pull request (number, checks, review)
# next to the context. Looked up with `gh` in the background and cached for
# @tmux_attention_pr_ttl seconds, so the status bar never waits on the network.
set_default_option "@tmux_attention_pr_status" "off"
set_default_option "@tmux_attention_pr_ttl" "180"
# Command summary (tmux 3.8): show "⏵ make t 3m" while a shell command runs in
# the current pane, and "✗ make t" after it fails, until the next command.
set_default_option "@tmux_attention_command_summary" "off"
set_default_option "@tmux_attention_command_max" "24"
# Refresh the context on every shell prompt (tmux 3.8 OSC 133), so `cd` and
# `git checkout` update the label right away instead of on the next focus
# change. Costs a couple of git calls per prompt, in the background.
set_default_option "@tmux_attention_refresh_on_prompt" "on"

# tmux_supports_38 reports whether the running server is tmux 3.8 or newer.
# Versions look like "3.8", "3.7c" or "next-3.9"; only the leading
# major.minor matters here.
tmux_supports_38() {
	local version major minor
	version="$(tmux display-message -p '#{version}' 2>/dev/null)"
	version="${version#next-}"
	major="${version%%.*}"
	minor="${version#*.}"
	minor="${minor%%[!0-9]*}"
	case "$major$minor" in
		'' | *[!0-9]*) return 1 ;;
	esac
	[ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 8 ]; }
}

if tmux_supports_38; then
	supports_38=1
else
	supports_38=0
fi

set_default_option "@tmux_attention_status" "#{?#{==:#{@agent_attention},input},#{@tmux_attention_icon_input} ,#{?#{==:#{@agent_attention},blocked},#{@tmux_attention_icon_blocked} ,#{?#{==:#{@agent_attention},review},#{@tmux_attention_icon_review} ,#{?#{==:#{@agent_attention},done},#{@tmux_attention_icon_done} ,}}}}"
set_default_option "@tmux_attention_tab_icon" "#{?#{==:#{@agent_attention},input},#{@tmux_attention_icon_input},#{?#{==:#{@agent_attention},blocked},#{@tmux_attention_icon_blocked},#{?#{==:#{@agent_attention},review},#{@tmux_attention_icon_review},#{?#{==:#{@agent_attention},done},#{@tmux_attention_icon_done},#{?#{==:#{@agent_context_active},1},#{?#{==:#{@tmux_attention_working_animation},on},#{E:@tmux_attention_working_spinner},#{@tmux_attention_icon_working}},}}}}}"
# Resolved on every load (not set-if-unset) so frame or tick changes apply on
# reload. Older servers have no A modifier and fall back to the static icon.
if [ "$supports_38" = 1 ]; then
	working_ticks="$(tmux show-option -gqv @tmux_attention_working_frame_ticks 2>/dev/null)"
	working_frames="$(tmux show-option -gqv @tmux_attention_working_frames 2>/dev/null)"
	if [ "$(tmux show-option -gqv @tmux_attention_working_style 2>/dev/null)" = robot ]; then
		working_ticks=2
		working_frames="$(robot_frames)"
	fi
	case "$working_ticks" in
		'' | *[!0-9]*) working_ticks=1 ;;
	esac
	queue_tmux set-option -gq "@tmux_attention_working_spinner" \
		"#{A/${working_ticks}:${working_frames:-⠋,⠙,⠹,⠸,⠼,⠴,⠦,⠧,⠇,⠏}}"
else
	queue_tmux set-option -gq "@tmux_attention_working_spinner" "#{@tmux_attention_icon_working}"
fi
# Context label. Prefers the active turn's project, then the idle label derived from the
# window's active pane (ticket key, else repo name, else directory), and only falls back to
# the raw pane directory when the summary has never run for this window. The point of the
# idle tier is that "which ticket is this window" is useful between turns too, not just
# while an agent is mid-turn; @tmux_attention_icon_working still distinguishes the two.
# Activity suffix is opt-in and off by default. A verb changes on every tool call while the
# status bar repaints on status-interval, so what you read is a sample of what the agent was
# doing some seconds ago; the working icon already answers "is something running here". Set
# @tmux_attention_show_activity to "on" if the extra detail is worth that to you.
set_default_option "@tmux_attention_show_activity" "off"
set_default_option "@tmux_attention_activity_suffix" "#{?#{&&:#{==:#{@tmux_attention_show_activity},on},#{!=:#{@agent_context_activity},}}, #{@agent_context_activity},}"
set_default_option "@tmux_attention_project_separator" " · "

set_default_option "@tmux_attention_context" "#{?#{==:#{@agent_context_active},1},#{@agent_context_project}#{E:@tmux_attention_activity_suffix},#{?#{!=:#{@agent_context_idle_project},},#{@agent_context_idle_project},#{b:pane_current_path}}}"

# Details that follow the context label: one slot, chosen by the pane you are
# looking at, so the parts never pile up.
#   agent pane (owned, or mid-turn): its summary phrase, else the branch PR
#   shell pane: the running or failed command, else the branch PR
# Each part leads with the project separator. Kept separate from
# @tmux_attention_context so themes can place, truncate or drop it:
#   #{E:@tmux_attention_context}#{=/40/…:#{E:@tmux_attention_context_details}}
set_default_option "@tmux_attention_command_duration" "#{?#{e|<:#{pane_command_duration},60},#{pane_command_duration}s,#{?#{e|<:#{pane_command_duration},3600},#{e|/:#{pane_command_duration},60}m,#{e|/:#{pane_command_duration},3600}h}}"
set_default_option "@tmux_attention_command_text" "#{?#{&&:#{==:#{@tmux_attention_command_summary},on},#{&&:#{==:#{@agent_pane_owner}#{@agent_pane_context_active},},#{!=:#{@agent_pane_command},}}},#{?#{==:#{pane_command_running},1},#{E:@tmux_attention_project_separator}⏵ #{@agent_pane_command} #{E:@tmux_attention_command_duration},#{?#{&&:#{!=:#{pane_command_status},},#{!=:#{pane_command_status},0}},#{E:@tmux_attention_project_separator}✗ #{@agent_pane_command},}},}"
set_default_option "@tmux_attention_summary_max" "40"
set_default_option "@tmux_attention_pr_text" "#{?#{!=:#{@agent_context_pr},},#{E:@tmux_attention_project_separator}#{@agent_context_pr},}"
set_default_option "@tmux_attention_context_details" "#{?#{||:#{!=:#{@agent_pane_owner},},#{==:#{@agent_pane_context_active},1}},#{?#{!=:#{@agent_pane_summary},},#{E:@tmux_attention_project_separator}#{@agent_pane_summary},#{E:@tmux_attention_pr_text}},#{?#{!=:#{E:@tmux_attention_command_text},},#{E:@tmux_attention_command_text},#{E:@tmux_attention_pr_text}}}"

# Same resolution for window tabs, but falling back to the window name rather than a
# directory, since that is what a tab shows by default. Pair it with
# @tmux_attention_tab_icon in window-status-format. Intermediate formats keep the policy
# readable and let custom themes reuse the context/specificity separately.
set_default_option "@tmux_attention_tab_context" "#{?#{==:#{@agent_context_active},1},#{?#{!=:#{@agent_context_tab_project},},#{@agent_context_tab_project},#{@agent_context_project}},#{?#{!=:#{@agent_context_idle_tab_project},},#{@agent_context_idle_tab_project},#{?#{!=:#{@agent_context_idle_project},},#{@agent_context_idle_project},#{window_name}}}}"
set_default_option "@tmux_attention_tab_specific" "#{?#{==:#{@agent_context_active},1},#{@agent_context_specific},#{@agent_context_idle_specific}}"
set_default_option "@tmux_attention_tab_mode" "preserve"
set_default_option "@tmux_attention_tab_separator" " · "
#
# Automatic names always become context. Deliberate names use one of three modes:
# preserve (default) keeps the chosen name; smart appends context only when it is an
# explicit override, Jira key, or linked worktree; compact replaces a chosen name with
# that short, meaningful context; context replaces every chosen name.
# This avoids turning distinct tabs into repeated repo names while still allowing an
# agent window to read "codex · FLYWL-2533" in smart mode or just "FLYWL-2533"
# in compact mode when the context is genuinely specific.
set_default_option "@tmux_attention_tab_label" "#{?automatic-rename,#{E:@tmux_attention_tab_context},#{?#{==:#{@tmux_attention_tab_mode},context},#{E:@tmux_attention_tab_context},#{?#{&&:#{==:#{@tmux_attention_tab_mode},compact},#{==:#{E:@tmux_attention_tab_specific},1}},#{E:@tmux_attention_tab_context},#{?#{&&:#{==:#{@tmux_attention_tab_mode},smart},#{==:#{E:@tmux_attention_tab_specific},1}},#{?#{==:#{window_name},#{E:@tmux_attention_tab_context}},#{window_name},#{window_name}#{E:@tmux_attention_tab_separator}#{E:@tmux_attention_tab_context}},#{window_name}}}}}"

# Re-clear the marker shortly after its pane is actually viewed. Cover every
# way a pane becomes visible: selecting its window (after-select-window), attaching a
# client (client-attached), switching sessions — e.g. jumping with tmux-fzf-jump,
# which uses switch-client (client-session-changed), and focusing a pane in it
# (pane-focus-in, which needs `focus-events on`). All share index 90 so
# re-sourcing updates in place instead of appending duplicates. clear-after-delay
# no-ops when the pane has no marker, so the frequent focus hook stays cheap.
clear_on_view="if -F '#{==:#{@tmux_attention_clear_on_view},on}' 'run-shell -b \"\\\"$CURRENT_DIR/scripts/clear-after-delay\\\" \\\"#{pane_id}\\\"\"'"
for hook in after-select-window client-attached client-session-changed pane-focus-in; do
	queue_tmux set-hook -g "${hook}[90]" "$clear_on_view"
done

# Keep the idle context label current. Without this the label would only be recomputed on a
# turn boundary or a pane kill, so a freshly attached server would show nothing until an
# agent ran. These are the "the user is now looking at something else" events, which is
# exactly when the label needs to be right. Deliberately NOT cached on the pane path: a
# `git checkout` changes the branch without changing the directory, which is the common case
# this feature exists for. Two git calls per event, backgrounded, at human pace.
refresh_context="run-shell -b \"\\\"$CURRENT_DIR/scripts/tmux-attention\\\" refresh --target \\\"#{window_id}\\\" >/dev/null 2>&1 || true\""
for hook in after-select-window client-attached client-session-changed pane-focus-in; do
	queue_tmux set-hook -g "${hook}[91]" "$refresh_context"
done

# A pane normally sends turn-stop before it exits. Recompute after an explicit
# kill as well so a vanished pane cannot leave a stale window summary behind.
queue_tmux set-hook -g "after-kill-pane[90]" "run-shell -b \"\\\"$CURRENT_DIR/scripts/tmux-attention\\\" refresh --target \\\"#{window_id}\\\" >/dev/null 2>&1 || true\""

# Long shell commands (tmux 3.8 OSC 133 events). The format gate keeps the hook
# free for short commands and agent-owned panes, so run-shell only spawns when a
# marker will actually be written. pane_command_status/duration describe the
# command that just finished in the hook's pane.
if [ "$supports_38" = 1 ]; then
	shell_done_gate="#{&&:#{==:#{@tmux_attention_shell_done},on},#{&&:#{==:#{@agent_pane_owner},},#{e|>=:#{pane_command_duration},#{@tmux_attention_shell_done_min_seconds}}}}"
	shell_done_run="run-shell -b \"\\\"$CURRENT_DIR/scripts/tmux-attention\\\" #{?#{==:#{pane_command_status},0},done,blocked} --target \\\"#{pane_id}\\\" --source shell --reason #{?#{==:#{pane_command_status},0},command_finished,command_failed} >/dev/null 2>&1 || true\""
	queue_tmux set-hook -g "pane-command-finished[90]" "if -F '$shell_done_gate' '$shell_done_run'"

	# Command summary: forget the previous command synchronously (so a command
	# that ends before the background read cannot inherit the old name), then
	# capture the new one in the background.
	command_gate="#{&&:#{==:#{@tmux_attention_command_summary},on},#{==:#{@agent_pane_owner}#{@agent_pane_context_active},}}"
	command_run="run-shell -b \"\\\"$CURRENT_DIR/scripts/tmux-attention\\\" command-start --target \\\"#{pane_id}\\\" >/dev/null 2>&1 || true\""
	queue_tmux set-hook -g "pane-command-started[90]" "set-option -pq -t '#{pane_id}' @agent_pane_command '' ; if -F '$command_gate' '$command_run'"

	prompt_gate="#{==:#{@tmux_attention_refresh_on_prompt},on}"
	prompt_run="run-shell -b \"\\\"$CURRENT_DIR/scripts/tmux-attention\\\" refresh --target \\\"#{window_id}\\\" >/dev/null 2>&1 || true\""
	queue_tmux set-hook -g "pane-shell-prompt[90]" "if -F '$prompt_gate' '$prompt_run'"
fi

tmux "${load_batch[@]}"
