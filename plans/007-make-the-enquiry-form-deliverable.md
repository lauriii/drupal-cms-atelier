# Plan 007: Let logged-in visitors reach the enquiry form, and stop a fresh install mailing enquiries into a reserved domain

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fffbe98..HEAD -- recipe.yml config/contact.form.enquiry.yml content/menu_link_content README.md tests/check.sh`
> If any of those changed since this plan was written, compare the
> "Current state" excerpts against the live files before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/003-stop-check-sh-aborting-silently.md`. That plan
  converts `tests/check.sh`'s assertion floor into an exact count held in
  `floor_base` / `floor_browser` / `floor_http` constants. This plan adds two
  assertions and must bump `floor_base` by 2. If 003 has **not** landed, bump
  the single `expected=` constant instead and say so in your report.
- **Category**: bug
- **Planned at**: commit `fffbe98`, 2026-08-10

## Why this matters

This template ships an enquiry form and routes the site's primary call to
action to it from nine buttons across ten pages. `README.md:259-281` devotes a
whole section to why it is Drupal's own contact form rather than a code
component. Two things about it are wrong on a fresh install.

**Logged-in visitors get a 403.** `recipe.yml:114-124` grants
`access site-wide contact form` to the `anonymous` role and not to the
`authenticated` role. Drupal permissions are not inherited from anonymous to
authenticated, so the moment a visitor logs in — including anyone in the
`content_editor` role this template creates — the enquiry form stops being
reachable for them. The recipe's own grant to anonymous is the proof that the
permission is not on by default. Every other permission in that block is
granted to both roles.

**Every enquiry goes nowhere.** `config/contact.form.enquiry.yml:7` sets a
single recipient on the `.example` top-level domain, which RFC 2606 reserves
precisely so that it can never resolve. Drupal's contact module does not
persist messages — it mails them and forgets — so a submission to an
unresolvable address is unrecoverable. Meanwhile
`config/contact.form.enquiry.yml:10` tells the sender "Thank you. We read every
enquiry and reply within two working days." Nothing in `README.md` mentions the
recipient at all, and `tests/check.sh:325-328` asserts only that the form
exists and that anonymous users can reach it.

A recipe genuinely cannot know the operator's email address — it is entered
during install, and `README.md:546-549` records that recipes applied through
the Drupal CMS installer or `drush site:install` never collect `input:` values.
So the placeholder has to stay. What can change is that the operator is *told*,
in the place they will actually look: Drupal CMS renders a `top-tasks` menu on
the welcome dashboard, and this template already inherits five links in it.

## Current state

### `recipe.yml:112-124` — the permission grants

```yaml
    # Code components fetch from JSON:API in the visitor's browser, so
    # anonymous users need read access to content and media.
    user.role.anonymous:
      grantPermissions:
        - 'access content'
        - 'view media'
        # Every page on this site asks a visitor to enquire; without
        # this they cannot reach the form that lets them.
        - 'access site-wide contact form'
    user.role.authenticated:
      grantPermissions:
        - 'access content'
        - 'view media'
```

### `config/contact.form.enquiry.yml` — complete

```yaml
langcode: en
status: true
dependencies: {  }
id: enquiry
label: Enquiry
recipients:
  - studio@atelier.example
reply: ''
weight: 0
message: 'Thank you. We read every enquiry and reply within two working days.'
redirect: ''
```

### The `top-tasks` menu

Five links ship in `content/menu_link_content/` with `menu_name: top-tasks` —
"Browse modules", "Change site appearance", "Choose recommended add-ons",
"Edit top tasks", "Invite users to collaborate". They came from the Drupal CMS
base recipe by way of a content re-export, and their UUIDs collide with the
base recipe's own, so on a fresh install the base's copies win and these are
skipped. A link with a **new** UUID imports normally. Here is the shape, from
`content/menu_link_content/cdc5767a-10b7-4bf2-b4bb-44733906b101.yml`:

