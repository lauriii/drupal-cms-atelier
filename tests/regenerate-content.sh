#!/usr/bin/env bash
#
# Re-exports the shipped content from a site you have built by hand, into
# `content/`. Companion to regenerate-components.sh, which does the same for the
# code components.
#
# Usage:
#   tests/regenerate-content.sh
#   DRUSH="ddev drush" tests/regenerate-content.sh
#
# Binary files are not re-exported: `drush content:export` writes the file
# entity, not the bytes. The JPEGs in content/file/ are checked in and stay put.

set -euo pipefail

DRUSH="${DRUSH:-drush}"
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTENT="$RECIPE_DIR/content"

for type in canvas_page media menu_link_content node; do
  rm -rf "${CONTENT:?}/$type"
  mkdir -p "$CONTENT/$type"
done

echo "==> Exporting"
$DRUSH ev '
  $out = [];
  foreach (["canvas_page", "media", "menu_link_content", "node"] as $t) {
    foreach (\Drupal::entityTypeManager()->getStorage($t)->loadMultiple() as $e) {
      $out[] = "$t:" . $e->id() . ":" . $e->uuid();
    }
  }
  print implode("\n", $out) . "\n";' \
  | grep -E '^(canvas_page|media|menu_link_content|node):' > /tmp/atelier-entities.txt

count=0
while IFS=: read -r type id uuid; do
  $DRUSH content:export "$type" "$id" < /dev/null > "$CONTENT/$type/$uuid.yml" 2>/dev/null
  count=$((count + 1))
done < /tmp/atelier-entities.txt
echo "    exported $count entities"

# `drush content:export` omits `created`, so every article would import on the
# install timestamp and the journal would read as three posts filed on the same
# afternoon. Pin them back, keyed by title so the mapping survives a re-export
# under new UUIDs. Values are Unix timestamps: the field rejects ISO strings.
echo "==> Pinning article dates"
python3 - "$CONTENT" <<'PY'
import pathlib
import sys

dates = {
    'Notes from the bench: joinery without fixings': 1784646300,
    'Sourcing ash from a single Hampshire woodland': 1782290400,
    'What we learned making two hundred of the same stool': 1779181920,
}
pinned = 0
for path in (pathlib.Path(sys.argv[1]) / 'node').glob('*.yml'):
    text = path.read_text()
    for title, when in dates.items():
        if title in text and 'created:' not in text:
            path.write_text(text.replace('  title:\n', f"  created:\n    -\n      value: {when}\n  title:\n", 1))
            pinned += 1
            break
print(f'    pinned {pinned} of {len(dates)}')
if pinned != len(dates):
    raise SystemExit('article titles changed: update the mapping in this script')
PY

echo "==> Done. Review the diff, then run tests/check.sh."
