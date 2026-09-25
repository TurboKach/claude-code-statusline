# TODOS

## P2

- **[P2 conf:0.7] statusline.sh:145** — absurd token count (`1e30`) prints as `1e+30` and drops the context meter → docs/reviews/2026-09-25-simplify-native-fields.md #finding-1
- **[P2 conf:0.6] statusline.sh:145** — token count ≥ 2^63 wraps bash arithmetic to a negative `used_k` → docs/reviews/2026-09-25-simplify-native-fields.md #finding-2
- **[P2 conf:0.5] statusline.sh:45** — a corrupted transcript line stops jq, hiding later `/effort` changes → docs/reviews/2026-09-25-simplify-native-fields.md #finding-3
