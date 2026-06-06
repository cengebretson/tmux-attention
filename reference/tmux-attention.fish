function tmux-attention --description 'Show an attention marker in tmux'
    set -l state input
    if test (count $argv) -gt 0
        set state $argv[1]
    end

    switch $state
        case input blocked review done clear none off
        case --help -h help
            printf 'Usage: tmux-attention [input|blocked|review|done|clear]\n'
            printf '       tmux-attention --install [claude|codex|all]\n'
            return 0
        case --install
            printf 'tmux-attention: hook installation is specified in ~/.config/tmux/attention-marker.md but is not implemented yet.\n' >&2
            printf 'Usage: tmux-attention --install [claude|codex|all]\n' >&2
            return 2
        case '*'
            printf 'tmux-attention: unknown state: %s\n' "$state" >&2
            printf 'Usage: tmux-attention [input|blocked|review|done|clear]\n' >&2
            printf '       tmux-attention --install [claude|codex|all]\n' >&2
            return 2
    end

    if test -z "$TMUX_PANE"
        printf '\a'
        return 0
    end

    set -l target "$TMUX_PANE"

    if contains -- $state clear none off
        tmux set-window-option -t "$target" @agent_attention ''
        return 0
    end

    tmux set-window-option -t "$target" @agent_attention "$state"

    set -l attached (tmux display-message -p -t "$target" '#{session_attached}')
    set -l active (tmux display-message -p -t "$target" '#{window_active}')
    if test "$attached" != 0; and test "$active" = 1
        tmux run-shell -b "sleep 8; tmux set-window-option -t '$target' @agent_attention ''"
    end
end