```yaml
_meta:
  version: '1.0'
  entity_type: menu_link_content
  bundle: menu_link_content
  uuid: cdc5767a-10b7-4bf2-b4bb-44733906b101
  default_langcode: en
default:
  enabled:
    -
      value: true
  title:
    -
      value: 'Browse modules'
  menu_name:
    -
      value: top-tasks
  link:
    -
      uri: 'internal:/admin/modules/browse/drupalorg_jsonapi'
      title: ''
      options: {  }
  external:
    -
      value: false
  rediscover:
    -
      value: true
  weight:
    -
      value: 0
  expanded:
    -
      value: false
  revision_translation_affected:
    -
      value: true
```

Note that admin-facing links use `uri: 'internal:/…'` — a path — where the
front-end menu links in `content/menu_link_content/` use `target_uuid`, because
those follow entities this recipe ships and these point at Drupal's own admin
routes. Match the `internal:` form here.

`tests/check.sh:145-146` already asserts the welcome dashboard exists, which is
what renders this menu.

### `tests/check.sh:324-328` — the existing assertions

```bash
# Nine buttons ask the reader to enquire. Before this there was no form behind
# any of them, and nothing noticed, because a mailto: always "works".
check 'enquiry form exists and anonymous can reach it' yes \
  "$(ev '$form = \Drupal::entityTypeManager()->getStorage("contact_form")->load("enquiry");
    $anon = \Drupal::entityTypeManager()->getStorage("user_role")->load("anonymous");
    print $form && $anon->hasPermission("access site-wide contact form") ? "yes" : "no";')"
```

### Repo conventions

- `recipe.yml` comments explain *why* a line exists, in full sentences, and
  often name the failure that motivated it.
- `check` labels are short lowercase phrases; the helper pads them to 52
  columns.
- `ev()` (`tests/check.sh:39`) runs PHP through Drush and strips whitespace, so
  a multi-value result is usually joined with a separator by the PHP itself.
- Content YAML is `Yaml::dump` output at 2-space indent.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| `recipe.yml` parses | `python3 -c "import yaml;yaml.safe_load(open('recipe.yml'))"` | exit 0 |
| New content YAML parses | `python3 -c "import yaml,sys;yaml.safe_load(open(sys.argv[1]))" content/menu_link_content/<new>.yml` | exit 0 |
| Shell syntax | `bash -n tests/check.sh` | exit 0 |
| Count assertion sites | `grep -c '^\s*check ' tests/check.sh` | 2 more than before |

If `import yaml` fails, `python3 -m pip install --user pyyaml`.

**You cannot run `tests/check.sh`.** It needs a disposable Drupal site and
starts with a destructive `drush site:install` (`tests/check.sh:6-7`). Say so
in your report rather than implying the new assertions were exercised.

## Scope

**In scope** (the only files you may modify or create):

- `recipe.yml` — the `user.role.authenticated` grant list only
- `content/menu_link_content/2b6c1f84-77a5-4e19-b3d2-9c4e0a5d81f7.yml` (create)
- `tests/check.sh` — two new assertions and the matching floor bump
- `README.md` — a "Before you go live" subsection
- `plans/README.md` — status row only

**Out of scope** (do NOT touch, even though they look related):

- **`config/contact.form.enquiry.yml`.** Do not change the recipient to a real
  address (you do not have one and shipping someone's inbox in a public
  template is worse than the placeholder), and do not empty the `recipients`
  list — Drupal's contact mail handler joins that list into the `To:` header
  and an empty list means the mail has no destination at all, which is a
  silent failure rather than a bounce. The placeholder stays; this plan makes
  it visible.
- The `message:` text. Changing "we reply within two working days" to hedge
  would make the demo copy worse in order to describe a misconfiguration, which
  is the wrong trade.
- The other four `contact.*` config entities, if any exist — this template
  ships only `enquiry`.
