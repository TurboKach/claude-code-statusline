#!/usr/bin/env bash
# Tests for hooks/session-start.sh. Temp dirs only: never touches ~/.claude.
# Run with the bash you want to test, e.g. `/bin/bash tests/session-start.test.sh`.
# Every case asserts exit 0 and the stdout contract (empty, or exactly the expected notice).

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/session-start.sh"
T=$(mktemp -d) || exit 1
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
pass=0 fail=0 skipped=0

# ---------- assertions ----------
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); printf 'FAIL [%s] %s\n' "$CASE" "$1"; }
check(){ if [ "$2" = "$3" ]; then ok; else bad "$1: expected [$2] got [$3]"; fi; }
yes()  { if "${@:2}"; then ok; else bad "$1"; fi; }
no()   { if "${@:2}"; then bad "$1"; else ok; fi; }
has()  { grep -qF -- "$2" "$1" 2>/dev/null; }
same() { cmp -s "$1" "$2"; }
nbak() { ls "$C"/settings.json.bak.* 2>/dev/null | wc -l | tr -d ' '; }

# ---------- fixtures ----------
OTHER='{
  "model": "opus",
  "env": { "A": "b" }
}'
OLD='{
  "model": "opus",
  "statusLine": { "type": "command", "command": "bash /old/path.sh" },
  "theme": "dark"
}'

# setup <case>: fresh root/data/cfg under $T
setup() {
  CASE=$1
  R="$T/$1/root"; D="$T/$1/data"; C="$T/$1/cfg"
  mkdir -p "$R" "$C"
  printf '#!/bin/sh\necho RENDERED\n' > "$R/statusline.sh"
  RV=$R DV=$D CV=$C OPT="" RUN_PATH=$PATH DELAY=0   # DELAY: the hook's test-only write delay, 0 = no sleep
  mkdir -p "$T/home"
}
put() { printf '%s\n' "$2" > "$1"; }

# run [source]: runs the hook with the case's env; sets OUT and RC.
# Empty RV/DV/OPT mean "unset". Empty source = no stdin JSON at all.
run() {
  local s=${1-startup} args=() input=""
  [ -n "$s" ] && input=$(printf '{"hook_event_name":"SessionStart","source":"%s"}' "$s")
  args+=(-u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_OPTION_REPLACE_EXISTING)
  args+=(HOME="$T/home" PATH="$RUN_PATH" CLAUDE_CONFIG_DIR="$CV" BASH_STATUSLINE_TEST_DELAY="$DELAY")
  [ -n "$RV" ] && args+=(CLAUDE_PLUGIN_ROOT="$RV")
  [ -n "$DV" ] && args+=(CLAUDE_PLUGIN_DATA="$DV")
  [ -n "$OPT" ] && args+=(CLAUDE_PLUGIN_OPTION_REPLACE_EXISTING="$OPT")
  OUT=$(printf '%s' "$input" | env "${args[@]}" "$BASH" "$HOOK" 2>/dev/null); RC=$?
  check "exit code" 0 "$RC"
}

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
exp_json() { printf '{"systemMessage":"%s"}' "$(jesc "bash-statusline: not set up, $1.")"; }
msg_existing() { exp_json "a status line is already set in $1 and was left alone. To use this one, turn on 'Replace an existing status line' in /plugin -> Installed -> bash-statusline -> Configure options, then start a new session"; }
msg_unmatched() { exp_json "the statusLine in $1 cannot be replaced automatically. Add the block by hand, see the README"; }
msg_notobject() { exp_json "$1 is not a JSON object. Fix it or add the block by hand, see the README"; }
msg_writefail() { exp_json "could not write $1. Add the block by hand, see the README"; }
silent() { check "stdout empty" "" "$OUT"; }
notice() { check "stdout is the notice" "$1" "$OUT"; }

# ---------- cases ----------
setup missing_settings
run; silent
yes "settings created" test -f "$C/settings.json"
yes "entry has our command" has "$C/settings.json" "\"command\": \"bash '$D/statusline.sh'\""
yes "refreshInterval" has "$C/settings.json" '"refreshInterval": 60'
check "link target" "$R/statusline.sh" "$(readlink "$D/statusline.sh")"
check "no backup (nothing to back up)" 0 "$(nbak)"
check "rendered through link" RENDERED "$(sh -c "bash '$D/statusline.sh'")"

