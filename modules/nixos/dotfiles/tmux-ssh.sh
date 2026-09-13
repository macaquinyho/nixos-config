#!/usr/bin/env bash

KNOWN_HOSTS_FILE="${HOME}/.ssh/known_hosts"

if [ -z "$TMUX" ]; then
        echo "Error: This script must be run inside a tmux session." >&2
        exit 1
fi

if ! command -v fzf &>/dev/null; then
        echo "Error: fzf command not found." >&2
        exit 1
fi

if [ ! -f "$KNOWN_HOSTS_FILE" ]; then
        echo "Error: Known hosts file not found at $KNOWN_HOSTS_FILE" >&2
        exit 1
fi

host_list=$(awk '!/^#/ && !/^\|/ {print $1}' "$KNOWN_HOSTS_FILE" |
        tr ',' '\n' |
        sed -e 's/^\[//' -e 's/\].*$//' |
        sort -u)

if [ -z "$host_list" ]; then
        echo "No valid host entries found in $KNOWN_HOSTS_FILE."
        exit 0
fi

mapfile -t fzf_output < <(echo "$host_list" | fzf --multi --prompt="Select hosts [TAB to mark multi-select]: " --print-query --tmux --border)

query="${fzf_output[0]}"
selections=("${fzf_output[@]:1}")

if [[ ${#selections[@]} -eq 0 && -n "$query" ]]; then
        selections=("$query")
fi

for host in "${selections[@]}"; do
        trimmed_host=$(echo "$host" | xargs)
        if [ -n "$trimmed_host" ]; then
                tmux new-window -n "ssh:${trimmed_host}" "ssh '${trimmed_host}'; tmux set-option -w automatic-rename on && exec $SHELL"
        fi
done

exit 0
