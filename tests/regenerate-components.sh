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
#   DRUSH="ddev drush" tests/regenerate-components.sh
#
# It writes:
#   config/canvas.js_component.*.yml   one per component
#   config/canvas.component.js.*.yml   the Canvas wrapper for each, which pins
#                                      the `component_version` that page regions
#                                      and pages reference
#   config/canvas.page_region.*.yml    the header/footer trees
#   recipe.yml                         the global CSS, spliced between markers
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

echo "==> Exporting code components and page regions"
rm -f "$CONFIG_DIR"/canvas.js_component.*.yml "$CONFIG_DIR"/canvas.page_region.*.yml "$CONFIG_DIR"/canvas.component.js.*.yml

# `uuid` and `_core` are site-specific; recipes ship neither. Core strips both
# before comparing recipe config with active config, so leaving them in would
# only add noise.
$DRUSH ev '
$dir = "/var/www/html/recipes/atelier/config";
$written = 0;
foreach (["js_component", "page_region", "component"] as $type) {
  foreach (\Drupal::entityTypeManager()->getStorage($type)->loadMultiple() as $entity) {
    $data = $entity->toArray();
    unset($data["uuid"], $data["_core"]);
    $name = $entity->getEntityType()->getConfigPrefix() . "." . $entity->id();
    // Only the wrappers for our own code components; Canvas regenerates the
    // block and SDC ones from whatever else the site has installed.
    if ($type === "component" && !str_starts_with($entity->id(), "js.")) {
      continue;
    }
    file_put_contents("$dir/$name.yml", \Symfony\Component\Yaml\Yaml::dump($data, 8, 2));
    $written++;
  }
}
print "wrote $written config files\n";
'

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
$yaml = \Symfony\Component\Yaml\Yaml::dump($action, 6, 2);
// Indent to sit under `config.actions:`.
$yaml = preg_replace("/^/m", "    ", rtrim($yaml)) . "\n";
file_put_contents("/tmp/atelier-asset-library.yml", $yaml);
print "prepared asset library action\n";
'

python3 - "$RECIPE_DIR" <<'PY'
import pathlib, subprocess, sys
recipe = pathlib.Path(sys.argv[1]) / 'recipe.yml'
block = subprocess.run(
    ['ddev', 'exec', 'cat', '/tmp/atelier-asset-library.yml'],
    capture_output=True, text=True, check=True).stdout.rstrip('\n')
BEGIN = '    # BEGIN generated: global CSS. @see tests/regenerate-components.sh\n'
END = '    # END generated\n'
s = recipe.read_text()
i, j = s.index(BEGIN), s.index(END)
recipe.write_text(s[:i] + BEGIN + block + '\n' + s[j:])
print('spliced global CSS into recipe.yml')
PY

echo
echo "NOTE: the footer page region carries a deliberate 'Powered by Drupal CMS'"
echo "      credit that a push overwrites with the scaffold default. Check the diff."
echo "==> Done. Review the diff, then re-run tests/check.sh."