setup empty_object
put "$C/settings.json" '{}'
run; silent
yes "entry added" has "$C/settings.json" '"statusLine"'
check "one backup" 1 "$(nbak)"
setup empty_file
: > "$C/settings.json"
run; silent
yes "entry added to empty file" has "$C/settings.json" '"statusLine"'

setup other_keys
put "$C/settings.json" "$OTHER"
run; silent
yes "entry added" has "$C/settings.json" "\"command\": \"bash '$D/statusline.sh'\""
yes "model kept" has "$C/settings.json" '"model": "opus"'
yes "env kept" has "$C/settings.json" '"env": { "A": "b" }'
check "one backup" 1 "$(nbak)"
put "$T/$CASE/orig" "$OTHER"
yes "backup equals original" same "$(ls "$C"/settings.json.bak.*)" "$T/$CASE/orig"
cp "$C/settings.json" "$T/$CASE/after"
run; silent
yes "second run: no write" same "$C/settings.json" "$T/$CASE/after"
check "second run: no new backup" 1 "$(nbak)"

setup existing_option_off
put "$C/settings.json" "$OLD"; cp "$C/settings.json" "$T/$CASE/orig"
run; notice "$(msg_existing "$C/settings.json")"
yes "unchanged byte-for-byte" same "$C/settings.json" "$T/$CASE/orig"
check "no backup" 0 "$(nbak)"
yes "no replaced marker" test ! -e "$D/.statusline-replaced"
run; silent
yes "second run unchanged" same "$C/settings.json" "$T/$CASE/orig"

setup existing_option_on
put "$C/settings.json" "$OLD"; cp "$C/settings.json" "$T/$CASE/orig"
OPT=true; run; silent
yes "old command gone" test "$(grep -c '/old/path.sh' "$C/settings.json")" = 0
yes "our command in" has "$C/settings.json" "\"command\": \"bash '$D/statusline.sh'\""
yes "model kept" has "$C/settings.json" '"model": "opus"'
yes "theme kept" has "$C/settings.json" '"theme": "dark"'
check "one backup" 1 "$(nbak)"
yes "backup equals original" same "$(ls "$C"/settings.json.bak.*)" "$T/$CASE/orig"
yes "replaced marker" test -e "$D/.statusline-replaced"
cp "$C/settings.json" "$T/$CASE/after"
run; silent
yes "second run: no write" same "$C/settings.json" "$T/$CASE/after"
check "second run: no new backup" 1 "$(nbak)"

for v in true TRUE True 1; do
  setup "option_on_$(printf %s "$v" | od -An -tx1 | tr -d " \n")"
  put "$C/settings.json" "$OLD"
  OPT=$v; run; silent
  yes "option '$v' replaces" has "$C/settings.json" "bash '$D/statusline.sh'"
done
for v in false 0 yes on ""; do
  setup "option_off_$(printf %s "x$v" | od -An -tx1 | tr -d " \n")"
  put "$C/settings.json" "$OLD"; cp "$C/settings.json" "$T/$CASE/orig"
  OPT=$v; run; notice "$(msg_existing "$C/settings.json")"
  yes "option '${v:-unset}' leaves alone" same "$C/settings.json" "$T/$CASE/orig"
done

setup already_ours
put "$C/settings.json" "{ \"statusLine\": { \"type\": \"command\", \"command\": \"bash '$D/statusline.sh'\", \"refreshInterval\": 60 } }"
cp "$C/settings.json" "$T/$CASE/orig"
run; silent
yes "no write" same "$C/settings.json" "$T/$CASE/orig"
check "no backup" 0 "$(nbak)"
OPT=true; run; silent
yes "still no write with option on" same "$C/settings.json" "$T/$CASE/orig"

setup option_on_after_notice
put "$C/settings.json" "$OLD"; cp "$C/settings.json" "$T/$CASE/orig"
run; notice "$(msg_existing "$C/settings.json")"
OPT=1; run; silent
yes "replaced at next run" has "$C/settings.json" "bash '$D/statusline.sh'"
check "one backup" 1 "$(nbak)"

