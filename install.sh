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

# --- dependency check: jq is required (the status line parses session JSON) ---
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required." >&2
  echo "       macOS:  brew install jq" >&2
  echo "       Debian: sudo apt-get install -y jq" >&2
  exit 1
fi

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
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  tmp="$(mktemp)"
  jq --arg cmd "$CMD" '.statusLine = {type:"command", command:$cmd}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "updated statusLine in $SETTINGS (backup saved alongside)"
else
  printf '{\n  "statusLine": { "type": "command", "command": "%s" }\n}\n' "$CMD" > "$SETTINGS"
  echo "created $SETTINGS with statusLine"
fi

echo
echo "Done. Claude Code picks up the new status line on its next render."
echo "Note: the session-name line needs iTerm2 on macOS; other terminals skip it cleanly."
