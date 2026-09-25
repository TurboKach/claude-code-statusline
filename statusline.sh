#!/usr/bin/env bash
# Claude Code status line

# --- Parse input JSON in one awk pass (\x1f separator preserves empty fields) ---
# awk is POSIX and ships with every macOS and Linux, so there is nothing to install.
IFS=$'\x1f' read -r cwd model model_id used_pct ctx_size total_input total_output \
  fh_pct fh_reset sd_pct sd_reset transcript_path effort session_name proj_idx < <(LC_ALL=C awk -v FS=$'\x1f' '
  # A tiny JSON reader: walks the tokens tracking the path of every value (.a.b, arrays
  # as []), like jq, so key order, whitespace, new fields and nesting do not matter.
  # String at path p, unescaped, with control chars dropped: a \x1f or newline in a value
  # (e.g. a directory name) would shift text into numeric fields that bash evaluates as
  # arithmetic, which runs $(...); it also keeps ANSI/OSC in names from hijacking the bar.
  function str(p,   x, o, i, c) {
    if (!(p in v) || !isstr[p]) return ""
    x = v[p]; o = ""
    for (i = 1; i <= length(x); i++) {
      c = substr(x, i, 1)
      # \u escapes are dropped: Claude Code only emits them for control chars
      if (c == "\\") { c = substr(x, ++i, 1); if (c == "u") { i += 4; c = "" } else if (c != "\"" && c != "\\" && c != "/") c = "" }
      else if (c == c2 && index(c1, substr(x, i + 1, 1))) { i++; c = "" }   # UTF-8 C1 control
      if (!index(cntrl, c)) o = o c
    }
    return o
  }
  # number at path p, floored (or rounded if r). Digits only, because bash arithmetic
  # runs $(...) inside a string; exponents and absurd sizes count as absent.
  function num(p, r) {
    if (!(p in v) || isstr[p] || v[p] !~ /^[0-9]+(\.[0-9]+)?$/ || v[p] + 0 >= 1e15) return ""
    return sprintf("%.0f", int(v[p] + (r ? 0.5 : 0)))
  }
  function dflt(a, b) { return a != "" ? a : b }
  BEGIN {
    d = 0
    for (i = 1; i < 256; i++) {
      c = sprintf("%c", i); ord[c] = i
      if (i < 32 || i == 127) cntrl = cntrl c; else if (i >= 128 && i < 160) c1 = c1 c; else if (i == 194) c2 = c
    }
  }
  { s = s $0 " " }
  END {
    while (s != "") {
      if (match(s, /^[ \t\r\n,:]+/)) { s = substr(s, RLENGTH + 1); continue }
      c = substr(s, 1, 1)
      if (c == "}" || c == "]") { d--; iskey[d] = (t[d] == "{"); s = substr(s, 2); continue }
      here = !d ? "" : t[d] == "{" ? p[d] "." k[d] : p[d] "[]"
      if (c == "{" || c == "[") { d++; t[d] = c; p[d] = here; iskey[d] = (c == "{"); s = substr(s, 2); continue }
      if (c == "\"") { if (!match(s, /^"([^"\\]|\\.)*"/)) break; tok = substr(s, 2, RLENGTH - 2) }
      else { if (!match(s, /^[-+.0-9A-Za-z]+/)) break; tok = substr(s, 1, RLENGTH) }
      s = substr(s, RLENGTH + 1)
      if (iskey[d]) { k[d] = tok; iskey[d] = 0; continue }
      v[here] = tok; isstr[here] = (c == "\""); iskey[d] = (t[d] == "{")
    }
    # per-project color index: stable string hash of the launch dir
    x = dflt(str(".workspace.project_dir"), str(".cwd")); h = 0
    for (i = 1; i <= length(x); i++) h = (h * 31 + ord[substr(x, i, 1)]) % 65521
    printf "%s", dflt(str(".workspace.current_dir"), str(".cwd")) FS str(".model.display_name") FS str(".model.id") FS \
      num(".context_window.used_percentage", 1) FS num(".context_window.context_window_size") FS \
      dflt(num(".context_window.total_input_tokens"), 0) FS dflt(num(".context_window.total_output_tokens"), 0) FS \
      num(".rate_limits.five_hour.used_percentage", 1) FS num(".rate_limits.five_hour.resets_at") FS \
      num(".rate_limits.seven_day.used_percentage", 1) FS num(".rate_limits.seven_day.resets_at") FS \
      str(".transcript_path") FS str(".effort.level") FS str(".session_name") FS h % 8
  }')

# effort.level (CC >= 2.1.122) is the live session value: tracks mid-session
# /effort changes, reports ultracode as xhigh, and is empty on models that
# do not support effort (so the bar self-hides, e.g. on Haiku).

# Ultracode (xhigh + workflow orchestration) reports as plain "xhigh" in stdin,
# so when at xhigh the transcript's most recent /effort output decides (last command
# wins, so switching away self-corrects). The needle includes the JSON key, so only a
# real command-output line matches: quoted mentions in chat or tool output have their
# quotes escaped (\"content\":\"...). Two greps because macOS grep scans ~2x slower
# with the leading quote; the second one only sees the few prefiltered lines.
# LC_ALL=C: macOS grep is ~5x slower in a UTF-8 locale; the needles are ASCII.
# Falls back to plain xhigh if the format ever changes.
if [ "$effort" = "xhigh" ] && [ -f "$transcript_path" ]; then
  last_effort=$(LC_ALL=C grep -F '<local-command-stdout>Set effort level to' "$transcript_path" 2>/dev/null \
    | LC_ALL=C grep -F '"content":"<local-command-stdout>Set effort level to ' | tail -n 1)
  [[ $last_effort == *'"type":"user"'* && $last_effort == *'Set effort level to ultracode'* ]] && effort="ultracode"
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
# Claude Code's own /effort colors (truecolor), looked up by name as eff_<level>
eff_low=$'\033[38;2;255;193;7m' eff_medium=$'\033[38;2;78;186;101m' eff_high=$'\033[38;2;177;185;249m'
eff_xhigh=$'\033[38;2;175;135;255m' eff_max=$'\033[38;2;200;130;180m'

# Helpers set variables / append to the line directly: $(...) would fork a subshell.
pct_color() {   # sets c
  if [ "$1" -ge 75 ]; then c=$red
  elif [ "$1" -ge 50 ]; then c=$yellow
  else c=$green
  fi
}

countdown() {   # sets cd
  [ -z "$now" ] && now=${EPOCHSECONDS:-$(date +%s)}   # builtin on bash 5; one date fork on 3.2, only when needed
  local diff=$(( $1 - now )); cd=""
  [ "$diff" -le 0 ] && return
  local h=$((diff / 3600)) m=$(( (diff % 3600) / 60 ))
  if [ "$h" -ge 24 ]; then printf -v cd '%dd%dh' $((h / 24)) $((h % 24))
  elif [ "$h" -gt 0 ]; then printf -v cd '%dh%02dm' "$h" "$m"
  else printf -v cd '%dm' "$m"
  fi
}

# Append the effort bar to line1: one cell per level the model supports ($2...),
# the first `pos` ($1) each in its own level's color and the rest dim. Trailing dim
# cells are the model's remaining headroom, so a full bar means "maxed for this model".
effort_bar() {
  local pos=$1 i=0 l v
  local chars=("▁" "▃" "▅" "▇" "█")
  shift
  for l in "$@"; do
    if [ "$i" -lt "$pos" ]; then v=eff_$l; line1+=${!v}; else line1+=$dim_grey; fi
    line1+=${chars[$i]}; i=$((i + 1))
  done
  line1+=$reset
}

# --- Line 1: dir + branch + model + effort bar ---
tilde="~"   # via a variable: a literal ~ in the replacement re-expands to $HOME in bash 5.2+
line1="${grey}${cwd/#$HOME/$tilde}${reset}"
# branch, or short sha when detached, read straight from .git/HEAD (no git process).
# A .git file is a worktree/submodule pointer ("gitdir: <path>"). Reftable repos keep
# a placeholder HEAD, so those ask git (if installed); outside a repo nothing shows.
d=$cwd branch=""
while [ -n "$d" ] && [ ! -e "$d/.git" ]; do d=${d%/*}; done
g=$d/.git
if [ -f "$g" ]; then read -r g < "$g"; g=${g#gitdir: }; [ "${g#/}" = "$g" ] && g=$d/$g; fi
if [ -n "$d" ] && read -r head 2>/dev/null < "$g/HEAD"; then
  case $head in
    "ref: refs/heads/.invalid") branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null \
                                         || git -C "$cwd" rev-parse --short HEAD 2>/dev/null) ;;
    "ref: refs/heads/"*) branch=${head#ref: refs/heads/} ;;
    *) branch=${head:0:7} ;;
  esac
fi
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
  level="$effort"
  [ "$effort" = "ultracode" ] && level="xhigh"

  set -- $levels
  pos=""; i=1
  for l in "$@"; do [ "$l" = "$level" ] && { pos=$i; break; }; i=$((i + 1)); done

  if [ -n "$pos" ]; then
    effort_bar "$pos" "$@"
    [ "$effort" = "ultracode" ] && line1+="${magenta}↯${reset}"
    v=eff_$level; label="${!v}${effort}"
    [ "$level" = "max" ] && label=$'\033[38;2;130;170;220mm\033[38;2;155;130;200ma'"${eff_max}x"   # per-letter gradient
    line1+=" ${label}${reset}"
  else
    line1+="${orange}${effort}${reset}"   # level not valid for this model: show raw
  fi
fi

# --- Line 2: context usage + rate limits ---
line2=""
if [ -n "$used_pct" ] && [ -n "$ctx_size" ]; then
  used_k=$(( (total_input + total_output) / 1000 ))
  max_k=$((ctx_size / 1000))
  if [ "$max_k" -ge 1000 ]; then max_label="$((max_k / 1000))M"
  else max_label="${max_k}k"
  fi
  pct_color "$used_pct"
  line2+="${c}${used_k}k/${max_label} (${used_pct}%)${reset}"
fi

rate_limit() {
  local pct=$1 reset_at=$2 label=$3 c cd
  [ -z "$pct" ] && return
  pct_color "$pct"
  [ -n "$line2" ] && line2+="  "
  line2+="${c}${label}:${pct}%${reset}"
  if [ "$pct" -ge 50 ] && [ -n "$reset_at" ]; then
    countdown "$reset_at"
    [ -n "$cd" ] && line2+="${c} ↻${cd}${reset}"
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
