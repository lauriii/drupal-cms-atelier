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
# File *entities* are exported; their bytes are not. `drush content:export`
# writes the entity, so a media item added since the last run would otherwise
# reference a file the recipe does not ship and the install would abort on
# `field_media_image=This value should not be null`. The JPEGs themselves are
# checked in alongside and are left alone.

set -euo pipefail

DRUSH="${DRUSH:-drush}"
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTENT="$RECIPE_DIR/content"

# Exporting from a site that has not had this recipe applied empties the
# shipped content, because the wipe happens before the export and the export
# finds nothing. Check before destroying anything.
existing="$($DRUSH ev 'print count(\Drupal::entityTypeManager()->getStorage("canvas_page")->loadMultiple());' 2>/dev/null | tr -cd '0-9')"
if [[ "${existing:-0}" -lt 5 ]]; then
  echo "Refusing to regenerate: the site has ${existing:-0} Canvas pages, expected at least 5." >&2
  echo "Apply this recipe to the site first, then re-run." >&2
  exit 1
fi

for type in canvas_page media menu_link_content node; do
  rm -rf "${CONTENT:?}/$type"
  mkdir -p "$CONTENT/$type"
done
# Only the entity YAMLs go; the binaries beside them stay.
find "$CONTENT/file" -name '*.yml' -delete

echo "==> Exporting"
$DRUSH ev '
  $out = [];
  foreach (["canvas_page", "media", "menu_link_content", "node", "file"] as $t) {
    foreach (\Drupal::entityTypeManager()->getStorage($t)->loadMultiple() as $e) {
      $out[] = "$t:" . $e->id() . ":" . $e->uuid();
    }
  }
  print implode("\n", $out) . "\n";' \
  | grep -E '^(canvas_page|media|menu_link_content|node|file):' > /tmp/atelier-entities.txt

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
        if title in text and '\n  created:\n' not in text:
            path.write_text(text.replace('  title:\n', f"  created:\n    -\n      value: {when}\n  title:\n", 1))
            pinned += 1
            break
print(f'    pinned {pinned} of {len(dates)}')
if pinned != len(dates):
    raise SystemExit('article titles changed: update the mapping in this script')
PY

# The site carries file entities from the base recipe whose bytes this recipe
# does not ship. Exported, they make the importer log a warning and leave a
# managed row pointing at nothing, so they go here rather than being deleted by
# hand after every run.
echo "==> Dropping file entities with no binary"
python3 - "$CONTENT/file" <<'PYEOF'
import pathlib
import re
import sys

d = pathlib.Path(sys.argv[1])
shipped = {p.name for p in d.iterdir() if p.suffix != '.yml'}
dropped = []
for y in sorted(d.glob('*.yml')):
    m = re.search(r"value: '?public://([^'\n]+)'?", y.read_text())
    if not m or m.group(1) not in shipped:
        dropped.append(m.group(1) if m else y.name)
        y.unlink()
print(f"    dropped {len(dropped)}: {', '.join(dropped) if dropped else 'none'}")
PYEOF

echo "==> Done. Review the diff, then run tests/check.sh."
