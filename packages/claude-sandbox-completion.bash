_claude_sandbox() {
  local cur=${COMP_WORDS[COMP_CWORD]} i=1
  COMPREPLY=()

  # the wrapper's flags come first, claude's own arguments have no completion
  while [ "$i" -lt "$COMP_CWORD" ]; do
    case ${COMP_WORDS[i]} in
      --dev-bind | --netif | --add-dir) i=$((i + 2)) ;;
      *) return 0 ;;
    esac
  done

  if [ "$i" -gt "$COMP_CWORD" ]; then
    case ${COMP_WORDS[COMP_CWORD - 1]} in
      --dev-bind) mapfile -t COMPREPLY < <(compgen -f -- "${cur:-/dev/}") ;;
      --netif) mapfile -t COMPREPLY < <(compgen -W "$(ls /sys/class/net)" -- "$cur") ;;
      --add-dir) mapfile -t COMPREPLY < <(compgen -d -- "$cur") ;;
    esac
  elif [[ $cur == -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W "--dev-bind --netif --add-dir --git-auth --exec" -- "$cur")
  fi
}
complete -o default -F _claude_sandbox claude