# replace happens once per install; a different bar set later is left alone, no notice
setup replace_once_then_left_alone
put "$C/settings.json" "$OLD"
OPT=true; run; silent
yes "first replace done" has "$C/settings.json" "bash '$D/statusline.sh'"
yes "replaced marker" test -e "$D/.statusline-replaced"
put "$C/settings.json" "$OLD"; cp "$C/settings.json" "$T/$CASE/orig"
run; silent
yes "later different bar not replaced" same "$C/settings.json" "$T/$CASE/orig"
run resume; silent
yes "no notice marker" test -z "$(ls -A "$D" | grep notice)"
OPT=false; run; notice "$(msg_existing "$C/settings.json")"
yes "option off: still unchanged, one notice" same "$C/settings.json" "$T/$CASE/orig"

setup unmatched_option_on
put "$C/settings.json" '{ "statusLine": "bash /x.sh", "model": "opus" }'; cp "$C/settings.json" "$T/$CASE/orig"
OPT=true; run; notice "$(msg_unmatched "$C/settings.json")"
yes "unchanged" same "$C/settings.json" "$T/$CASE/orig"
check "no backup" 0 "$(nbak)"
run; silent

setup nested_option_off
put "$C/settings.json" '{ "profiles": { "a": { "statusLine": { "type": "command", "command": "x" } } } }'; cp "$C/settings.json" "$T/$CASE/orig"
run; notice "$(msg_existing "$C/settings.json")"
yes "unchanged" same "$C/settings.json" "$T/$CASE/orig"

setup not_object
put "$C/settings.json" '[1, 2]'; cp "$C/settings.json" "$T/$CASE/orig"
run; notice "$(msg_notobject "$C/settings.json")"
yes "unchanged" same "$C/settings.json" "$T/$CASE/orig"
check "no backup" 0 "$(nbak)"
run; silent

setup source_clear
put "$C/settings.json" "$OLD"
run clear; silent
yes "no notice marker after clear" test -z "$(ls -A "$D" | grep notice)"
run compact; silent
run ""; silent
yes "no notice marker without source" test -z "$(ls -A "$D" | grep notice)"
run resume; notice "$(msg_existing "$C/settings.json")"
run startup; silent

setup symlinked_settings
mkdir -p "$T/$CASE/real"
put "$T/$CASE/real/settings.json" "$OTHER"
ln -s "$T/$CASE/real/settings.json" "$C/settings.json"
run; silent
yes "link kept" test -L "$C/settings.json"
check "link target same" "$T/$CASE/real/settings.json" "$(readlink "$C/settings.json")"
yes "target updated" has "$T/$CASE/real/settings.json" "bash '$D/statusline.sh'"
yes "target keeps keys" has "$T/$CASE/real/settings.json" '"model": "opus"'
setup symlinked_relative
mkdir -p "$C/sub"
put "$C/sub/real.json" "$OTHER"
ln -s sub/real.json "$C/settings.json"
run; silent
yes "relative link kept" test -L "$C/settings.json"
yes "relative target updated" has "$C/sub/real.json" "bash '$D/statusline.sh'"

setup readonly_dir
put "$C/settings.json" "$OTHER"; cp "$C/settings.json" "$T/$CASE/orig"
if [ "$(id -u)" = 0 ]; then
  skipped=$((skipped + 1)); echo "SKIP [$CASE] running as root"
else
  chmod 555 "$C"
  run; notice "$(msg_writefail "$C/settings.json")"
  chmod 755 "$C"
  yes "unchanged" same "$C/settings.json" "$T/$CASE/orig"
  check "no backup" 0 "$(nbak)"
fi

setup mv_fails
put "$C/settings.json" "$OTHER"; cp "$C/settings.json" "$T/$CASE/orig"
mkdir -p "$T/$CASE/shim" "$D"
printf '#!/bin/sh\nexit 1\n' > "$T/$CASE/shim/mv"; chmod +x "$T/$CASE/shim/mv"
ln -s "$R/statusline.sh" "$D/statusline.sh"
RUN_PATH="$T/$CASE/shim:$PATH"
run; notice "$(msg_writefail "$C/settings.json")"
yes "unchanged" same "$C/settings.json" "$T/$CASE/orig"
check "failed write leaves no backup" 0 "$(nbak)"
check "failed write leaves no temp file" 0 "$(ls -A "$C" | grep -c '^\.settings\.')"
run; silent

