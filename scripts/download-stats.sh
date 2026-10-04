#!/usr/bin/env bash
# Show download counts per release and platform for m-tky/koreader-tategumi.

set -euo pipefail

REPO="m-tky/koreader-tategumi"

# A bot that scrapes every asset once inflates the total by N-1 per release
# (where N = number of assets). Detect this signature — min(asset counts) >= 1
# across a "full" release (>= 10 assets) — and collapse the bot's per-asset
# floor into a single download in the total.
BOT_DETECT_MIN_ASSETS=10

ADJUST_TOTAL_JQ="
  def adjust_total:
    (.assets | length) as \$n |
    (.assets | map(.download_count) | min // 0) as \$m |
    (.assets | map(.download_count) | add // 0) as \$sum |
    if \$n >= ${BOT_DETECT_MIN_ASSETS} and \$m >= 1
    then { total: (\$sum - \$m * \$n + 1), bot_floor: \$m, n: \$n, raw: \$sum }
    else { total: \$sum, bot_floor: 0, n: \$n, raw: \$sum }
    end;
"

gh api "repos/${REPO}/releases" --jq "
  ${ADJUST_TOTAL_JQ}
  .[] |
  . as \$rel |
  (\$rel | adjust_total) as \$a |
  \"=== \(\$rel.tag_name) (\(\$rel.published_at[:10])) — total: \(\$a.total)\" +
    (if \$a.bot_floor > 0
     then \" (raw: \(\$a.raw), bot floor: \(\$a.bot_floor) × \(\$a.n) assets collapsed to 1)\"
     else \"\" end) + \" ===\",
  (
    \$rel.assets[]
    | select(.download_count > 0)
    | select(.name | test(\"-latest-stable\\\\.zsync$\") | not)
    | select(.name | test(\"-latest-stable$\") | not)
    | \"  \(.name): \(.download_count)\"
  )
" | grep -v '^$'

echo ""
echo "Grand total: $(gh api "repos/${REPO}/releases" --jq "
  ${ADJUST_TOTAL_JQ}
  [.[] | adjust_total.total] | add
") downloads"
