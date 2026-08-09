#!/usr/bin/env bash
#
# Checks that the Atelier site template installs a working site and can be
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
  --account-name=admin --account-pass=admin --site-name=Atelier -y >/dev/null
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
check 'default theme' atelier_theme \
  "$(ev 'print \Drupal::config("system.theme")->get("default");')"
# The shell theme must strip Drupal's own CSS and declare the regions Canvas
# page regions bind to. `regions:` replaces the default set wholesale, so a
# missing `content` region silently loses main content and messages.
# Drupal's styling CSS is dropped file by file, but `hidden.module.css` is
# kept: it defines `.visually-hidden`, which core's own skip link relies on.
# A per-file override silently no-ops if the path does not match
# system.libraries.yml exactly, so assert the shape as well as the outcome.
check 'shell theme drops Drupal styling CSS' 4 \
  "$(ev '$t = \Drupal::service("theme_handler")->getTheme("atelier_theme");
    $o = $t->info["libraries-override"]["system/base"]["css"]["component"] ?? [];
    print count(array_filter($o, fn ($v) => $v === FALSE));')"
check 'shell theme keeps hidden.module.css' 1 \
  "$(ev '$t = \Drupal::service("theme_handler")->getTheme("atelier_theme");
    $o = $t->info["libraries-override"]["system/base"]["css"]["component"] ?? [];
    print (int) !array_key_exists("css/components/hidden.module.css", $o);')"
check 'shell theme regions' content,footer,header \
  "$(ev '$t = \Drupal::service("theme_handler")->getTheme("atelier_theme");
    $r = array_keys($t->info["regions"] ?? []); sort($r); print implode(",", $r);')"
check 'no Mercury installed' 0 \
  "$(ev 'print (int) \Drupal::service("theme_handler")->themeExists("mercury");')"

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

# The content model the Atelier pages expect.
check 'article node type' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("node_type")->load("article");')"
check 'article field_image' 1 \
  "$(ev 'print (int) isset(\Drupal::service("entity_field.manager")->getFieldDefinitions("node","article")["field_image"]);')"
check 'image media type' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("media_type")->load("image");')"
check 'cms_content search index' 1 \
  "$(ev 'print (int) (bool) \Drupal::entityTypeManager()->getStorage("search_api_index")->load("cms_content");')"
# The vendored snapshot of the Atelier code components. Without these the site
# has no front end of its own until someone runs `canvas push`.
# @see tests/regenerate-components.sh
check 'code components shipped' 18 \
  "$(ev 'print count(\Drupal::entityTypeManager()->getStorage("js_component")->loadMultiple());')"
check 'global CSS applied' 1 \
  "$(ev 'print (int) str_contains(\Drupal::config("canvas.asset_library.global")->get("css.compiled") ?? "", "tailwindcss");')"
for region in header footer; do
  check "page region atelier_theme.$region" 1 \
    "$(ev "\$r = \Drupal::entityTypeManager()->getStorage('page_region')->load('atelier_theme.$region');
      print (int) (\$r && \$r->status() && count(\$r->get('component_tree')) > 0);")"
done
# Loading a region by ID is not enough: the page variant looks regions up by
# theme, which goes through the config entity lookup key store. That store can
# hold one region and not another, which renders the site with a header and no
# footer while every by-ID check above still passes.
# @see \Drupal\canvas\Plugin\DisplayVariant\CanvasPageVariant::build()
check 'regions discoverable by theme' 2 \
  "$(ev 'print count(\Drupal\canvas\Entity\PageRegion::loadForTheme("atelier_theme"));')"

# A visitor should never meet a contrib module's PHP notice mid-page. Errors
# still reach the log. Read past the override layer: a development environment
# (DDEV writes `verbose` into settings) would otherwise mask what the template
# actually stored.
check 'front end error display hidden' hide \
  "$(ev 'print \Drupal::configFactory()->getEditable("system.logging")->get("error_level");')"