- Anything about spam or flood control. The base recipe
  `drupal_cms_site_template_base` already applies `drupal_cms_anti_spam`.
- The five existing `top-tasks` links, and every other file in
  `content/menu_link_content/`. In particular do **not** try to resolve the two
  footer privacy links — commit `cfc17de` records that shape as deliberate.
- `config/`, `content/canvas_page/`, `content/node/`, `content/media/`.

## Git workflow

- Branch: `advisor/007-enquiry-form-reachable`
- One commit is fine.
- Commit message style is an imperative sentence with no prefix, often with a
  second clause, e.g.
  `Let logged-in visitors reach the enquiry form, and put its recipient in front of the admin`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Grant the permission to authenticated users

In `recipe.yml`, extend the `user.role.authenticated` grant list. Add the
permission and a comment in the house style explaining why it is not simply
inherited:

```yaml
    user.role.authenticated:
      grantPermissions:
        - 'access content'
        - 'view media'
        # Not inherited from anonymous -- Drupal roles do not nest -- so
        # without this line every page's primary call to action 403s the
        # moment a visitor logs in, including for the `content_editor` role
        # this template creates.
        - 'access site-wide contact form'
```

Change nothing else in `recipe.yml`. In particular do not touch the generated
block between `# BEGIN generated: global CSS.` (line 132) and `# END generated`
(line 139) — that is ~43 KB of machine-written CSS and any hand edit there is
overwritten by the next regeneration.

**Verify**:
- `python3 -c "import yaml;yaml.safe_load(open('recipe.yml'))"` → exit 0
- ```
  python3 -c "
  import yaml
  r = yaml.safe_load(open('recipe.yml'))
  a = r['config']['actions']
  for role in ('user.role.anonymous', 'user.role.authenticated'):
      print(role, 'access site-wide contact form' in a[role]['grantPermissions'])
  "
  ```
  → both lines end `True`
- `git diff --numstat recipe.yml` → `5  0  recipe.yml` (four comment lines plus
  the permission; a larger figure means you touched the generated block — STOP)

### Step 2: Put the recipient in front of the administrator

Create `content/menu_link_content/2b6c1f84-77a5-4e19-b3d2-9c4e0a5d81f7.yml`:

```yaml
# A site template cannot know the operator's email address: it is entered
# during install, and a recipe applied through the installer or
# `drush site:install` never collects `input:` values. So `contact.form.enquiry`
# ships a recipient on a reserved domain that can never resolve, and every
# enquiry a fresh install receives is mailed nowhere.
#
# This puts that one job on the dashboard the administrator lands on, beside
# the other five things Drupal CMS asks them to do first.
_meta:
  version: '1.0'
  entity_type: menu_link_content
  bundle: menu_link_content
  uuid: 2b6c1f84-77a5-4e19-b3d2-9c4e0a5d81f7
  default_langcode: en
default:
  enabled:
    -
      value: true
  title:
    -
      value: 'Set who receives enquiries'
  menu_name:
    -
      value: top-tasks
  link:
    -
      uri: 'internal:/admin/structure/contact/manage/enquiry'
      title: ''
      options: {  }
  external:
    -
      value: false
  rediscover:
    -
      value: true
  weight:
    -
      value: -10
  expanded:
    -
      value: false
  revision_translation_affected:
    -
      value: true
```

The `weight: -10` puts it above the five inherited links, because it is the one
task on that list that is broken until it is done.

**Verify**:
- `grep -rl "2b6c1f84-77a5-4e19-b3d2-9c4e0a5d81f7" . --exclude-dir=.git`
  → exactly two paths: the new file and this plan
- `python3 -c "import yaml,sys;d=yaml.safe_load(open(sys.argv[1]));print(d['default']['menu_name'][0]['value'], d['default']['link'][0]['uri'])" content/menu_link_content/2b6c1f84-77a5-4e19-b3d2-9c4e0a5d81f7.yml`
  → `top-tasks internal:/admin/structure/contact/manage/enquiry`
