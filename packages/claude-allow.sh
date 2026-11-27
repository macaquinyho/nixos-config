usage() {
  cat << EOF
Usage: claude-allow [-s SESSION] HOST[:PORT] [DURATION]
       claude-allow [-s SESSION] -c
       claude-allow -l

Lets one claude-sandbox session reach HOST (port 443 by default) until it ends,
or for DURATION (30m, 2h, 1d). A leading dot in HOST also allows its subdomains.

  -s SESSION  the session's id or directory, needed when it is ambiguous
  -c          clear the session's list
  -l          list sessions and what they allow
EOF
}

dir="${XDG_RUNTIME_DIR:?}/$SESSIONS_DIR_NAME"

# a session is live while the pid it recorded still has its netns
live() {
  local id=$1 pid
  pid=$(< "$dir/$id/pid") 2> /dev/null || return 1
  [ "$(stat -L -c %i "/proc/$pid/ns/net" 2> /dev/null)" = "$id" ]
}

sessions=()
for d in "$dir"/*/; do
  [ -d "$d" ] || continue
  id=$(basename "$d")
  [[ $id =~ ^[0-9]+$ ]] || continue
  if live "$id"; then
    sessions+=("$id")
  else
    rm -rf "$d"
  fi
done

list() {
  local id now dest expires
  now=$(date +%s)
  for id in "${sessions[@]}"; do
    echo "$id  $(< "$dir/$id/cwd")"
    while read -r dest expires; do
      [ -n "$dest" ] || continue
      if [ "$expires" = - ]; then
        echo "  $dest  until the session ends"
      elif [ "$expires" -gt "$now" ]; then
        echo "  $dest  until $(date -d "@$expires" '+%a %H:%M')"
      fi
    done < "$dir/$id/allow"
  done
}

pick() {
  local want=$1 id matches=()
  for id in "${sessions[@]}"; do
    if [ -z "$want" ] || [ "$id" = "$want" ] ||
      [ "$(< "$dir/$id/cwd")" = "$(realpath -m -- "$want")" ]; then
      matches+=("$id")
    fi
  done
  # with several sessions and none named, the one started here
  if [ -z "$want" ] && [ ${#matches[@]} -gt 1 ]; then
    matches=()
    for id in "${sessions[@]}"; do
      [ "$(< "$dir/$id/cwd")" = "$PWD" ] && matches+=("$id")
    done
  fi
  case ${#matches[@]} in
    1) echo "${matches[0]}" ;;
    0)
      echo "claude-allow: no matching session" >&2
      list >&2
      return 1
      ;;
    *)
      echo "claude-allow: several sessions match, pick one with -s" >&2
      list >&2
      return 1
      ;;
  esac
}

seconds() {
  [[ $1 =~ ^([0-9]+)([smhd])$ ]] || {
    echo "claude-allow: bad duration $1, expected e.g. 30m, 2h or 1d" >&2
    return 1
  }
  local n=${BASH_REMATCH[1]}
  case ${BASH_REMATCH[2]} in
    s) echo "$n" ;;
    m) echo $((n * 60)) ;;
    h) echo $((n * 3600)) ;;
    d) echo $((n * 86400)) ;;
  esac
}

want=''
clear=''
while getopts "s:clh" opt; do
  case $opt in
    s) want=$OPTARG ;;
    c) clear=1 ;;
    l)
      list
      exit 0
      ;;
    h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done
shift $((OPTIND - 1))

if [ -n "$clear" ]; then
  [ $# -eq 0 ] || {
    usage >&2
    exit 2
  }
  id=$(pick "$want")
  : > "$dir/$id/allow"
  exit 0
fi

[ $# -ge 1 ] && [ $# -le 2 ] || {
  usage >&2
  exit 2
}
dest=${1,,}
[[ $dest == *:* ]] || dest="$dest:443"
[[ $dest =~ ^\.?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*:[0-9]+$ ]] || {
  echo "claude-allow: expected HOST[:PORT], got $1" >&2
  exit 2
}
port=${dest##*:}
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || {
  echo "claude-allow: bad port $port" >&2
  exit 2
}
expires=-
if [ $# -eq 2 ]; then
  # a plain assignment, so set -e stops on a bad duration
  secs=$(seconds "$2")
  expires=$(($(date +%s) + secs))
fi

id=$(pick "$want")
allow="$dir/$id/allow"
now=$(date +%s)
{
  # drop expired entries and any older one for the same destination
  while read -r d e; do
    [ -n "$d" ] && [ "$d" != "$dest" ] || continue
    [ "$e" = - ] || [ "$e" -gt "$now" ] || continue
    echo "$d $e"
  done < "$allow"
  echo "$dest $expires"
} > "$allow.new"
mv "$allow.new" "$allow"

if [ "$expires" = - ]; then
  echo "allowed $dest for $(< "$dir/$id/cwd") until the session ends"
else
  echo "allowed $dest for $(< "$dir/$id/cwd") until $(date -d "@$expires" '+%a %H:%M')"
fi
