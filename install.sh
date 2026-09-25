#!/usr/bin/env bash
# Installer for claude-code-statusline.
#
# Dual-mode (auto-detected):
#   - via `curl ... | bash`  -> downloads statusline.sh into ~/.claude (a copy)
#   - run from a git clone   -> symlinks ~/.claude/statusline-command.sh to the
#                               repo file, so the repo stays the source of truth
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/TurboKach/claude-code-statusline/main/statusline.sh"
CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/statusline-command.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# --- place the script ---
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/statusline.sh" ] && [ -f "$SRC_DIR/install.sh" ]; then
  # running from a clone: symlink so the repo stays the source of truth
  if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
    cp "$DEST" "$DEST.bak.$(date +%s)"; echo "backed up existing script -> $DEST.bak.*"
  fi
  ln -sf "$SRC_DIR/statusline.sh" "$DEST"
  echo "symlinked $DEST -> $SRC_DIR/statusline.sh"
else
  # running via curl|bash: download a copy
  [ -e "$DEST" ] && { cp "$DEST" "$DEST.bak.$(date +%s)"; echo "backed up existing script -> $DEST.bak.*"; }
  curl -fsSL "$REPO_RAW" -o "$DEST"
  echo "installed $DEST"
fi
chmod +x "$DEST"

# --- point settings.json at it (preserve other settings, back up first) ---
CMD="bash $DEST"
entry="\"statusLine\": { \"type\": \"command\", \"command\": \"$CMD\" }"
if [ -f "$SETTINGS" ]; then
  # A plain-text edit, no jq: statusLine is a flat object, so the regex spans all of it.
  # Anything else is inserted as the first key.
  json=$(<"$SETTINGS")
  re='"statusLine"[[:space:]]*:[[:space:]]*\{[^{}]*\}'
  if [[ $json =~ $re ]]; then json=${json/"${BASH_REMATCH[0]}"/"$entry"}
  elif [[ $json == *'"statusLine"'* ]]; then
    echo "error: can't safely edit statusLine in $SETTINGS; set it by hand to:" >&2
    echo "       $entry" >&2
    exit 1
  elif [[ $json =~ ^[[:space:]]*(\{[[:space:]]*\})?[[:space:]]*$ ]]; then json="{ $entry }"
  else json=${json/\{/"{
  $entry,"}
  fi
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  tmp="$(mktemp)"
  printf '%s\n' "$json" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "updated statusLine in $SETTINGS (backup saved alongside)"
else
  printf '{\n  "statusLine": { "type": "command", "command": "%s" }\n}\n' "$CMD" > "$SETTINGS"
  echo "created $SETTINGS with statusLine"
fi

echo
echo "Done. Claude Code picks up the new status line on its next render."