- `ls content/menu_link_content/*.yml | wc -l` → `17` (was 16)

### Step 3: Assert both fixes

Add two assertions to `tests/check.sh`. Put them immediately after the existing
enquiry-form assertion (currently ending at line 328), so the whole enquiry
story reads as one block.

```bash
# Roles do not nest, so a permission on anonymous does nothing for a logged-in
# visitor. Nine buttons point at this form; it 403'd for every authenticated
# user until the grant was added to both roles.
check 'enquiry form reachable when logged in' yes \
  "$(ev '$auth = \Drupal::entityTypeManager()->getStorage("user_role")->load("authenticated");
    print $auth && $auth->hasPermission("access site-wide contact form") ? "yes" : "no";')"
# The shipped recipient is on a reserved domain and can never resolve, because
# a recipe cannot know the operator's address. That is fine only for as long as
# the operator is told: this asserts the dashboard task that tells them exists
# and points at the form's own settings.
check 'a top task points at the enquiry recipient' yes \
  "$(ev '$found = "no";
    foreach (\Drupal::entityTypeManager()->getStorage("menu_link_content")->loadByProperties(["menu_name" => "top-tasks"]) as $link) {
      if (str_contains($link->getUrlObject()->toString(), "/contact/manage/enquiry")) { $found = "yes"; }
    }
    print $found;')"
```

Then bump the floor. If `plans/003-…` has landed, `floor_base` moves from 86 to
88. If it has not, `expected=128` moves to `130`. Whichever you do, say which
in your report.

**Verify**:
- `bash -n tests/check.sh` → exit 0
- `grep -c '^\s*check ' tests/check.sh` → 2 more than the value you recorded
  before starting
- Both new PHP bodies are syntactically valid. Copy each into `/tmp/a.php` with
  a leading `<?php` and run `php -l /tmp/a.php` → `No syntax errors detected`.
  Do this rather than reading it: `ev` sends stderr to `/dev/null`
  (`tests/check.sh:39`), so a parse error reports as a failed assertion with no
  explanation. Commit `cfc17de` records that exact trap costing a debugging
  round.
- The floor constant moved by exactly 2:
  `git diff tests/check.sh | grep -E '^[-+](floor_base|expected)='`

### Step 4: Write the "Before you go live" section

`README.md`'s enquiry-form section runs from line 259 to line 281. Add this at
the end of it, before the `## Shipping this on drupal.org` heading:

```markdown
### Before you go live

`contact.form.enquiry` ships with a recipient on a reserved domain
(`.example`), which by design can never receive mail — a recipe is applied
without ever asking for your address, so there is nothing honest to put there.
Until you change it, every enquiry the site accepts is mailed nowhere, and the
sender is told you will reply within two working days.

Set it at `/admin/structure/contact/manage/enquiry`, or:

```
drush config:set contact.form.enquiry recipients.0 you@example.com
```

The welcome dashboard carries a "Set who receives enquiries" task pointing at
the same place, above the five Drupal CMS puts there.

Two things are already handled and need no action: logged-in visitors can reach
the form (`recipe.yml` grants `access site-wide contact form` to both the
anonymous and the authenticated role — Drupal roles do not nest, so both are
needed), and spam protection comes from `drupal_cms_anti_spam`, which the base
recipe applies.
```

**Verify**:
- `grep -c 'Before you go live' README.md` → `1`
- `grep -c 'contact.form.enquiry' README.md` → at least `2`

## Test plan

No new test files: this repository's only suite is `tests/check.sh`, which
needs a live disposable site, and the two assertions added in Step 3 *are* the
test for this change. Static verification is the command list above.

If the operator has a disposable Drupal site with this template applied and
asks for a live check, the three things to confirm are:

