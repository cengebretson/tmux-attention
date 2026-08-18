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

set_default_option "@tmux_attention_status" "#{?#{==:#{@agent_attention},input},#{@tmux_attention_icon_input} ,#{?#{==:#{@agent_attention},blocked},#{@tmux_attention_icon_blocked} ,#{?#{==:#{@agent_attention},review},#{@tmux_attention_icon_review} ,#{?#{==:#{@agent_attention},done},#{@tmux_attention_icon_done} ,}}}}"
set_default_option "@tmux_attention_tab_icon" "#{?#{==:#{@agent_attention},input},#{@tmux_attention_icon_input},#{?#{==:#{@agent_attention},blocked},#{@tmux_attention_icon_blocked},#{?#{==:#{@agent_attention},review},#{@tmux_attention_icon_review},#{?#{==:#{@agent_attention},done},#{@tmux_attention_icon_done},#{?#{==:#{@agent_context_active},1},#{@tmux_attention_icon_working},}}}}}"
# Context label. Prefers the active turn's project, then the idle label derived from the
# window's active pane (ticket key, else repo name, else directory), and only falls back to
# the raw pane directory when the summary has never run for this window. The point of the
# idle tier is that "which ticket is this window" is useful between turns too, not just
# while an agent is mid-turn; @tmux_attention_icon_working still distinguishes the two.
set_default_option "@tmux_attention_context" "#{?#{==:#{@agent_context_active},1},#{@agent_context_project},#{?#{!=:#{@agent_context_idle_project},},#{@agent_context_idle_project},#{b:pane_current_path}}}"

# Same resolution for window tabs, but falling back to the window name rather than a
# directory, since that is what a tab shows by default. Pair it with
# @tmux_attention_tab_icon in window-status-format.
set_default_option "@tmux_attention_tab_label" "#{?#{==:#{@agent_context_active},1},#{@agent_context_project},#{?#{!=:#{@agent_context_idle_project},},#{@agent_context_idle_project},#{window_name}}}"

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

tmux "${load_batch[@]}"
