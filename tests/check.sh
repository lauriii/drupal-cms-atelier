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

# Probe before rebuilding caches, so the report says whether the rebuild was
# actually needed rather than hiding it.
if [[ -n "${SITE_URL:-}" ]]; then
  echo "    HTTP / straight after install: $(curl -sk -o /dev/null -w '%{http_code}' "$SITE_URL/")"
fi

# `drush site:install` leaves a container that does not know about every module
# the recipe installed, so the first requests die with PluginNotFoundException
# for entity types like `oauth2_scope`. Rebuild before touching the site.
echo "==> Rebuilding caches"
$DRUSH cr >/dev/null 2>&1 || true

# `automated_cron` otherwise fires on the first anonymous request, and the first
# cron on a fresh Drupal CMS site takes long enough to fail that request. Get it
# out of the way, which also populates the search index.
echo "==> Running cron once"
$DRUSH cron >/dev/null 2>&1 || true

echo "==> Asserting the installed site"

# The one thing that makes this a selectable site template rather than an
# ordinary recipe. If the Drupal CMS installer is present, ask its own
# discovery code; otherwise check the discriminator directly.
if ev 'print (int) is_dir(DRUPAL_ROOT . "/profiles/contrib/drupal_cms_installer");' | grep -q 1; then
  # `scan()` is a generator that only catches RecipeFileException, so a sibling
  # recipe throwing anything else aborts it mid-iteration. That happens here
  # but never during a real install, because it is triggered by config the
  # already-applied recipes left behind. Collect what it yields before any
  # throw rather than asserting on the complete list.
  check 'offered as a site template by the installer' yes \
    "$(ev "require_once DRUPAL_ROOT . '/profiles/contrib/drupal_cms_installer/src/RecipeHandler.php';
      \$h = new \Drupal\drupal_cms_installer\RecipeHandler(\Drupal::state(), \Drupal::messenger());
      \$found = [];
      try { foreach (\$h->scan('Site') as \$n => \$r) { \$found[] = \$n; } } catch (\Throwable) {}
      print in_array('$RECIPE_NAME', \$found, TRUE) ? 'yes' : 'no';")"
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

# The Drupal CMS foundation, inherited from drupal_cms_site_template_base.
check 'admin theme is Gin' gin \
  "$(ev 'print \Drupal::config("system.theme")->get("admin");')"
for module in navigation dashboard gin_toolbar coffee project_browser \
              pathauto metatag scheduler workflows trash field_ui
do
  check "module $module installed" 1 \
    "$(ev "print (int) \Drupal::moduleHandler()->moduleExists('$module');")"
done
check 'content_editor role' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("user_role")->load("content_editor");')"
check 'content editors can manage code components' 1 \
  "$(ev 'print (int) \Drupal::entityTypeManager()->getStorage("user_role")->load("content_editor")->hasPermission("administer code components");')"
check 'page content type (Drupal CMS)' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("node_type")->load("page");')"
check 'content_format text format' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("filter_format")->load("content_format");')"
check 'welcome dashboard' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("dashboard")->load("welcome");')"
# `drupal_cms_helper`'s RecipeSubscriber rewrites `page.front` from an alias to
# its internal system path on apply, so this reads `/page/1`, not `/home`.
# Assert the relationship rather than the literal.
# @see \Drupal\drupal_cms_helper\EventSubscriber\RecipeSubscriber::onApply()
check 'front page is the landing page' 1 \
  "$(ev 'print (int) (\Drupal::service("path_alias.manager")->getPathByAlias("/home") === \Drupal::config("system.site")->get("page.front"));')"
# Setting page.front must not clobber the 403 the base recipe sets.
check 'base 403 page preserved' /user/login \
  "$(ev 'print \Drupal::config("system.site")->get("page.403");')"
check 'landing page is a canvas_page' Home \
  "$(ev 'print \Drupal::entityTypeManager()->getStorage("canvas_page")->load(1)?->label();')"

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
# Default content: a home page and an About page, both in the main menu.
check 'main menu links' 2 \
  "$(ev 'print count(\Drupal::entityTypeManager()->getStorage("menu_link_content")->loadByProperties(["menu_name"=>"main"]));')"
check 'About page exists and is published' 1 \
  "$(ev '$n = \Drupal::service("entity.repository")->loadEntityByUuid("node", "2b5e91d7-3c48-4f6a-8e21-9d0c7b4a3f15");
    print (int) ($n && $n->isPublished() && $n->bundle() === "page");')"
