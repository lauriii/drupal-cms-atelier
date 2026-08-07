# Nebula

A Drupal CMS site template that produces the Drupal side of a
[Nebula](https://github.com/acquia/nebula) setup: a site already configured to
be the backend that a Nebula codebase pushes Drupal Canvas code components to.

Nebula itself is the front-end half. It is a GitHub template repository,
consumed by `npx @drupal-canvas/create`, that generates a React and Tailwind
codebase for authoring code components. It is not a Drupal site. This recipe is
its counterpart.

## What makes this a site template

A recipe is offered as a selectable site template in the Drupal CMS installer
if, and only if, its `recipe.yml` has the top-level key `type: Site`
(case-sensitive). Discovery is a filesystem scan of the directory that the root
`composer.json` maps to `type:drupal-recipe` — `./recipes/{$name}` in a
standard Drupal CMS project — and the machine name is the directory name.

See `\Drupal\drupal_cms_installer\RecipeHandler::scan()`, which the installer
calls as `scan('Site')`. Core itself treats `type` as a free-form string;
`Site` is a convention the installer enforces, not core.

## Install

Require the recipe, then pick "Nebula" in the installer:

```
composer require drupal/nebula
```

Outside a Drupal CMS project, allow the Composer plugin that
`drupal_cms_site_template_base` depends on before requiring anything, or the
install aborts:

```
composer config --no-plugins allow-plugins.drupal/site_template_helper true
```

Instead of the installer UI, from the command line:

```
drush site:install recipes/nebula
```

Or apply it to a site that already exists:

```
drush recipe /absolute/path/to/recipes/nebula
```

## What the template configures

**A full Drupal CMS site.** The template is built on
`drupal_cms_site_template_base`, the same foundation Drupal CMS's own Starter
template uses, so you get the whole Drupal CMS admin experience rather than a
bare Drupal install: Gin as the admin theme, the navigation sidebar, dashboards,
Coffee, Project Browser, the `page` content type with its Canvas component tree,
the media types, the `content_editor` role, editorial workflow, Trash, Scheduler,
Pathauto, Metatag and the SEO and privacy tooling.

A site template should be built on that base rather than on another site
template. Applying it also covers `core/recipes/administrator_role`,
`content_editor_role` and the media-type recipes, so this template does not
repeat them.

**Canvas and code components.** Canvas comes from the base. Code components are
`canvas.js_component` config entities that live in the `canvas` module — there
is no separate submodule to install. This template grants `content_editor` the
`administer code components` and `administer page template` permissions, so
editors can work with what the CLI pushes.

**Authentication for the CLI.** `canvas_oauth`, `simple_oauth` and `consumers`,
with all eleven `canvas:*` OAuth scopes imported, including
`canvas:media:image:create`. That last one matters: the CLI asks for it in its
default scope string, and without it every push fails with `invalid_scope`.

**A theme with the regions Nebula targets, and a front end that works before
you push anything.** `mercury`, whose `header` and `footer` regions are what
`regions/header.json` and `regions/footer.json` in a Nebula codebase map onto.

Block placements are theme config entities, and core skips those when a recipe
installs a theme — so a Mercury site set up by a recipe renders no header,
navigation or footer at all unless the template supplies them. The mechanism
that supplies them is Canvas **page regions**, and this template ships two,
with the same structure Drupal CMS's own Starter template uses:

| Region | Contents |
| --- | --- |
| `mercury.header` | `sdc.mercury.navbar`, with `block.system_branding_block` in its `logo` slot and `block.system_menu_block.main` in its `navigation` slot |
| `mercury.footer` | `sdc.mercury.footer`, with `block.system_menu_block.footer` in its `footer_utility_first` slot |

`canvas push` replaces both with the trees from your `regions/*.json`, so they
are a working default rather than a fixture.

**Pages, so the site is not empty.** Two of them, both in the main menu:

- **Home** — a Canvas page at `/home`, set as the front page. Same pattern, and
  same path, as Drupal CMS's Blank and Starter templates. A Canvas page rather
  than a node on purpose; see the notes below.
- **About** — a node of Drupal CMS's own `page` type, published through the
  editorial workflow. Ordinary rich text, the kind of content an editor writes
  without touching code, to sit alongside the component-built home page.

The menu links reference their targets by `target_uuid` rather than by path, so
they follow the entities instead of breaking when an alias changes.

**The content model the examples actually expect** — no more:

| Example component | What it needs, and what this template provides |
| --- | --- |
| `main_navigation` | `jsonapi_menu_items` exposing `/jsonapi/menu_items/main`, and a `main` menu with at least one link. Both provided. |
| `related_articles` | An `article` node type with `field_image`, `uid`, `created`, `title` and `path`, readable at `/jsonapi/node/article`. Drupal CMS ships a `page` type, not an `article` one, so this template adds `core/recipes/article_content_type`. |
| `search_results` | `jsonapi_search_api` exposing `/jsonapi/index/cms_content`, backed by a Search API index of that exact name over nodes and Canvas pages. Provided. |
| `logo` | A site name and front page in `system.site`. Provided. |
| `breadcrumb` | Nothing beyond `canvas`. |
| The other 20 examples | Nothing. They are presentational, with static props. |

Nothing beyond that was invented for the Nebula side. No content templates, in
particular: Nebula's `canvas.config.json` points at a `content-templates/`
directory, but the repo ships none, so building one here would be guesswork.
Create it in your codebase and push it.

**A screenshot for the installer.** `screenshot.webp`, 500×400, which the
Drupal CMS installer shows on the template's card. Without one it falls back to
a generic default.

**Anonymous read access.** Code components fetch from JSON:API in the visitor's
browser, so `access content` and `view media` are granted to anonymous and
authenticated users.

## What the template deliberately does not do

It does not generate the OAuth key pair or create the consumer.

A recipe is declarative configuration. It cannot generate key material, and
shipping a fixed client secret in a public site template would mean every site
installed from it shares the same credentials. So the recipe stops at the
declarative boundary: modules installed, scopes defined, permissions granted.

Canvas ships an interactive Drush command for the generated-secret part. Check
whether your version has it:

```
drush list | grep canvas
```

If it is not there yet, the manual equivalent is below. Both produce the same
result.

## Finish the OAuth setup

Generate a key pair outside the document root and point `simple_oauth` at it:

```
drush simple-oauth:generate-keys ../keys
drush config:set simple_oauth.settings public_key ../keys/public.key
drush config:set simple_oauth.settings private_key ../keys/private.key
```

Create a consumer at `/admin/config/services/consumer/add`:

- **Client ID** — `cli` matches the value Nebula's `.env.example` ships, so
  using it means one less thing to edit.
- **New secret** — anything; you will paste it into `.env`.
- **Is Confidential?** — checked.
- **Grant types** — Client credentials.
- **User** — a real user, not anonymous. Canvas access checkers read this user.
  Note that the user's own role permissions are ignored; the scopes decide what
  the client can do.
- **Scopes** — all eleven `canvas:*` scopes.

Verify before moving on:

```
curl -X POST https://example.ddev.site/oauth/token \
  -d 'grant_type=client_credentials&client_id=cli&client_secret=YOUR_SECRET' \
  --data-urlencode 'scope=canvas:js_component canvas:asset_library canvas:media:image:create canvas:media:view canvas:page:create canvas:page:read canvas:page:edit canvas:content_template canvas:page_region'
```

That scope string is exactly what the CLI requests when a Nebula codebase has
`sync.pages`, `sync.regions` and `sync.contentTemplates` all enabled, which is
Nebula's default. A token in the response means the Drupal side is ready.

## Scaffold the Nebula codebase and connect it

```
npx @drupal-canvas/create my-site --site-url https://example.ddev.site
cd my-site
```

The scaffolder writes `.env` with `CANVAS_SITE_URL` already filled in. Two
things to know about that value:

- A `https://*.ddev.site` URL is rewritten to `http://`, because Node does not
  trust mkcert's local certificate authority. This is expected.
- It must be the site root, not the JSON:API endpoint.

Add the credentials from the previous step:

```
CANVAS_CLIENT_ID=cli
CANVAS_CLIENT_SECRET=your-secret
```

## Get a component onto the site

A freshly scaffolded Nebula project has no components. `examples/` is reference
material you copy from:

```
cp -R examples/components/card src/components/
npx canvas push
```

Components under `examples/` import each other through `@/components/*`, and
the build fails if a dependency is missing. Copy the whole dependency closure —
`card`, for instance, needs `button` and `heading`.

Pushing Nebula's example page and regions needs their components too, and the
external Unsplash URLs in `examples/pages/homepage.json` have to become Drupal
media first:

```
cp examples/regions/*.json regions/
cp examples/pages/homepage.json pages/
npx canvas reconcile-media
npx canvas push
```

Pushed pages arrive **unpublished**. Publish at `/admin/content/pages`, then
point the front page at it:

```
drush config:set system.site page.front /home
```

One caveat if you push Nebula's `examples/pages/homepage.json` verbatim: it also
targets `/home`, so you end up with two Canvas pages on one alias, and path
lookups resolve to the newer one. Re-applying the recipe would then point
`system.site.page.front` at the page you just pushed while it is still
unpublished, and the front page would start serving the login screen. Adopt the
existing page with `npx canvas pull` first, or delete it at
`/admin/content/pages`, before pushing a page of your own to `/home`.

There is no post-install message: `recipe.yml` has nine allowed top-level keys
and none of them emits one, and a site template cannot prompt during install
either. The surfaces that do exist are `extra.drupal_cms_installer.links`,
which puts the Nebula repository and the Canvas project page on the installer
card, and the landing page itself. This README is the real handoff.

## Local preview without Drupal

```
npm run dev
```

The Canvas Workbench renders components locally against `mocks.json`, so you do
not need this site for day-to-day component work — only to push.

## Notes and known edges

- **`npx canvas login` needs `--client-id`.** The interactive login flow
  discovers its client from `/.well-known/oauth-protected-resource`. Nothing in
  the Canvas or `simple_oauth` stack serves that endpoint today, so discovery
  404s and falls back to `/oauth/authorize` and `/oauth/token` with the client
  ID supplied by hand. For a PKCE consumer, add
  `http://localhost:4444/callback` as a redirect URI, enable the Authorization
  code grant, check **Use PKCE?**, and leave **Is Confidential?** unchecked.
  Client credentials, as configured above, is the simpler path and is what
  `push` and `pull` use.
- **Recipes skip module config entities.** When a recipe installs a module,
  core calls `setSyncing(TRUE)` first, which suppresses the config *entities*
  in that module's `config/install` — only simple config is created. Every
  config entity has to be listed under `config.import`. That is why this recipe
  imports `canvas_oauth` and `simple_oauth` explicitly; the base recipe already
  covers `canvas` and `filter` the same way. See
  `\Drupal\Core\Recipe\RecipeRunner::installModules()`.
- **`drupal/site_template_helper` is a Composer plugin** and has to be allowed
  before `drupal_cms_site_template_base` will install. In a Drupal CMS project
  it already is; elsewhere, run
  `composer config --no-plugins allow-plugins.drupal/site_template_helper true`.
- **`composer require` unpacks recipes.** `core-recipe-unpack` hoists a
  recipe's dependencies into your root `composer.json` and then drops the
  recipe itself from `require` and from `composer.lock`. The files stay in
  `recipes/`, which is all that matters at install time, but a later
  `composer install` on a clean checkout will not restore them. This template
  has the same dependency shape as `drupal_cms_starter`, so it behaves the same
  way; keep `recipes/` in version control if you want to re-apply later.
- **`canvas_oauth`'s install hook is skipped for the same reason.**
  `canvas_oauth_install()` returns early when `$is_syncing`, so the
  `canvas:media:image:create` scope it would normally create never appears on a
  recipe-installed site. This recipe ships that scope as config instead.
- **Site templates cannot prompt during install.** Core supports `input` in
  `recipe.yml`, but `RecipeRunner::toBatchOperations()` — the path both the
  Drupal CMS installer and `drush site:install` use — never collects it.
  Inputs silently take their defaults.
- **`simpleConfigUpdate` sets whole keys, not leaves.** Writing
  `page: {front: /home}` replaces the entire `page` array and silently drops
  the `page.403` and `page.404` the base recipe set. Use the dotted form,
  `page.front: /home`.
- **`RecipeHandler::scan()` aborts on a throwing sibling.** It only catches
  `RecipeFileException`, so any other exception from a neighbouring recipe ends
  the generator and hides every template after it. That does not bite during a
  real install, where nothing is applied yet, but it does if you scan a site
  that already has recipes applied — worth knowing when debugging a template
  that "does not appear".
- **Do not run `drush` against the site while it is installing.** Doing so
  caches a container built from a half-populated `core.extension`, and every
  later request then dies with `PluginNotFoundException: The "oauth2_scope"
  entity type does not exist` (and the same for `simple_sitemap`). `drush cr`
  clears it. A clean install with nothing else touching the site does not
  reproduce this.
- **First request after install is slow.** `automated_cron` is installed here so
  the search index fills without a real cron job, which means the first
  anonymous request runs a full cron on a fresh Drupal CMS site. Run
  `drush cron` once after installing.
- **Pathauto rewrites aliases on nodes in default content.** Drupal CMS ships a
  `/[node:title]` pattern, so a *node* shipped in a recipe's `content/` will not
  keep a hand-written alias. The About page here therefore ships no alias at
  all and lets Pathauto generate `/about` from the title. Canvas pages have no
  Pathauto pattern, which is why the home page is a `canvas_page` and its
  `/home` alias sticks.
- **`content_format` runs `filter_autop`.** Source line breaks inside a
  paragraph become `<br>` and the rendered text hard-wraps. Keep each HTML
  element on one line in `content/`, rather than using a YAML block scalar.
- **Deleting content does not remove it, and re-import then silently skips.**
  Drupal CMS installs Trash, so a deleted node is only soft-deleted.
  `loadEntityByUuid()` stops finding it, but the default content importer still
  reports `already exists` and — under `Existing::Skip`, which recipes use —
  quietly does nothing. Only relevant when re-applying a recipe over a site you
  have been editing; a fresh install has no trash. Purge with
  `drush trash:purge` before re-importing.
- **`page.front` will not read back as you wrote it.** `drupal_cms_helper`'s
  `RecipeSubscriber` resolves it from an alias to the internal system path when
  a recipe is applied, so `page.front: /home` ends up stored as `/page/1`. That
  is deliberate — core expects a system path there — so assert the relationship,
  not the literal.
- **Component versions in page regions are site-specific.** A page region pins
  `component_version` per component. The `sdc.mercury.*` hashes match Drupal
  CMS Starter's, but the `block.*` ones did not — they are derived from the
  site's block plugin configuration. Generate them from a real install rather
  than copying another template's, and re-check after a Mercury or Canvas
  upgrade.

## Automated check

```
tests/check.sh
```

Installs a throwaway site from the recipe, asserts the pieces above are in
place, applies the recipe a second time, and asserts nothing was duplicated.
It rebuilds the site's database, so only run it against a disposable site.

## License

GPL-2.0-or-later, like the Drupal configuration it ships. The Nebula codebase
template it pairs with is MIT.
