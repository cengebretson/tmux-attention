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
set_default_option "@tmux_attention_context" "#{?#{==:#{@agent_context_active},1},#{@agent_context_project},#{b:pane_current_path}}"

# Re-clear the marker shortly after its window is actually viewed. Cover every
# way a window becomes visible: selecting it (after-select-window), attaching a
# client (client-attached), switching sessions — e.g. jumping with tmux-fzf-jump,
# which uses switch-client (client-session-changed), and focusing a pane in it
# (pane-focus-in, which needs `focus-events on`). All share index 90 so
# re-sourcing updates in place instead of appending duplicates. clear-after-delay
# no-ops when the window has no marker, so the frequent focus hook stays cheap.
clear_on_view="if -F '#{==:#{@tmux_attention_clear_on_view},on}' 'run-shell -b \"\\\"$CURRENT_DIR/scripts/clear-after-delay\\\" \\\"#{window_id}\\\"\"'"
for hook in after-select-window client-attached client-session-changed pane-focus-in; do
	queue_tmux set-hook -g "${hook}[90]" "$clear_on_view"
done

tmux "${load_batch[@]}"
