#!/usr/bin/env bash
#
# Maintainer tool, not a test.
#
# Refreshes the vendored snapshot of the Atelier code components from a site
# that has had `canvas push` run against it. Run this whenever the paired
# paired codebase changes.
#
#   1. Install this template on a disposable site.
#   2. Finish the OAuth setup (see README.md).
#   3. From your codebase: `npx canvas push`.
#   4. tests/regenerate-components.sh
#
# Usage:
#   tests/regenerate-components.sh                    # uses `drush`
#   DRUSH="ddev drush" tests/regenerate-components.sh # inside DDEV
#
# Set these so the snapshot records what it is a snapshot of. Without them the
# 21 vendored components cannot be diffed against the codebase they came from,
# which is the whole maintenance story for this template:
#   ATELIER_UPSTREAM           the paired codebase's repository URL
#   ATELIER_UPSTREAM_REVISION  the commit you pushed from
#   ATELIER_CANVAS_CLI         `npx canvas --version` on that codebase
#
# It writes:
#   config/canvas.js_component.*.yml   one per component
#   config/canvas.component.js.*.yml   the Canvas wrapper for each, which pins
#                                      the `component_version` that page regions
#                                      and pages reference
#   config/canvas.page_region.*.yml    the header/footer trees
#   recipe.yml                         the global CSS, spliced between markers
#   composer.json                      extra.atelier.snapshot, the provenance
#
# The global CSS cannot be a plain config file. `canvas.asset_library.global`
# already exists by the time this recipe's config is imported — the base recipe
# creates it when it installs Canvas — and a recipe only imports config that
# does not exist yet unless it is in strict mode. So it is applied as a
# `setProperties` config action instead.
# @see \Drupal\Core\Recipe\ConfigConfigurator::getConfigStorage()

set -euo pipefail

DRUSH="${DRUSH:-drush}"
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$RECIPE_DIR/config"

# Nothing is written into the repository until a complete export has arrived
# here, so an export that dies halfway leaves the snapshot alone.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# Exporting from a site that is broken or half-installed writes the emptiness
# over the vendored snapshot: this script deletes all 21 component files and
# both page regions before it re-exports them, so an empty site silently
# becomes an empty recipe. That happened -- a failed install left no page
# regions, this ran against it, and the header and footer configs were lost.
# `regenerate-content.sh` has had a guard since a similar loss; this did not.
#
# The floor was a constant, and it was set to 15 while 21 components shipped --
# so a site left half-populated by an interrupted push cleared the guard, and
# the `rm -f` below then replaced 21 files with 16. Count what is on disk
# instead: the only legitimate way to ship fewer is to delete some on purpose,
# and that shows up in the diff.
shipped_components="$(ls "$CONFIG_DIR"/canvas.js_component.*.yml 2>/dev/null | wc -l | tr -d ' ')"
shipped_regions="$(ls "$CONFIG_DIR"/canvas.page_region.*.yml 2>/dev/null | wc -l | tr -d ' ')"
components="$($DRUSH ev 'print count(\Drupal::entityTypeManager()->getStorage("js_component")->loadMultiple());' 2>/dev/null | tr -cd '0-9')"
regions="$($DRUSH ev 'print count(\Drupal::entityTypeManager()->getStorage("page_region")->loadMultiple());' 2>/dev/null | tr -cd '0-9')"
if [[ "${components:-0}" -lt "$shipped_components" || "${regions:-0}" -lt "$shipped_regions" ]]; then
  echo "Refusing to regenerate: the site has ${components:-0} components and ${regions:-0} page regions." >&2
  echo "The recipe ships $shipped_components and $shipped_regions. Install this template on the site first, then re-run." >&2
  exit 1
fi

echo "==> Exporting code components and page regions"
# `uuid` and `_core` are site-specific; recipes ship neither. Core strips both
# before comparing recipe config with active config, so leaving them in would
# only add noise.
#
# The PHP knows no path: it prints a delimited stream and the host writes it.
# It used to write straight to a container path with the recipe name hardcoded
# into it, so on any other layout this deleted the snapshot and wrote nowhere.
$DRUSH ev '
foreach (["js_component", "page_region", "component"] as $type) {
  foreach (\Drupal::entityTypeManager()->getStorage($type)->loadMultiple() as $entity) {
    // Only the wrappers for our own code components; Canvas regenerates the
    // block and SDC ones from whatever else the site has installed.
    if ($type === "component" && !str_starts_with($entity->id(), "js.")) {
      continue;
    }
    $data = $entity->toArray();
    unset($data["uuid"], $data["_core"]);
    $name = $entity->getEntityType()->getConfigPrefix() . "." . $entity->id();
    print "----FILE:$name.yml----\n";
    print \Symfony\Component\Yaml\Yaml::dump($data, 8, 2);
  }
}
' > "$STAGING/stream.txt"