# Imagery, shipped as file + media content so the pages have something to show
# on a fresh install. The component inputs reference media by UUID
# (CANVAS_ENTITY_REFERENCE), which Canvas remaps to the local serial ID on
# import — numeric IDs in an exported tree would only work by coincidence.
# @see \Drupal\canvas\EventSubscriber\DefaultContentSubscriber
# Project Browser reads the recommended add-ons list from a file this template
# ships, rather than from a remote URL it cannot have until publication.
check 'recommended add-ons list on disk' 1 \
  "$(ev 'print (int) file_exists("public://recommended-add-ons.yaml");')"
check 'Project Browser uses the shipped list' recommended \
  "$(ev 'print \Drupal::config("project_browser.admin_settings")->get("default_source");')"

check 'media shipped' 8 \
  "$(ev 'print count(\Drupal::entityTypeManager()->getStorage("media")->loadMultiple());')"
check 'hero image reference resolved' 1 \
  "$(ev '$p = \Drupal::service("entity.repository")->loadEntityByUuid("canvas_page", "4b3d5e15-3a8d-46c8-a502-1255c2b1ad26");
    foreach ($p?->getComponentTree() ?? [] as $i) {
      if ($i->getComponentId() === "js.hero") {
        $ref = $i->getInputs()["image"]["target_id"] ?? NULL;
        print (int) ($ref && \Drupal::entityTypeManager()->getStorage("media")->load($ref));
        return;
      }
    }
    print 0;')"

# Default content: four pages composed from those components, three of them in
# the main menu. Every menu link must resolve — a template that ships a nav
# pointing at a 404 is worse than one that ships no nav.
check 'main menu links' 3 \
  "$(ev 'print count(\Drupal::entityTypeManager()->getStorage("menu_link_content")->loadByProperties(["menu_name"=>"main"]));')"
check 'privacy page published' 1 \
  "$(ev '$p = \Drupal::entityTypeManager()->getStorage("canvas_page")->loadByProperties(["title" => "Privacy"]);
    $p = reset($p);
    print (int) ($p && $p->isPublished() && $p->get("path")->alias === "/privacy");')"
for page in "Home:4b3d5e15-3a8d-46c8-a502-1255c2b1ad26:/home:28" \
            "Studio:41c22c99-9e7a-4601-ab8c-517b366306d4:/studio:20" \
            "Journal:1797e924-d08c-40da-8f12-69155d704b44:/journal:3" \
            "Contact:5c31bfce-a14c-4aec-9928-e175a9502815:/contact:9"; do
  IFS=: read -r label uuid alias count <<<"$page"
  check "$label page published at $alias" 1 \
    "$(ev "\$p = \Drupal::service('entity.repository')->loadEntityByUuid('canvas_page', '$uuid');
      print (int) (\$p && \$p->isPublished() && \$p->get('path')->alias === '$alias');")"
  # Canvas drops tree items whose component id or enum values do not validate,
  # so a wrong value shows up as a short tree rather than an error.
  check "$label page component tree intact" "$count" \
    "$(ev "\$p = \Drupal::service('entity.repository')->loadEntityByUuid('canvas_page', '$uuid');
      print \$p ? iterator_count(\$p->getComponentTree()) : 0;")"
done

# The journal index prints publication dates, so they have to survive import.
# Without a pinned `created` every article lands on the install timestamp and
# the journal reads as three posts filed on the same afternoon.
check 'article dates are distinct' 3 \
  "$(ev '$d = [];
    foreach (\Drupal::entityTypeManager()->getStorage("node")->loadByProperties(["type" => "article"]) as $n) {
      $d[date("Y-m-d", $n->getCreatedTime())] = TRUE;
    }
    print count($d);')"

