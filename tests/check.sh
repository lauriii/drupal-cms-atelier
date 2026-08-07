#!/usr/bin/env bash
#
# Checks that the Nebula site template installs a working site and can be
# applied twice without duplicating anything.
#
# DESTRUCTIVE: this drops and rebuilds the target site's database. Run it
# against a disposable site only.
#
# Usage:
#   tests/check.sh                       # uses `drush`
#   DRUSH="ddev drush" tests/check.sh    # inside DDEV
#
# ponytail: a shell script rather than a BrowserTestBase pair, because core's
# phpunit.xml.dist only discovers tests under `core/recipes/*`, not under a
# project-root `recipes/`. Swap in PHPUnit if this recipe ever ships as its own
# drupal.org project, where GitLab CI places it where discovery can see it.

set -euo pipefail

DRUSH="${DRUSH:-drush}"
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPE_NAME="$(basename "$RECIPE_DIR")"

pass=0
fail=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf '  ok   %-52s %s\n' "$label" "$actual"
    pass=$((pass + 1))
  else
    printf '  FAIL %-52s expected %s, got %s\n' "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

# Runs PHP in the site's bootstrap and prints a single value.
ev() { $DRUSH ev "$1" 2>/dev/null | tr -d '[:space:]'; }

echo "==> Installing a fresh site from recipes/$RECIPE_NAME"
install_start=$SECONDS
$DRUSH site:install "recipes/$RECIPE_NAME" \
  --account-name=admin --account-pass=admin --site-name=Nebula -y >/dev/null
echo "    installed in $((SECONDS - install_start))s"

echo "==> Asserting the installed site"

# The one thing that makes this a selectable site template rather than an
# ordinary recipe. If the Drupal CMS installer is present, ask its own
# discovery code; otherwise check the discriminator directly.
if ev 'print (int) is_dir(DRUPAL_ROOT . "/profiles/contrib/drupal_cms_installer");' | grep -q 1; then
  check 'offered as a site template by the installer' "$RECIPE_NAME" \
    "$(ev "require_once DRUPAL_ROOT . '/profiles/contrib/drupal_cms_installer/src/RecipeHandler.php';
      \$h = new \Drupal\drupal_cms_installer\RecipeHandler(\Drupal::state(), \Drupal::messenger());
      print implode(',', array_keys(iterator_to_array(\$h->scan('Site'))));")"
else
  check 'recipe type is Site' Site \
    "$(ev "print \Drupal\Core\Recipe\Recipe::createFromDirectory(DRUPAL_ROOT . '/../recipes/$RECIPE_NAME')->type;")"
fi

check 'canvas module installed' 1 \
  "$(ev 'print (int) \Drupal::moduleHandler()->moduleExists("canvas");')"
check 'code component entity type available' 1 \
  "$(ev 'print (int) \Drupal::entityTypeManager()->hasDefinition("js_component");')"
check 'default theme' mercury \
  "$(ev 'print \Drupal::config("system.theme")->get("default");')"

# Config entities a recipe-installed module does NOT get for free.
# @see \Drupal\Core\Recipe\RecipeRunner::installModules()
for name in \
  image.style.canvas_parametrized_width \
  filter.format.canvas_html_block \
  filter.format.plain_text \
  canvas.asset_library.global \
  simple_oauth.oauth2_token.bundle.access_token
do
  check "config $name" 1 \
    "$(ev "print (int) !\Drupal::config('$name')->isNew();")"
done

# The CLI's default scope string must resolve, including the media scope that
# canvas_oauth_install() skips when syncing.
check 'canvas:* OAuth scopes' 11 \
  "$(ev 'print count(\Drupal::entityTypeManager()->getStorage("oauth2_scope")->loadMultiple());')"
check 'canvas:media:image:create scope' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("oauth2_scope")->load("canvas_media_image_create");')"

# The content model the Nebula examples expect.
check 'article node type' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("node_type")->load("article");')"
check 'article field_image' 1 \
  "$(ev 'print (int) isset(\Drupal::service("entity_field.manager")->getFieldDefinitions("node","article")["field_image"]);')"
check 'image media type' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("media_type")->load("image");')"
check 'cms_content search index' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("search_api_index")->load("cms_content");')"
check 'main menu link' 1 \
  "$(ev 'print count(\Drupal::entityTypeManager()->getStorage("menu_link_content")->loadByProperties(["menu_name"=>"main"]));')"
check 'get started article' 1 \
  "$(ev 'print count(\Drupal::entityTypeManager()->getStorage("node")->loadByProperties(["type"=>"article"]));')"

# Anonymous JSON:API reads, which every data-fetching code component depends on.
check 'anonymous can access content' 1 \
  "$(ev 'print (int) \Drupal::entityTypeManager()->getStorage("user_role")->load("anonymous")->hasPermission("access content");')"

base_url="$(ev 'print \Drupal::request()->getSchemeAndHttpHost();')"
if [[ -n "$base_url" && "$base_url" != http* ]]; then base_url=""; fi
if [[ -n "${SITE_URL:-}" ]]; then base_url="$SITE_URL"; fi
if [[ -n "$base_url" ]]; then
  for path in /jsonapi /jsonapi/menu_items/main /jsonapi/index/cms_content /jsonapi/node/article; do
    check "GET $path (anonymous)" 200 \
      "$(curl -sk -o /dev/null -w '%{http_code}' "$base_url$path")"
  done
else
  echo "  skip  HTTP checks (set SITE_URL to enable)"
fi

echo "==> Re-applying the recipe (idempotency)"
before_links="$(ev 'print count(\Drupal::entityTypeManager()->getStorage("menu_link_content")->loadMultiple());')"
before_nodes="$(ev 'print count(\Drupal::entityTypeManager()->getStorage("node")->loadMultiple());')"

reapply_start=$SECONDS
if $DRUSH recipe "$RECIPE_DIR" -y >/dev/null 2>&1; then
  reapply=0
else
  # `drush recipe` needs a path the PHP process can see; inside DDEV the host
  # path differs from the container path.
  if $DRUSH recipe "/var/www/html/recipes/$RECIPE_NAME" -y >/dev/null 2>&1; then
    reapply=0
  else
    reapply=1
  fi
fi
check 'recipe re-applies cleanly' 0 "$reapply"
echo "    re-applied in $((SECONDS - reapply_start))s"

check 'menu links not duplicated' "$before_links" \
  "$(ev 'print count(\Drupal::entityTypeManager()->getStorage("menu_link_content")->loadMultiple());')"
check 'nodes not duplicated' "$before_nodes" \
  "$(ev 'print count(\Drupal::entityTypeManager()->getStorage("node")->loadMultiple());')"

echo
echo "$pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