# Pathauto generates this from the title; nothing in the recipe hard-codes it.
check 'About page alias' /about \
  "$(ev '$n = \Drupal::service("entity.repository")->loadEntityByUuid("node", "2b5e91d7-3c48-4f6a-8e21-9d0c7b4a3f15");
    print $n ? \Drupal::service("path_alias.manager")->getAliasByPath("/node/" . $n->id()) : "";')"
check 'home page is published' 1 \
  "$(ev '$p = \Drupal::service("entity.repository")->loadEntityByUuid("canvas_page", "7c1f9a2e-84b6-4d3f-9c05-2ab7e6d1f843");
    print (int) ($p && $p->isPublished());')"
# The home page is a hero plus two card sections. If a component id or an enum
# value is wrong, Canvas drops the item, so assert the tree survived intact.
check 'home page component count' 12 \
  "$(ev '$p = \Drupal::service("entity.repository")->loadEntityByUuid("canvas_page", "7c1f9a2e-84b6-4d3f-9c05-2ab7e6d1f843");
    print $p ? iterator_count($p->getComponentTree()) : 0;')"
check 'home page uses cards' 6 \
  "$(ev '$p = \Drupal::service("entity.repository")->loadEntityByUuid("canvas_page", "7c1f9a2e-84b6-4d3f-9c05-2ab7e6d1f843");
    $n = 0; foreach ($p?->getComponentTree() ?? [] as $i) { if ($i->getComponentId() === "sdc.mercury.card") { $n++; } }
    print $n;')"

# The front end gets its header, navigation and footer from Canvas page
# regions. Without them a Mercury site renders no site chrome at all, because
# block placements are theme config entities and core skips those when a recipe
# installs a theme.
for region in header footer; do
  check "page region mercury.$region enabled" 1 \
    "$(ev "\$r = \Drupal::entityTypeManager()->getStorage('page_region')->load('mercury.$region');
      print (int) (\$r && \$r->status() && count(\$r->get('component_tree')) > 0);")"
done

# Anonymous JSON:API reads, which every data-fetching code component depends on.
check 'anonymous can access content' 1 \
  "$(ev 'print (int) \Drupal::entityTypeManager()->getStorage("user_role")->load("anonymous")->hasPermission("access content");')"

base_url="$(ev 'print \Drupal::request()->getSchemeAndHttpHost();')"
if [[ -n "$base_url" && "$base_url" != http* ]]; then base_url=""; fi
if [[ -n "${SITE_URL:-}" ]]; then base_url="$SITE_URL"; fi
if [[ -n "$base_url" ]]; then
  # `/` first: it is the page a human opens after installing, and a stale
  # container or a front page pointing at nothing both surface here and
  # nowhere else.
  for path in / /home /about \
              /jsonapi /jsonapi/menu_items/main /jsonapi/index/cms_content /jsonapi/node/article; do
    # -L because `/home` 301s to `/`: it is the front page, and Drupal CMS's
    # `redirect` module canonicalises the alias onto it.
    check "GET $path (anonymous)" 200 \
      "$(curl -skL -o /dev/null -w '%{http_code}' "$base_url$path")"
  done
  # Site chrome, not just a 200. This is what "the navigation is missing"
  # looks like from the outside, and a status code will not catch it.
  body="$(curl -sk "$base_url/")"
  check 'front end renders a <nav>' yes \
    "$(grep -qi '<nav' <<<"$body" && echo yes || echo no)"
  # Newlines stripped first: the anchor text sits on its own line, so a
  # line-based grep for `>Home<` misses it.
  flat="$(tr -d '\n' <<<"$body")"
  for item in Home About; do
    check "front end renders the '$item' menu link" yes \
      "$(grep -qE ">[[:space:]]*$item[[:space:]]*<" <<<"$flat" && echo yes || echo no)"
  done
  # Content, not just chrome: a component that fails to render leaves the
  # surrounding markup intact, so check for the text itself.
  for phrase in 'How this site works' 'Already configured for you' \
                'Author in your editor' 'Compose in Canvas'; do
    check "front end renders '$phrase'" yes \
      "$(grep -qF "$phrase" <<<"$flat" && echo yes || echo no)"
  done
  # The footer is a region too, and it rendered empty until it got branding.
  check 'footer region renders content' yes \
    "$(grep -qE '<footer' <<<"$flat" && echo yes || echo no)"
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
