# claude-code-statusline

Multi-line status line for [Claude Code](https://www.claude.com/product/claude-code): a per-project-colored session name read live from the iTerm2 tab title, an effort bar, and context-window + rate-limit meters.

```
Add CSV export                          # session name (iTerm2 tab title), colored per project
~/proj  main  Opus ▁▃▅▇█                # directory, git branch, model, effort bar
312k/1M (31%)  5h:24%  7d:9%            # context window usage, 5h / 7d rate limits
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/TurboKach/claude-code-statusline/main/install.sh | bash
```

The installer copies `statusline.sh` to `~/.claude/statusline-command.sh`, points `~/.claude/settings.json` at it (your other settings are preserved and a timestamped backup is saved), and checks for `jq`. No restart needed — Claude Code re-runs the status line on its next render.

### Track it with git (recommended if you want to tweak it)

```bash
git clone https://github.com/TurboKach/claude-code-statusline ~/Dev/claude-code-statusline
cd ~/Dev/claude-code-statusline && ./install.sh
```

Run from a clone, the installer **symlinks** `~/.claude/statusline-command.sh` to the repo file — so your edits are version-controlled and the live bar reflects them immediately.

## What it shows

- **Line 1 — session name.** The session's auto-generated topic, read live from the **iTerm2 tab title** and colored per project (each repo gets a stable hue). macOS + iTerm2 only; every other terminal skips this line cleanly.
- **Line 2 — context.** Working directory, git branch, model name, and an **effort bar** — one cell per reasoning level the model supports (`low · medium · high · xhigh · max` on Opus 4.8), filled up to the active level. When **ultracode** is active (xhigh effort driving a multi-agent workflow), the bar fills to the `xhigh` cell and a magenta **`↯`** icon appears right after it — your at-a-glance "ultracode is running" indicator.
- **Line 3 — budget.** Context-window usage (`used / max (pct%)`) plus 5-hour and 7-day rate-limit meters, with a countdown when you're near a cap.

## Requirements

- **[`jq`](https://jqlang.github.io/jq/)** — required (`brew install jq`). Parses the session JSON on stdin.
- **iTerm2** (macOS) — optional, only for the session-name line. Other terminals work without it.
- **git** — optional, for the branch display.

## How the session-name line works

Claude Code sets your session's auto-generated topic as the **iTerm2 tab title** (via an OSC escape sequence) but never writes it to a file. This script reads it back with AppleScript keyed on `$ITERM_SESSION_ID`, strips iTerm's status glyph and job-name suffix, caches it under `~/.claude/session-labels/`, and refreshes it in a throttled, detached background job so the bar never blocks on AppleScript. The per-project color is a stable hash (`cksum`) of the git root, or the working directory outside a repo.

## Customize

Open `statusline.sh`:

- **Colors** — edit `proj_hues=(...)`, the 8 ANSI-256 color codes used per project.
- **Refresh cadence** — the session-name refresh is throttled to 8 seconds; change the `-ge 8` threshold.

## Uninstall

Remove the `statusLine` block from `~/.claude/settings.json` (a timestamped backup sits next to it), then optionally `rm ~/.claude/statusline-command.sh`.

## License

[MIT](LICENSE)
