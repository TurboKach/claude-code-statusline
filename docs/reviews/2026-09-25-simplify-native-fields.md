# Codex challenge verdict — simplify-native-fields

Range `9e780b8..4e2fdd8`, final round (codex gpt-6-astra/medium, exit 0). Triaged against `git show 4e2fdd8:statusline.sh`.

Verdict: **0 P0, 0 P1, 3 P2** — none reachable with a real Claude Code payload.

## finding-1

[P2 conf:0.7] `statusline.sh:145` — a token count or `context_window_size` of `1e30` survives `numbers | floor` as jq's `1e+30`; bash `$(( ))` then fails with a syntax error and the context meter is dropped (exit 0, no crash). Needs an absurd value Claude Code never sends.

## finding-2

[P2 conf:0.6] `statusline.sh:145` — `total_input_tokens` of 2^63 overflows bash's signed 64-bit arithmetic and renders a negative `used_k` (e.g. `-9223372036854775k/200k`). Same pathological-input caveat.

## finding-3

[P2 conf:0.5] `statusline.sh:45` — jq aborts a JSON stream at the first unparsable line, so a corrupted transcript line that contains the `/effort` needle would hide any later `/effort` change from the ultracode check. Only reachable with a corrupted transcript. Likely fix: `jq -R 'fromjson? | …'` to skip bad lines.

## Accepted, not tracked

- Control-char stripping alters a cwd that genuinely contains a tab; `git -C` then fails harmlessly.
- The ultracode check greps the whole transcript on each xhigh render — deliberate (~8 ms on 33 MB, never misses an old `/effort`).
- Pasting the literal `<local-command-stdout>Set effort level to ultracode` text into your own chat message can spoof the badge — cosmetic, self-inflicted, same as before the branch.
- Percentages round half-up in jq (was half-even via `printf '%.0f'`).
