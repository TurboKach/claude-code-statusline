# claude-code-statusline

Multi-line status line for [Claude Code](https://www.claude.com/product/claude-code): a per-project-colored session name, an effort bar, and context-window + rate-limit meters.

```
Add CSV export                          # session name, colored per project
~/proj  main  Opus ▁▃▅▇█                # directory, git branch, model, effort bar
312k/1M (31%)  5h:24%  7d:9%            # context window usage, 5h / 7d rate limits
```

## Install

Clone it wherever you keep your repos, then run the installer:

```bash
git clone https://github.com/TurboKach/claude-code-statusline.git
cd claude-code-statusline
./install.sh
```

The installer finds its own location (no fixed directory required) and **symlinks** `~/.claude/statusline-command.sh` to the cloned `statusline.sh` — so the repo is the source of truth, your edits are version-controlled, and the live bar reflects them on its next render. It also points `~/.claude/settings.json` at the script (your other settings preserved, with a timestamped backup) and checks for `jq`. No restart needed.

Keep the clone around — the install is a symlink to it. Update later with `git pull` in the clone.

## What it shows

- **Line 1 — session name.** Your `/rename` name, or else Claude's auto-generated session title, colored per project (each launch directory gets a stable hue). Hidden until the session has a name.
- **Line 2 — context.** Working directory, git branch, model name, and an **effort bar** — one cell per reasoning level the model supports (`low · medium · high · xhigh · max` on Opus 4.8), filled up to the active level. When **ultracode** is active (xhigh effort driving a multi-agent workflow), the bar fills to the `xhigh` cell and a magenta **`↯`** icon appears right after it — your at-a-glance "ultracode is running" indicator.
- **Line 3 — budget.** Context-window usage (`used / max (pct%)`) plus 5-hour and 7-day rate-limit meters, with a countdown when you're near a cap.

## Requirements

- **[`jq`](https://jqlang.github.io/jq/)** — required (`brew install jq`). Parses the session JSON on stdin.
- **git** — optional, for the branch display.

## Customize

Open `statusline.sh`:

- **Colors** — edit `proj_hues=(...)`, the 8 ANSI-256 color codes used per project.

## Uninstall

Remove the `statusLine` block from `~/.claude/settings.json` (a timestamped backup sits next to it), then optionally `rm ~/.claude/statusline-command.sh`.

## License

[MIT](LICENSE)
