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

In a Drupal CMS project, require the recipe and pick "Nebula" in the installer:

```
composer require drupal/nebula
```

Or install from the command line:

```
drush site:install recipes/nebula
```

Or apply it to a site that already exists:

```
drush recipe /absolute/path/to/recipes/nebula
```

## What the template configures

**Canvas and code components.** The `canvas` module, plus the `canvas_stark`
theme it needs. Code components are `canvas.js_component` config entities that
live in the `canvas` module — there is no separate submodule to install.

**Authentication for the CLI.** `canvas_oauth`, `simple_oauth` and `consumers`,
with all eleven `canvas:*` OAuth scopes imported, including
`canvas:media:image:create`. That last one matters: the CLI asks for it in its
default scope string, and without it every push fails with `invalid_scope`.

**A theme with the regions Nebula targets.** `mercury`, whose `header` and
`footer` regions are what `regions/header.json` and `regions/footer.json` in a
Nebula codebase map onto.

**The content model the examples actually expect** — no more:

| Example component | What it needs, and what this template provides |
| --- | --- |
| `main_navigation` | `jsonapi_menu_items` exposing `/jsonapi/menu_items/main`, and a `main` menu with at least one link. Both provided. |
| `related_articles` | An `article` node type with `field_image`, `uid`, `created`, `title` and `path`, readable at `/jsonapi/node/article`. Provided via `core/recipes/article_content_type`. |
| `search_results` | `jsonapi_search_api` exposing `/jsonapi/index/cms_content`, backed by a Search API index of that exact name over nodes and Canvas pages. Provided. |
| `logo` | A site name and front page in `system.site`. Provided. |
| `breadcrumb` | Nothing beyond `canvas`. |
| The other 20 examples | Nothing. They are presentational, with static props. |

No taxonomy, no Views, no JSON-RPC, no content templates, and no `page` content
type — because nothing in the Nebula repo asks for them.

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

Until you do, the front page is the "Get started" article this template ships
at `/start`, which repeats these steps.

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
  imports `canvas`, `canvas_oauth`, `simple_oauth` and `filter.format.plain_text`
  explicitly. See `\Drupal\Core\Recipe\RecipeRunner::installModules()`.
- **`canvas_oauth`'s install hook is skipped for the same reason.**
  `canvas_oauth_install()` returns early when `$is_syncing`, so the
  `canvas:media:image:create` scope it would normally create never appears on a
  recipe-installed site. This recipe ships that scope as config instead.
- **Site templates cannot prompt during install.** Core supports `input` in
  `recipe.yml`, but `RecipeRunner::toBatchOperations()` — the path both the
  Drupal CMS installer and `drush site:install` use — never collects it.
  Inputs silently take their defaults.

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