# a missing statusLine is added back in every session (user removal, or Claude Code
# rewriting settings.json from its in-memory copy)
setup removed_by_user
put "$C/settings.json" "$OTHER"
run; silent
put "$C/settings.json" "$OTHER"
run; silent
yes "re-added after the user removed it" has "$C/settings.json" "\"command\": \"bash '$D/statusline.sh'\""
yes "model kept" has "$C/settings.json" '"model": "opus"'
setup clobbered_by_claude
put "$C/settings.json" "$OTHER"
run; silent
put "$C/settings.json" '{
  "model": "opus",
  "effortLevel": "high"
}'
run; silent
yes "re-added after a clobber" has "$C/settings.json" "\"command\": \"bash '$D/statusline.sh'\""
yes "clobbering write's key kept" has "$C/settings.json" '"effortLevel": "high"'
cp "$C/settings.json" "$T/$CASE/after"
run; silent
yes "present again: no write" same "$C/settings.json" "$T/$CASE/after"

setup root_moved
put "$C/settings.json" "$OTHER"
run; silent
R2="$T/$CASE/root2"; mkdir -p "$R2"; cp "$R/statusline.sh" "$R2/statusline.sh"
RV=$R2; run; silent
check "link re-pointed" "$R2/statusline.sh" "$(readlink "$D/statusline.sh")"
check "no stray temp links" 0 "$(ls -A "$D" | grep -c '^\.statusline\.sh\.')"

setup orphaned_root
touch "$R/.orphaned_at"
run; silent
yes "no data dir created" test ! -e "$D"
yes "no settings written" test ! -e "$C/settings.json"
mkdir -p "$D" "$T/$CASE/other"; ln -s "$T/$CASE/other/statusline.sh" "$D/statusline.sh"
put "$C/settings.json" "$OTHER"; cp "$C/settings.json" "$T/$CASE/orig"
run; silent
check "link unchanged" "$T/$CASE/other/statusline.sh" "$(readlink "$D/statusline.sh")"
yes "settings unchanged" same "$C/settings.json" "$T/$CASE/orig"

setup unset_env
put "$C/settings.json" "$OTHER"; cp "$C/settings.json" "$T/$CASE/orig"
RV=""; run; silent
yes "root unset: no data dir" test ! -e "$D"
yes "root unset: settings unchanged" same "$C/settings.json" "$T/$CASE/orig"
RV=$R DV=""; run; silent
yes "data unset: settings unchanged" same "$C/settings.json" "$T/$CASE/orig"

setup weird_paths
D="$T/$CASE/da & ta's \"q\" \\b"; C="$T/$CASE/c fg's \"q\" \\z"
mkdir -p "$C"; CV=$C DV=$D
put "$C/settings.json" "$OLD"
run; notice "$(msg_existing "$C/settings.json")"
OPT=true; run; silent
cmd=$(sed -n 's/.*"command": "\(.*\)", "refreshInterval".*/\1/p' "$C/settings.json")
cmd=${cmd//\\\"/\"}; cmd=${cmd//\\\\/\\}
sq="'" esc="'\\''"; dq=${D//$sq/$esc}
check "command text" "bash '$dq/statusline.sh'" "$cmd"
check "command runs via sh -c" RENDERED "$(sh -c "$cmd")"

# ---------- statusLine as an object key only; "ours" scoped to the block ----------
MULTI='{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "echo other-bar"
  },
  "theme": "dark"
}'
jvalid() { python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null; }
jmsg_ok() { jmsg "$1" >/dev/null; }
jmsg() { python3 -I -c 'import json,sys; sys.stdout.write(json.loads(sys.argv[1])["systemMessage"])' "$1" 2>/dev/null; }

setup value_not_key
put "$C/settings.json" '{ "env": {"X":"statusLine"}, "permissions": { "allow": ["Bash(statusLine)", "statusLine"] }, "model": "opus" }'
run; silent
yes "added although the text appears as a value" has "$C/settings.json" "\"command\": \"bash '$D/statusline.sh'\""
yes "env kept" has "$C/settings.json" '"env": {"X":"statusLine"}'
yes "model kept" has "$C/settings.json" '"model": "opus"'
check "one backup" 1 "$(nbak)"
setup value_not_key_spaced_key
put "$C/settings.json" '{ "env": {"X":"statusLine"}, "statusLine" : { "type": "command", "command": "x" } }'; cp "$C/settings.json" "$T/$CASE/orig"
run; notice "$(msg_existing "$C/settings.json")"
yes "spaced key still counts as existing" same "$C/settings.json" "$T/$CASE/orig"

