#!/usr/bin/env bash
# Claude Code statusline: session tokens · cost · context-window usage.
# Reads the statusline JSON on stdin (schema: code.claude.com/docs/en/statusline).
# The context field turns yellow and gains a 😫 once usage passes 20%.
# Decimal punctuation follows your locale (a comma-decimal locale prints "77,0K").
input=$(cat)

read -r tin tout size pct cost <<<"$(printf '%s' "$input" | jq -r '
  [ (.context_window.total_input_tokens  // 0),
    (.context_window.total_output_tokens // 0),
    (.context_window.context_window_size // 0),
    (.context_window.used_percentage     // 0),
    (.cost.total_cost_usd                // 0) ] | @tsv')"

awk -v tin="$tin" -v tout="$tout" -v size="$size" -v pct="$pct" -v cost="$cost" 'BEGIN{
  tok   = (tin + tout) / 1000
  usedk = (size * pct / 100) / 1000
  sizek = size / 1000
  y="\033[33m"; g="\033[32m"; c="\033[36m"; d="\033[2m"; r="\033[0m"
  ctx   = (pct > 20) ? y : c          # yellow once context gets heavy
  warn  = (pct > 20) ? " \360\237\230\253" : ""   # tired face 😫
  printf "%s%.1fK%s  %s$%.2f%s  %s%.0fK/%.0fK %s(%.0f%%)%s%s", \
         y, tok, r,  g, cost, r,  ctx, usedk, sizek,  d, pct, r,  warn
}'