# Buttons are checked the same way menu links are, and for the same reason: a
# relabelling pass once left the front page's primary button promising a page
# and opening a mail client. Checking that the URL resolves is not enough —
# `mailto:` always "resolves" — so the label has to agree with the scheme.
check 'every button URL resolves and matches its label' 0 \
  "$(ev '$bad = 0;
    $check = function (array $inputs) use (&$bad) {
      $url = $inputs["url"] ?? "";
      $label = $inputs["label"] ?? "";
      if ($url === "") { return; }
      // A label that names a destination must not open a mail client, and a
      // label that asks for contact must not open a page.
      $asksToWrite = (bool) preg_match("/enquir|email|contact|get in touch/i", $label);
      $namesAPage = (bool) preg_match("/read|see|about|view|browse|studio|journal/i", $label);
      if (str_starts_with($url, "mailto:")) {
        if (!$asksToWrite || $namesAPage) { $bad++; }
        return;
      }
      if ($asksToWrite && !$namesAPage) { $bad++; }
      if (str_starts_with($url, "/")) {
        if (!\Drupal::service("path.validator")->isValid($url)) { $bad++; }
        return;
      }
      if (!str_starts_with($url, "http://") && !str_starts_with($url, "https://")) { $bad++; }
    };
    foreach (\Drupal::entityTypeManager()->getStorage("canvas_page")->loadMultiple() as $p) {
      foreach ($p->get("components")->getValue() as $i) {
        if ($i["component_id"] === "js.button") { $check(json_decode($i["inputs"], TRUE)); }
      }
    }
    foreach (\Drupal::entityTypeManager()->getStorage("page_region")->loadMultiple() as $r) {
      foreach ($r->get("component_tree") as $i) {
        if (($i["component_id"] ?? "") !== "js.button") { continue; }
        $raw = $i["inputs"] ?? [];
        $check(is_string($raw) ? json_decode($raw, TRUE) : $raw);
      }
    }
    print $bad;')"

# The footer menu is rendered by the same component as the main one, and its
# only link points at a node that ships unpublished by default. An anonymous
# visitor then gets an empty labelled landmark and no privacy statement.
check 'footer menu has a link for anonymous visitors' 1 \
  "$(ev '$links = \Drupal::entityTypeManager()->getStorage("menu_link_content")->loadByProperties(["menu_name" => "footer"]);
    $visible = 0;
    foreach ($links as $link) {
      // A disabled link pointing at `#` grants access to everyone and renders
      // to nobody, which is how this check passed while the footer was empty.
      if (!$link->isEnabled()) { continue; }
      $url = $link->getUrlObject();
      $target = $url->toString();
      if (strlen($target) === 0 || $target === "#") { continue; }
      if ($url->access(\Drupal\user\Entity\User::getAnonymousUser())) { $visible++; }
    }
    print (int) ($visible > 0);')"

# Every component here hydrates in the browser, so curl proves only that the
# server emitted a custom element: a component that throws on mount still ships
# green. If a browser is available, mount the front page and read the DOM back.
# Skipped rather than failed when it is not, so the suite still runs in CI.
if command -v agent-browser >/dev/null 2>&1 && [[ -n "${SITE_URL:-}" ]]; then
  export AGENT_BROWSER_IGNORE_HTTPS_ERRORS=1
  agent-browser --session atelier-check open "$SITE_URL/" >/dev/null 2>&1 || true
  sleep 4
  probe() { agent-browser --session atelier-check eval "$1" 2>/dev/null | tr -d '"'; }
  check 'components mount in a browser' yes \
    "$(probe "document.querySelector('h1') && /Six people/.test(document.querySelector('h1').textContent) ? 'yes' : 'no'")"
  check 'footer renders its links' yes \
    "$(probe "document.querySelectorAll('footer a').length > 0 ? 'yes' : 'no'")"
  # Three components take a `level` prop so an editor can keep headings in
  # order; nothing asserted that the shipped content actually does. A skipped
  # level went out on the studio page while those props existed.
  for hp in / /studio /journal /contact; do
    agent-browser --session atelier-check open "$SITE_URL$hp" >/dev/null 2>&1 || true
    sleep 2
    check "heading order intact on $hp" yes \
      "$(probe "(function(){var l=Array.from(document.querySelectorAll('h1,h2,h3,h4')).map(function(h){return +h.tagName[1]});for(var i=1;i<l.length;i++){if(l[i]-l[i-1]>1)return 'no'}return l.length&&l[0]===1?'yes':'no'})()")"
  done
  agent-browser --session atelier-check open "$SITE_URL/" >/dev/null 2>&1 || true
  sleep 2
  check 'no console errors on the front page' 0 \
    "$(agent-browser --session atelier-check console --level error 2>/dev/null | grep -c . | tr -cd '0-9')"
  # The header is one row wherever it fits and must never push the page sideways.
  agent-browser --session atelier-check set viewport 360 800 >/dev/null 2>&1 || true
  agent-browser --session atelier-check open "$SITE_URL/" >/dev/null 2>&1 || true
  sleep 3
  check 'no horizontal overflow at 360px' yes \
    "$(probe "document.documentElement.scrollWidth <= window.innerWidth ? 'yes' : 'no'")"
  agent-browser --session atelier-check close >/dev/null 2>&1 || true