setup ours_only_in_env
put "$C/settings.json" "{ \"env\": { \"X\": \"bash '$D/statusline.sh'\" }, \"model\": \"opus\" }"
run; silent
yes "entry added" has "$C/settings.json" "\"command\": \"bash '$D/statusline.sh'\", \"refreshInterval\""
yes "env kept" has "$C/settings.json" '"model": "opus"'
check "one backup" 1 "$(nbak)"
setup ours_in_env_other_bar
put "$C/settings.json" "{ \"env\": { \"X\": \"bash '$D/statusline.sh'\" }, \"statusLine\": { \"type\": \"command\", \"command\": \"echo other-bar\" } }"; cp "$C/settings.json" "$T/$CASE/orig"
run; notice "$(msg_existing "$C/settings.json")"
yes "unchanged" same "$C/settings.json" "$T/$CASE/orig"
yes "no marker" test ! -e "$D/.statusline-replaced"
OPT=true; run; silent
yes "replaced with option on" has "$C/settings.json" "\"command\": \"bash '$D/statusline.sh'\", \"refreshInterval\""
yes "other bar gone" test "$(grep -c 'echo other-bar' "$C/settings.json")" = 0
yes "env kept" has "$C/settings.json" '"env": {'
setup ours_in_other_field
put "$C/settings.json" "{ \"statusLine\": { \"type\": \"command\", \"command\": \"echo x\", \"padding\": \"bash '$D/statusline.sh'\" } }"; cp "$C/settings.json" "$T/$CASE/orig"
run; notice "$(msg_existing "$C/settings.json")"
yes "unchanged: our text outside the command value is not ours" same "$C/settings.json" "$T/$CASE/orig"
yes "no marker" test ! -e "$D/.statusline-replaced"

# ---------- multi-line (pretty-printed) settings, as Claude Code rewrites them ----------
setup multiline_option_on
put "$C/settings.json" "$MULTI"; cp "$C/settings.json" "$T/$CASE/orig"
OPT=true; run; silent
yes "other bar gone" test "$(grep -c 'echo other-bar' "$C/settings.json")" = 0
yes "our command in" has "$C/settings.json" "\"command\": \"bash '$D/statusline.sh'\""
yes "model kept" has "$C/settings.json" '"model": "opus"'
yes "theme kept" has "$C/settings.json" '"theme": "dark"'
check "one backup" 1 "$(nbak)"
yes "backup equals original" same "$(ls "$C"/settings.json.bak.*)" "$T/$CASE/orig"
yes "replaced marker" test -e "$D/.statusline-replaced"
setup multiline_option_off
put "$C/settings.json" "$MULTI"; cp "$C/settings.json" "$T/$CASE/orig"
run; notice "$(msg_existing "$C/settings.json")"
yes "unchanged byte-for-byte" same "$C/settings.json" "$T/$CASE/orig"
check "no backup" 0 "$(nbak)"
yes "no marker" test ! -e "$D/.statusline-replaced"
setup multiline_already_ours
put "$C/settings.json" "{
  \"model\": \"opus\",
  \"statusLine\": {
    \"type\": \"command\",
    \"command\": \"bash '$D/statusline.sh'\",
    \"refreshInterval\": 60
  }
}"; cp "$C/settings.json" "$T/$CASE/orig"
run; silent
yes "no write" same "$C/settings.json" "$T/$CASE/orig"
check "no backup" 0 "$(nbak)"
OPT=true; run; silent
yes "still no write with option on" same "$C/settings.json" "$T/$CASE/orig"

# ---------- control characters in paths never produce invalid JSON ----------
setup control_chars_data
D="$T/$CASE/da"$'\t'"ta"$'\n'"x"$'\001'"y"; DV=$D
put "$C/settings.json" "$OTHER"
run; silent
yes "settings.json is valid JSON" jvalid "$C/settings.json"
cmd=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["statusLine"]["command"], end="")' "$C/settings.json" 2>/dev/null)
check "command decodes to the real path" "bash '$D/statusline.sh'" "$cmd"
check "command runs via sh -c" RENDERED "$(sh -c "$cmd")"
setup control_chars_cfg_notice
C="$T/$CASE/c"$'\t'"fg"$'\r'"x"$'\037'; CV=$C; mkdir -p "$C"
put "$C/settings.json" "$OLD"
run
yes "notice is valid JSON" jmsg_ok "$OUT"
check "notice text decodes to the real path" "bash-statusline: not set up, a status line is already set in $C/settings.json and was left alone. To use this one, turn on 'Replace an existing status line' in /plugin -> Installed -> bash-statusline -> Configure options, then start a new session." "$(jmsg "$OUT")"
case $OUT in *$'\t'*|*$'\r'*|*$'\037'*) bad "raw control character in the notice" ;; *) ok ;; esac

