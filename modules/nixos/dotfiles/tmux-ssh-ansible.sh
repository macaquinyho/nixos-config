#!/usr/bin/env bash

JQ_CMD='._meta.hostvars as $hostvars |
[to_entries[] |
select(.key != "_meta" and .key != "all") |
try .value.hosts[] as $hostname |
($hostvars[$hostname].ansible_host) as $ansiblehost |
($ansiblehost // $hostname) as $target |
(if $ansiblehost != null and $ansiblehost != $hostname then "\($hostname)-->\($ansiblehost)" else $hostname end) as $display |
"\($display) \($target)"] | unique[]'

readarray -t selected_target < <(
        ansible-inventory -i "$ANSIBLE_INV" --list --export |
                jq -r "$JQ_CMD" |
                fzf --delimiter=' ' --with-nth=1 --multi --tmux --border --prompt="Target(s): " |
                awk -F ' ' '{print $2}'
)
# fzf delimiters dont work https://github.com/junegunn/fzf/issues/2154

for host in "${selected_target[@]}"; do
        if [ -n "$host" ]; then
                tmux new-window -n "ssh:${host}" "ssh '${host}'; tmux set-option -w automatic-rename on && exec $SHELL"
        fi
done

exit 0