else
  echo "    (skipped browser checks: agent-browser or SITE_URL unavailable)"
fi

# Journal entries are node pages, so without a content template they render
# through the default node display — which in a theme that emits no chrome means
# unstyled markup. The template binds the heading to the node title and the body
# to the body field, and it only takes over rendering when it is enabled.
check 'article content template enabled' 1 \
  "$(ev '$t = \Drupal::entityTypeManager()->getStorage("content_template")->load("node.article.full");
    print (int) ($t && $t->status() && count($t->get("component_tree")) > 0);')"
check 'articles have body copy' 3 \
  "$(ev '$n = 0;
    foreach (\Drupal::entityTypeManager()->getStorage("node")->loadByProperties(["type" => "article"]) as $node) {
      if (!$node->get("body")->isEmpty()) { $n++; }
    }
    print $n;')"

# The demo content is this library's documentation, so a component that renders
# nowhere is undocumented. This asserts a floor rather than a count: it fails
# when coverage drops, and does not need editing when content is added — unlike
# the per-page item counts above, which have been amended to match whatever
# shipped and so have never once constrained anything.
#
# The floor is 17, not 18. `badge` is deliberately unused: it was placed twice
# to satisfy this assertion and both times it read as a disabled control — once
# as a button in a hero's actions slot, once as a text input filling a grid
# column. Availability, the one thing it was carrying, is a `figure` prop now,
# in the caption of the piece it describes. A component with no honest home in
# this demo is better documented by its schema than by a bad placement, and an
# assertion that drives composition is worse than a gap it is covering up.
check 'components exercised by the demo' 1 \
  "$(ev '$used = [];
    foreach (\Drupal::entityTypeManager()->getStorage("canvas_page")->loadMultiple() as $p) {
      foreach ($p->get("components")->getValue() as $i) { $used[$i["component_id"]] = TRUE; }
    }
    foreach (\Drupal::entityTypeManager()->getStorage("page_region")->loadMultiple() as $r) {
      foreach ($r->get("component_tree") as $i) { $used[$i["component_id"]] = TRUE; }
    }
    foreach (\Drupal::entityTypeManager()->getStorage("content_template")->loadMultiple() as $c) {
      foreach ($c->get("component_tree") as $i) { $used[$i["component_id"]] = TRUE; }
    }
    print (int) (count($used) >= 17);')"