# ---------- delay: the write lands after Claude Code's settings watcher starts ----------
now() { python3 -I -c 'import time; print(time.time())'; }
# hook <outfile>: run the hook with the case's env and a stdin source; prints nothing itself
hook_bg() {
  printf '{"hook_event_name":"SessionStart","source":"startup"}' | env -u CLAUDE_PLUGIN_OPTION_REPLACE_EXISTING \
    HOME="$T/home" PATH="$RUN_PATH" CLAUDE_CONFIG_DIR="$CV" CLAUDE_PLUGIN_ROOT="$RV" CLAUDE_PLUGIN_DATA="$DV" \
    BASH_STATUSLINE_TEST_DELAY="$DELAY" ${OPT:+CLAUDE_PLUGIN_OPTION_REPLACE_EXISTING="$OPT"} "$BASH" "$HOOK" > "$1" 2>/dev/null
}

setup delay_write_path
put "$C/settings.json" "$OTHER"
DELAY=1; t0=$(now); run; silent; t1=$(now)
yes "write path takes at least the delay" python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[2]) - float(sys.argv[1]) >= 0.95 else 1)' "$t0" "$t1"
yes "block written" has "$C/settings.json" "bash '$D/statusline.sh'"

setup delay_no_write_path
put "$C/settings.json" "{ \"statusLine\": { \"type\": \"command\", \"command\": \"bash '$D/statusline.sh'\", \"refreshInterval\": 60 } }"
DELAY=3; t0=$(now); run; silent; t1=$(now)
yes "already ours: no sleep" python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[2]) - float(sys.argv[1]) < 1.5 else 1)' "$t0" "$t1"
setup delay_notice_path
put "$C/settings.json" "$OLD"
DELAY=3; t0=$(now); run; notice "$(msg_existing "$C/settings.json")"; t1=$(now)
yes "existing bar, option off: no sleep" python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[2]) - float(sys.argv[1]) < 1.5 else 1)' "$t0" "$t1"

# the decision and the write use a read taken after the delay
setup fresh_read_keeps_change
put "$C/settings.json" "$OTHER"
DELAY=1
hook_bg "$T/$CASE/out" & hp=$!
sleep 0.4
put "$C/settings.json" '{
  "model": "opus",
  "theme": "light"
}'
wait $hp
yes "change made during the delay survives" has "$C/settings.json" '"theme": "light"'
yes "block added" has "$C/settings.json" "bash '$D/statusline.sh'"
check "stdout empty" "" "$(cat "$T/$CASE/out")"
setup fresh_read_user_adds_bar
put "$C/settings.json" "$OTHER"
DELAY=1
hook_bg "$T/$CASE/out" & hp=$!
sleep 0.4
put "$C/settings.json" "$OLD"; cp "$C/settings.json" "$T/$CASE/orig"
wait $hp
yes "bar set during the delay is left alone (option off)" same "$C/settings.json" "$T/$CASE/orig"
check "notice from the fresh read" "$(msg_existing "$C/settings.json")" "$(cat "$T/$CASE/out")"
check "no backup" 0 "$(nbak)"
setup fresh_read_ours_appears
put "$C/settings.json" "$OTHER"
DELAY=1
hook_bg "$T/$CASE/out" & hp=$!
sleep 0.4
put "$C/settings.json" "{ \"statusLine\": { \"type\": \"command\", \"command\": \"bash '$D/statusline.sh'\", \"refreshInterval\": 60 } }"; cp "$C/settings.json" "$T/$CASE/orig"
wait $hp
yes "already there after the delay: no write" same "$C/settings.json" "$T/$CASE/orig"
check "no backup" 0 "$(nbak)"

echo
echo "executed=$((pass + fail)) passed=$pass failed=$fail skipped=$skipped"
[ "$fail" -eq 0 ]
