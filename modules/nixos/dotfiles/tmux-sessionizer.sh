#!/usr/bin/env bash

roots=( "$HOME/projects" "/workspace/projects" "$HOME/assig" )
final_roots=()
for dir in "${roots[@]}"; do
    [ -d "$dir" ] && final_roots+=("$dir")
done

# shellcheck disable=SC2016
selected="$(find "${final_roots[@]}" -mindepth 1 -maxdepth 1 -type d \
    | fzf --header="Pick a project" \
        --preview 'echo "HEAD: $(git -C {} rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")"; echo; \
            git -C {} -c color.ui=always log --oneline --decorate --graph -25 2>/dev/null || ls -la {}')"

if [[ -z $selected ]]; then
    exit 0
fi

selected_name=$(basename "$selected" | tr './: ' '____')

tmux_running=$(pgrep tmux)

if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
    tmux new-session -s "$selected_name" -c "$selected"
    exit 0
fi

if ! tmux has-session -t="$selected_name" 2> /dev/null; then
    tmux new-session -ds "$selected_name" -c "$selected"
fi

if [ -z "$TMUX" ]; then   # si estamos fuera de tmux hacemos attach
    tmux attach -t "$selected_name"
else                    # si estamos dentro solo cambiamos el cliente
    tmux switch-client -t "$selected_name"
fi
