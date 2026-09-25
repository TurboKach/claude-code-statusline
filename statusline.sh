#!/usr/bin/env bash
# Claude Code status line

input=$(cat)

# --- Parse input JSON in one jq pass (\x1f separator preserves empty fields) ---
IFS=$'\x1f' read -r cwd model model_id used_pct ctx_size total_input total_output \
  fh_pct fh_reset sd_pct sd_reset transcript_path effort session_name proj_idx < <(jq -rj '[
    .workspace.current_dir // .cwd // "",
    .model.display_name // "",
    .model.id // "",
    .context_window.used_percentage // "",
    .context_window.context_window_size // "",
    .context_window.total_input_tokens // 0,
    .context_window.total_output_tokens // 0,
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.five_hour.resets_at // "",
    .rate_limits.seven_day.used_percentage // "",
    .rate_limits.seven_day.resets_at // "",
    .transcript_path // "",
    .effort.level // "",
    # drop control chars so a session name cannot break the read or inject ANSI/OSC into the bar
    (.session_name // "" | gsub("[[:cntrl:]]"; "")),
    # per-project color index: stable string hash of the launch dir
    (.workspace.project_dir // .cwd // "" | reduce explode[] as $c (0; (. * 31 + $c) % 65521) % 8)
  ] | join([31]|implode)' <<<"$input")

# effort.level (CC >= 2.1.122) is the live session value: tracks mid-session
# /effort changes, reports ultracode as xhigh, and is empty on models that
# do not support effort (so the bar self-hides, e.g. on Haiku).

# Ultracode (xhigh + workflow orchestration) reports as plain "xhigh" in stdin,
# so when at xhigh we peek at the transcript for the most recent /effort command.
# Scoped to the <local-command-stdout> wrapper + user-string lines, so quoted
# mentions in chat or tool output can't false-match. Last command wins (switching
# away self-corrects); falls back to plain xhigh if the format ever changes.
if [ "$effort" = "xhigh" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  last_effort=$(tail -n 2000 "$transcript_path" 2>/dev/null | jq -r '
    select(.type == "user")
    | .message.content
    | select(type == "string")
    | capture("<local-command-stdout>Set effort level to (?<e>[a-z]+)")
    | .e
  ' 2>/dev/null | tail -n 1)
  [ "$last_effort" = "ultracode" ] && effort="ultracode"
fi

# --- Colors (256-palette) ---
grey=$'\033[38;5;245m'
dim_grey=$'\033[2;38;5;238m'
cyan=$'\033[38;5;51m'
orange=$'\033[38;5;208m'
green=$'\033[38;5;46m'
yellow=$'\033[38;5;226m'
red=$'\033[38;5;196m'
magenta=$'\033[38;5;201m'
reset=$'\033[0m'

pct_color() {
  if [ "$1" -ge 75 ]; then printf '%s' "$red"
  elif [ "$1" -ge 50 ]; then printf '%s' "$yellow"
  else printf '%s' "$green"
  fi
}

countdown() {
  local diff=$(( $1 - $(date +%s) ))
  [ "$diff" -le 0 ] && return
  local h=$((diff / 3600)) m=$(( (diff % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then printf '~%dh%02dm' "$h" "$m"
  else printf '~%dm' "$m"
  fi
}

# Render the effort bar: `total` cells (one per level the model supports), the
# first `pos` filled in their hue and the rest dim. Trailing dim cells are the
# model's remaining headroom, so a full bar means "maxed for this model".
effort_bar() {
  local pos=$1 total=$2 i
  local chars=("▁" "▃" "▅" "▇" "█")
  local hues=($'\033[38;5;46m' $'\033[38;5;226m' $'\033[38;5;214m' $'\033[38;5;202m' $'\033[38;5;196m')
  for ((i = 0; i < total; i++)); do
    if [ $((i + 1)) -le "$pos" ]; then
      printf '%s%s' "${hues[$i]}" "${chars[$i]}"
    else
      printf '%s%s' "$dim_grey" "${chars[$i]}"
    fi
  done
  printf '%s' "$reset"
}

# --- Line 1: dir + branch + model + effort bar ---
tilde="~"   # via a variable: a literal ~ in the replacement re-expands to $HOME in bash 5.2+
line1="${grey}${cwd/#$HOME/$tilde}${reset}"
# branch, or short sha when detached; both fail silently outside a repo
branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null \
         || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
[ -n "$branch" ] && line1+=" ${cyan}${branch}${reset}"
[ -n "$model" ] && line1+=" ${orange}${model}${reset}"

if [ -n "$effort" ]; then
  # Effort levels the active model supports, low->high. Keep in sync with
  # platform.claude.com/docs/en/build-with-claude/effort. Unknown/future models
  # fall back to the full scale so a real effort value is never hidden or trimmed.
  case "$model_id" in
    *opus-4-8*|*opus-4-7*)            levels="low medium high xhigh max" ;;
    *opus-4-6*|*sonnet-4-6*|*mythos*) levels="low medium high max" ;;
    *opus-4-5*)                       levels="low medium high" ;;
    *)                                levels="low medium high xhigh max" ;;
  esac

  # Ultracode = xhigh + workflow orchestration: render at the xhigh slot + a badge.
  level="$effort"; badge=""
  [ "$effort" = "ultracode" ] && { level="xhigh"; badge="${magenta}↯${reset}"; }

  set -- $levels
  pos=""; i=1
  for l in "$@"; do [ "$l" = "$level" ] && { pos=$i; break; }; i=$((i + 1)); done

  if [ -n "$pos" ]; then
    line1+=$(effort_bar "$pos" "$#")
    line1+="$badge"
  else
    line1+="${orange}${effort}${reset}"   # level not valid for this model: show raw
  fi
fi

# --- Line 2: context usage + rate limits ---
line2=""
if [ -n "$used_pct" ] && [ -n "$ctx_size" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  used_k=$(( (total_input + total_output) / 1000 ))
  max_k=$((ctx_size / 1000))
  if [ "$max_k" -ge 1000 ]; then max_label="$((max_k / 1000))M"
  else max_label="${max_k}k"
  fi
  line2+="$(pct_color "$used_int")${used_k}k/${max_label} (${used_int}%)${reset}"
fi

rate_limit() {
  local pct=$1 reset_at=$2 label=$3
  [ -z "$pct" ] && return
  local n; n=$(printf '%.0f' "$pct")
  [ -n "$line2" ] && line2+="  "
  line2+="$(pct_color "$n")${label}:${n}%${reset}"
  if [ "$n" -ge 75 ] && [ -n "$reset_at" ]; then
    local cd; cd=$(countdown "$reset_at")
    [ -n "$cd" ] && line2+="${red} ${cd}${reset}"
  fi
}
rate_limit "$fh_pct" "$fh_reset" "5h"
rate_limit "$sd_pct" "$sd_reset" "7d"

# --- Line 0: session name (/rename or Claude's auto-generated title), colored per project ---
if [ -n "$session_name" ]; then
  proj_hues=(75 215 114 177 221 80 211 252)   # mid-bright: sky orange green purple gold teal rose grey
  printf '\033[38;5;%sm%s%s\n' "${proj_hues[$proj_idx]}" "$session_name" "$reset"
fi
printf '%s\n%s\n' "$line1" "$line2"
