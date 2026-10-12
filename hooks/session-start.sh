#!/usr/bin/env bash
# SessionStart hook for the bash-statusline plugin.
#
# A plugin cannot set `statusLine`, and ${CLAUDE_PLUGIN_ROOT} changes on every
# update, so this hook (1) keeps a stable symlink in ${CLAUDE_PLUGIN_DATA} that
# points at the current statusline.sh and (2) adds `statusLine` to the user's
# settings.json whenever it has none. A different existing statusLine is replaced
# once per install, and only when the plugin option replace_existing is on. The
# settings edit copies install.sh's add and replace branches (plain-text, no jq).
#
# Claude Code rewrites settings.json from its in-memory copy and keeps an external
# edit only if its file watcher saw it. The watcher starts about when this hook
# ends, so a write needs a delay (2 s) to land after it; the hook reads, decides
# and writes only after that delay (a write that was not needed does not sleep).
# A missing block is added back in a later session if Claude Code still drops it.
#
# Contract: exit code is always 0; stdout is empty, except for one JSON
# `systemMessage` notice (once per reason) when the bar could not be set up.

main() {
  local root=${CLAUDE_PLUGIN_ROOT:-} data=${CLAUDE_PLUGIN_DATA:-}
  [ -n "$root" ] && [ -n "$data" ] || return 0
  # Claude Code marks the previous version dir on update/uninstall; an old
  # session still runs its old hook, which must not act.
  [ -e "$root/.orphaned_at" ] && return 0

  local input="" show=0
  [ -t 0 ] || input=$(cat 2>/dev/null)
  local src_re='"source"[[:space:]]*:[[:space:]]*"(startup|resume)"'
  [[ $input =~ $src_re ]] && show=1

  # --- stable link: new link under a temp name, then rename over the old one ---
  local link="$data/statusline.sh"
  mkdir -p "$data" 2>/dev/null || return 0
  if [ "$(readlink "$link" 2>/dev/null)" != "$root/statusline.sh" ]; then
    local ltmp="$data/.statusline.sh.$$"
    rm -f "$ltmp" 2>/dev/null
    if ln -s "$root/statusline.sh" "$ltmp" 2>/dev/null; then
      mv -f "$ltmp" "$link" 2>/dev/null || rm -f "$ltmp" 2>/dev/null
    fi
    [ "$(readlink "$link" 2>/dev/null)" = "$root/statusline.sh" ] || return 0
  fi

  # --- settings ---
  local marker="$data/.statusline-replaced"   # a different statusLine was replaced once
  local sq="'" esc="'\\''" q cmd cmd_json
  q=${data//$sq/$esc}
  cmd="bash '$q/statusline.sh'"
  cmd_json=$(json_esc "$cmd")
  local entry="\"statusLine\": { \"type\": \"command\", \"command\": \"$cmd_json\", \"refreshInterval\": 60 }"

  local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  local target=$cfg l n=0
  while [ -L "$target" ] && [ "$n" -lt 10 ]; do   # write through a symlinked settings.json
    l=$(readlink "$target")
    case $l in /*) target=$l ;; *) target=$(dirname "$target")/$l ;; esac
    n=$((n + 1))
  done

  local on=0
  case $(printf '%s' "${CLAUDE_PLUGIN_OPTION_REPLACE_EXISTING:-}" | tr '[:upper:]' '[:lower:]') in
    true|1) on=1 ;;
  esac

  # BASH_STATUSLINE_TEST_DELAY: test-only override of the write delay (seconds).
  local delay=${BASH_STATUSLINE_TEST_DELAY:-2} attempt
  [[ $delay =~ ^[0-9]+(\.[0-9]+)?$ ]] || delay=2

  # Attempt 1 decides without sleeping; if it needs a write, sleep, then attempt 2
  # reads settings.json again and decides and writes from that fresh read.
  for attempt in 1 2; do
    local json="" new="" had_file=0 action=add
    if [ -e "$target" ]; then
      had_file=1
      if ! json=$(<"$target") 2>/dev/null; then
        notice writefail "could not read $cfg. Add the block by hand, see the README"
        return 0
      fi
      local re='"statusLine"[[:space:]]*:[[:space:]]*\{([^{}"]|"([^"\\]|\\.)*")*\}'
      local key_re='"statusLine"[[:space:]]*:' cmd_re='"command"[[:space:]]*:[[:space:]]*"'
      local obj_re='^[[:space:]]*\{' empty_re='^[[:space:]]*(\{[[:space:]]*\})?[[:space:]]*$'
      local m="" pre rest
      # only a "statusLine" used as an object key counts; a string value is never followed by ':'
      if [[ $json =~ $key_re ]]; then
        [[ $json =~ $re ]] && m=${BASH_REMATCH[0]}
        # ours = the command value of the statusLine block the replace below would match
        if [ -n "$m" ] && [[ $m =~ $cmd_re ]]; then
          rest=${m#*"${BASH_REMATCH[0]}"}
          [[ $rest == "$cmd_json\""* ]] && return 0
        fi
        if [ "$on" -ne 1 ]; then
          notice existing "a status line is already set in $cfg and was left alone. To use this one, turn on 'Replace an existing status line' in /plugin -> Installed -> bash-statusline -> Configure options, then start a new session"
          return 0
        fi
        [ -e "$marker" ] && return 0
        if [ -n "$m" ]; then
          action=replace
          pre=${json%%"$m"*}
          new="$pre$entry${json#*"$m"}"
        else
          notice unmatched "the statusLine in $cfg cannot be replaced automatically. Add the block by hand, see the README"
          return 0
        fi
      elif [[ $json =~ $empty_re ]]; then
        new="{ $entry }"
      elif [[ $json =~ $obj_re ]]; then
        pre=${json%%\{*}
        new="$pre{
    $entry,${json#*\{}"
      else
        notice notobject "$cfg is not a JSON object. Fix it or add the block by hand, see the README"
        return 0
      fi
    else
      new="{
    $entry
  }"
    fi

    if [ "$attempt" = 1 ]; then
      sleep "$delay" 2>/dev/null
      continue
    fi
    if write_settings "$target" "$new" "$had_file"; then
      [ "$action" = replace ] && touch "$marker" 2>/dev/null
    else
      notice writefail "could not write $cfg. Add the block by hand, see the README"
    fi
  done
  return 0
}

# JSON-escape \, " and the control characters U+0001..U+001F (as \u00XX)
json_esc() {
  local s=${1//\\/\\\\} i h c e
  s=${s//\"/\\\"}
  if [[ $s == *[[:cntrl:]]* ]]; then
    for ((i = 1; i < 32; i++)); do
      printf -v h '%02x' "$i"
      printf -v c "\\x$h"
      e="\\u00$h"
      s=${s//"$c"/"$e"}
    done
  fi
  printf '%s' "$s"
}

# write_settings <target> <content> <had_file>: one backup (existing file only),
# then mktemp + mv in the target's dir; a failed write removes the backup.
write_settings() {
  local target=$1 content=$2 had=$3 bak="" tmp
  if [ "$had" = 1 ]; then
    bak="$target.bak.$(date +%s)"
    cp "$target" "$bak" 2>/dev/null || { rm -f "$bak" 2>/dev/null; return 1; }
  fi
  tmp=$(mktemp "$(dirname "$target")/.settings.XXXXXX" 2>/dev/null) || { [ -n "$bak" ] && rm -f "$bak" 2>/dev/null; return 1; }
  if printf '%s\n' "$content" > "$tmp" 2>/dev/null && mv "$tmp" "$target" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  [ -n "$bak" ] && rm -f "$bak" 2>/dev/null
  return 1
}

# notice <reason> <text>: once per reason, only for startup/resume sources
# (a clear/compact run shows nothing a hook returns). The marker is touched only
# when the notice is printed.
notice() {
  [ "$show" = 1 ] || return 0
  local nm="$data/.notice-$1"
  [ -e "$nm" ] && return 0
  touch "$nm" 2>/dev/null || return 0
  printf '{"systemMessage":"%s"}\n' "$(json_esc "bash-statusline: not set up, $2.")"
}

main
exit 0