```
drush ev 'print (int) \Drupal::entityTypeManager()->getStorage("user_role")->load("authenticated")->hasPermission("access site-wide contact form");'
```
→ `1`

```
drush ev 'foreach (\Drupal::entityTypeManager()->getStorage("menu_link_content")->loadByProperties(["menu_name" => "top-tasks"]) as $l) { print $l->getTitle() . "\n"; }'
```
→ includes `Set who receives enquiries`

and, logged in as a user whose only role is `authenticated`, that
`/contact/enquiry` returns 200 rather than 403.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `python3 -c "import yaml;yaml.safe_load(open('recipe.yml'))"` exits 0
- [ ] Both `user.role.anonymous` and `user.role.authenticated` list `access site-wide contact form`
- [ ] `git diff --numstat recipe.yml` shows 5 insertions and 0 deletions
- [ ] `ls content/menu_link_content/*.yml | wc -l` returns `17`
- [ ] The new menu link's `menu_name` is `top-tasks` and its `uri` is `internal:/admin/structure/contact/manage/enquiry`
- [ ] `bash -n tests/check.sh` exits 0
- [ ] `grep -c '^\s*check ' tests/check.sh` is exactly 2 higher than before
- [ ] `php -l` reports no syntax errors for both new PHP bodies
- [ ] The floor constant moved by exactly 2, and the report names which constant
- [ ] `config/contact.form.enquiry.yml` is unmodified (`git diff --stat` empty for it)
- [ ] `grep -c 'Before you go live' README.md` returns `1`
- [ ] `git status --porcelain` lists only the Scope paths
- [ ] The report states that `tests/check.sh` was not executed, and why
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `recipe.yml`'s `user.role.authenticated` block already grants
  `access site-wide contact form`. Someone has done part of this; report and
  do not guess at the rest.
- `git diff --numstat recipe.yml` shows more than 5 insertions. You have
  touched the generated CSS block — revert and retry.
- `php -l` reports a syntax error on either new assertion that you cannot fix
  in one attempt. A silently mis-parsed assertion is worse than no assertion;
  revert that hunk and report.
- `grep -rn "2b6c1f84-77a5-4e19-b3d2-9c4e0a5d81f7"` finds a pre-existing use of
  that UUID. Pick another v4-shaped UUID, note the substitution, continue.
- The `top-tasks` menu turns out not to render anywhere on this template's
  installed site. In that case the menu link is dead weight: keep Step 1, Step 3's
  first assertion and Step 4's README section, drop Step 2 and the second
  assertion, adjust the floor by 1 instead of 2, and report the finding — the
  five inherited `top-tasks` links in `content/` would then also be dead
  content worth removing in a separate plan.
- You are tempted to put a real email address anywhere in this repository. Do
  not; report instead.

## Maintenance notes

For the human or agent who owns this next:

- **What a reviewer should scrutinise**: that `config/contact.form.enquiry.yml`
  is untouched (the placeholder is deliberate, and a reviewer should be able to
  confirm at a glance that no address was added), that the `recipe.yml` diff is
  five lines, and that the floor constant moved by exactly the number of
  assertions added.
- **What will interact with this**: `tests/regenerate-content.sh` re-exports
  every `menu_link_content` on the site and would pick up the new top task
  along with everything else — that is fine, but check the diff, because the
  same script is what swept five base-recipe `top-tasks` links into this
  repository in the first place.
- **Deliberately deferred**: the five inherited `top-tasks` links, the
  unpublished "Privacy policy" node and five unreferenced media entities in
  `content/` are all artefacts of that unfiltered re-export. Cleaning them up
  needs an ownership predicate in the regeneration script and is worth its own
  plan; adding one link here does not make that worse.
- **If the enquiry form ever needs to persist submissions** rather than only
  mailing them, that is a different architecture — `README.md:261-265` explains
  why the current design deliberately avoids making JSON:API writable for
  anonymous users, and any change there should start from that paragraph.
