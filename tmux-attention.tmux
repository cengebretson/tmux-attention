#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set_default_option() {
	local option="$1"
	local value="$2"

	if ! tmux show-option -g "$option" >/dev/null 2>&1; then
		tmux set-option -gq "$option" "$value"
	fi
}

set_default_option "@tmux_attention_icon_input" "󱐋"
set_default_option "@tmux_attention_icon_blocked" ""
set_default_option "@tmux_attention_icon_review" "󰛨"
set_default_option "@tmux_attention_icon_done" ""
set_default_option "@tmux_attention_clear_delay" "8"
set_default_option "@tmux_attention_clear_on_view" "on"
set_default_option "@tmux_attention_cli" "$CURRENT_DIR/scripts/tmux-attention"

set_default_option "@tmux_attention_status" "#{?#{==:#{@agent_attention},input},#{@tmux_attention_icon_input} ,#{?#{==:#{@agent_attention},blocked},#{@tmux_attention_icon_blocked} ,#{?#{==:#{@agent_attention},review},#{@tmux_attention_icon_review} ,#{?#{==:#{@agent_attention},done},#{@tmux_attention_icon_done} ,}}}}"

tmux set-hook -g "after-select-window[90]" "if -F '#{==:#{@tmux_attention_clear_on_view},on}' 'run-shell -b \"\\\"$CURRENT_DIR/scripts/clear-after-delay\\\" \\\"#{window_id}\\\"\"'"
tmux set-hook -g "client-attached[90]" "if -F '#{==:#{@tmux_attention_clear_on_view},on}' 'run-shell -b \"\\\"$CURRENT_DIR/scripts/clear-after-delay\\\" \\\"#{window_id}\\\"\"'"