python3 - "$STAGING" <<'PY'
import pathlib, re, sys
staging = pathlib.Path(sys.argv[1])
name, buf = None, []
def flush():
    if name:
        (staging / name).write_text(''.join(buf))
for line in (staging / 'stream.txt').read_text().splitlines(keepends=True):
    header = re.match(r'^----FILE:(.+\.yml)----\n$', line)
    if header:
        flush()
        name, buf = header.group(1), []
    elif name:
        buf.append(line)
flush()
PY

written="$(ls "$STAGING"/*.yml 2>/dev/null | wc -l | tr -d ' ')"
if (( written < shipped_components + shipped_regions )); then
  echo "Refusing to replace the snapshot: the export produced $written files." >&2
  echo "Expected at least $(( shipped_components + shipped_regions )). Nothing has been deleted." >&2
  exit 1
fi
rm -f "$CONFIG_DIR"/canvas.js_component.*.yml "$CONFIG_DIR"/canvas.page_region.*.yml "$CONFIG_DIR"/canvas.component.js.*.yml
mv "$STAGING"/*.yml "$CONFIG_DIR"/
echo "    wrote $written config files"

echo "==> Splicing the global CSS into recipe.yml"
$DRUSH ev '
$library = \Drupal::config("canvas.asset_library.global")->getRawData();
// Only the CSS. `js.compiled` is empty and `js.original` is a Tailwind
// class-extraction manifest that the CLI regenerates on every push, so
// shipping it would be 30KB of noise that goes stale immediately.
$action = [
  "canvas.asset_library.global" => [
    "setProperties" => [
      "label" => $library["label"],
      "css" => ["original" => $library["css"]["original"], "compiled" => $library["css"]["compiled"]],
    ],
  ],
];
print \Symfony\Component\Yaml\Yaml::dump($action, 6, 2);
' > "$STAGING/asset-library.yml"

python3 - "$RECIPE_DIR" "$STAGING/asset-library.yml" <<'PY'
import pathlib, sys
recipe = pathlib.Path(sys.argv[1]) / 'recipe.yml'
raw = pathlib.Path(sys.argv[2]).read_text().rstrip('\n')
if not raw:
    raise SystemExit('the asset library export was empty; recipe.yml not touched')
# Indent to sit under `config.actions:`.
block = '\n'.join('    ' + line if line else line for line in raw.split('\n'))
BEGIN = '    # BEGIN generated: global CSS. @see tests/regenerate-components.sh\n'
END = '    # END generated\n'
s = recipe.read_text()
i, j = s.index(BEGIN), s.index(END)
recipe.write_text(s[:i] + BEGIN + block + '\n' + s[j:])
print('    spliced global CSS into recipe.yml')
PY

echo "==> Stamping the snapshot's provenance"
canvas_version="$($DRUSH ev 'print \Drupal::service("extension.list.module")->getExtensionInfo("canvas")["version"] ?? "unknown";' 2>/dev/null | tr -d '[:space:]' || true)"
python3 - "$RECIPE_DIR" "${ATELIER_UPSTREAM:-}" "${ATELIER_UPSTREAM_REVISION:-}" "${ATELIER_CANVAS_CLI:-}" "$canvas_version" <<'PY'
import json, pathlib, sys, datetime
root, upstream, revision, cli, canvas = sys.argv[1:6]
path = pathlib.Path(root) / 'composer.json'
data = json.loads(path.read_text())
snap = data.setdefault('extra', {}).setdefault('atelier', {}).setdefault('snapshot', {})
if upstream: snap['upstream'] = upstream
if revision: snap['upstream-revision'] = revision
if cli: snap['canvas-cli'] = cli
snap['drupal-canvas'] = canvas
snap['exported'] = datetime.date.today().isoformat()
path.write_text(json.dumps(data, indent=4) + '\n')
missing = [k for k in ('upstream', 'upstream-revision', 'canvas-cli') if not snap.get(k)]
if missing:
    print('    WARNING: provenance incomplete, set ' +
          ', '.join('ATELIER_' + m.upper().replace('-', '_') for m in missing))
else:
    print('    stamped provenance')
PY

echo
echo "NOTE: the footer page region carries a deliberate 'Powered by Drupal CMS'"
echo "      credit that a push overwrites with the scaffold default. Check the diff."
echo "==> Done. Review the diff, run tests/lint.sh, then re-run tests/check.sh."