# Every shipped file entity needs its bytes beside it. Without them the
# importer logs a warning and leaves a managed row pointing at nothing, and the
# media count assertion cannot see it because no media references it.
check 'every file entity ships its binary' 0 \
  "$(python3 "$RECIPE_DIR/tests/lib/orphan-files.py" "$RECIPE_DIR/content/file")"

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
  for path in / /home /studio /journal /contact \
              /jsonapi /jsonapi/menu_items/main /jsonapi/index/cms_content /jsonapi/node/article; do
    # -L because `/home` 301s to `/`: it is the front page, and Drupal CMS's
    # `redirect` module canonicalises the alias onto it.
    check "GET $path (anonymous)" 200 \
      "$(curl -skL -o /dev/null -w '%{http_code}' "$base_url$path")"
  done
  body="$(curl -skL "$base_url/")"
  flat="$(tr -d '\n' <<<"$body")"

  # There is deliberately no server-rendered navigation: the shell theme emits
  # no chrome, and the site_nav component renders the menu itself in the
  # browser. So the menu has to be available as *data*,
  # which is what that component consumes, rather than as markup.
  menu_json="$(curl -sk "$base_url/jsonapi/menu_items/main")"
  for item in Studio Journal Contact; do
    check "main menu exposes '$item' over JSON:API" yes \
      "$(grep -qF "\"title\":\"$item\"" <<<"$menu_json" && echo yes || echo no)"
  done
  # Titles are not enough. The links reference pages by entity ID, which is
  # reassigned on every install, so a link can carry the right label and open
  # the wrong page — which is exactly what happened once.
  for pair in Studio:/studio Journal:/journal Contact:/contact; do
    IFS=: read -r title alias <<<"$pair"
    check "main menu link '$title' opens $alias" 1 \
      "$(ev "\$links = \Drupal::entityTypeManager()->getStorage('menu_link_content')->loadByProperties(['title' => '$title', 'menu_name' => 'main']);
        \$link = reset(\$links);
        if (!\$link) { print 0; return; }
        \$url = \$link->getUrlObject();
        print (int) (\$url->toString() === \Drupal::service('path_alias.manager')->getPathByAlias('$alias') || \$url->toString() === '$alias');")"
  done

  # The components render. Their markup is a `canvas-island` per component,
  # hydrated client-side, so count those rather than looking for prose.
  check 'front end renders Canvas components' yes \
    "$(grep -qE '<canvas-island' <<<"$flat" && echo yes || echo no)"
  # The components hydrate in the browser, so curl cannot prove they render.
  # It can prove they were handed this page's copy rather than an empty tree,
  # which is the failure a stale or mis-imported snapshot actually produces.
  # A specific article, not whichever one loads first, and a phrase from that
  # article's own body. The body reaches the browser inside the island payload,
  # so this proves the template's dynamic prop resolved rather than that the
  # component rendered.
  article_url="$(ev 'print reset(\Drupal::entityTypeManager()->getStorage("node")->loadByProperties([
    "type" => "article",
    "title" => "Notes from the bench: joinery without fixings",
  ]))->toUrl()->toString();')"
  curl -skL "$base_url$article_url" >/dev/null 2>&1 || true
  check 'journal entry carries its own body' yes \
    "$(curl -skL "$base_url$article_url" | grep -qF 'wedged through-tenon' && echo yes || echo no)"
  check 'components receive the page copy' yes \
    "$(grep -qF 'Six people, two benches' <<<"$flat" && echo yes || echo no)"
  # The imagery actually resolves to a derivative, rather than a broken ref.
  check 'front end renders the shipped imagery' yes \
    "$(grep -qE 'atelier-work-(hero|[123])\.jpg' <<<"$flat" && echo yes || echo no)"
  check 'front end renders the logo row' yes \
    "$(grep -qE 'atelier-logo-[1234].png' <<<"$flat" && echo yes || echo no)"
  check 'footer credits Drupal CMS' yes \
    "$(grep -qF 'Powered by Drupal CMS' <<<"$flat" && echo yes || echo no)"
  # Styling comes from the vendored global CSS, and from nothing else: the
  # shell theme contributes no Drupal CSS of its own.
  check 'component CSS on the page' yes \
    "$(grep -qE '<link[^>]*rel="stylesheet"' <<<"$flat" && echo yes || echo no)"
  # Drupal aggregates every stylesheet into one file, so a path check proves
  # nothing — fetch the aggregate and look for core's own base CSS in it.
  css_href="$(grep -oE 'href="/sites/default/files/css/[^"]*"' <<<"$flat" \
    | head -1 | sed 's/href="//; s/"$//; s/&amp;/\&/g')"
  if [[ -n "$css_href" ]]; then
    agg="$(curl -sk "$base_url$css_href")"
    # Drupal's styling CSS must be gone...
    check 'stylesheet carries no Drupal styling CSS' yes \
      "$(grep -qE '\.clearfix|\.js-hide|\.container-inline' <<<"$agg" && echo no || echo yes)"
    # ...but `.visually-hidden` has to survive, or core's own skip link renders
    # as visible text at the top of every page.
    check 'visually-hidden utility kept' yes \
      "$(grep -qE '\.visually-hidden' <<<"$agg" && echo yes || echo no)"
  else
    check 'stylesheet carries no Drupal styling CSS' yes no
    check 'visually-hidden utility kept' yes no
  fi

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
