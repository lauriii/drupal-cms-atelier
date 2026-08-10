# Plan 002: Ship the file entity for `recommended-add-ons.yaml`, so Project Browser works on a cold install

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fffbe98..HEAD -- recipe.yml content/file tests/check.sh`
> If any of those changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `fffbe98`, 2026-08-10

## Why this matters

This repository is a Drupal *recipe* — a site template. When someone installs a
site from it, Drupal's default-content importer walks `content/<entity_type>/*.yml`,
creates each entity, and for `file` entities copies the accompanying binary out
of `content/file/` into the site's public files directory. **A binary with no
entity YAML beside it is never copied.**

`content/file/recommended-add-ons.yaml` is exactly that: a 1,925-byte binary
with no entity. Its entity was deleted in commit `cfc17de` as part of a sweep
described in that commit message as "duplicate media and orphan file entities
pruned" — the entity looked orphaned because it declared a *different*
filename (`recommended-add-ons_3.yaml`, a Drupal re-upload suffix) from the one
that actually shipped.

Meanwhile `recipe.yml` still points Project Browser's default source at
`public://recommended-add-ons.yaml`. On a fresh install that file does not
exist, so the first thing an administrator sees when they open Project Browser
— which this template deliberately sets as the *default* source — is a source
pointed at nothing.

This has been invisible for two reasons, and both are worth understanding
before you fix it:

1. `drush site:install` drops and rebuilds the **database**. It does not clear
   `sites/default/files`. So on a machine that has ever installed a template
   which does ship this file, the byte-identical filename is already on disk
   and the assertion at `tests/check.sh:293` passes — on that machine only.
2. `tests/lib/orphan-files.py` walks entity YAMLs looking for missing binaries.
   It has no pass in the other direction, so a binary with no entity is
   structurally invisible to it. (Plan 004 in `plans/` adds that pass; this
   plan does not, so that the diff here stays small and obviously correct.)

The sibling site template `drupal_cms_blank`, which `recipe.yml:104` names as
the model for this approach, ships **both** halves — the binary and its file
entity. This template ships one.

## Current state

### `recipe.yml:102-111` — the config action, as it exists today

```yaml
    # Point Project Browser at the recommended add-ons list this template
    # ships as a file, rather than at a remote URL. Same approach as
    # drupal_cms_blank, and it works on a site with no network access.
    # @see content/file/6b2f19d4-8a07-4e53-91c6-3d05f8be71a2.yml
    project_browser.admin_settings:
      simpleConfigUpdate:
        enabled_sources.recommended:
          uri: 'public://recommended-add-ons.yaml'
          ttl: 86400
        default_source: recommended
```

The `@see` on the fourth line points at a file that does not exist anywhere in
this repository. Confirm that yourself before you start:

```
ls content/file/6b2f19d4-8a07-4e53-91c6-3d05f8be71a2.yml
```
→ `No such file or directory`

### `content/file/` — the shape of a correct file entity

Every other binary in `content/file/` has an entity YAML beside it. Here is a
complete one, `content/file/f1155f91-453c-4208-9fdf-9854ec1e988f.yml`, which is
the pattern to copy exactly:

```yaml
_meta:
  version: '1.0'
  entity_type: file
  uuid: f1155f91-453c-4208-9fdf-9854ec1e988f
  default_langcode: en
default:
  uid:
    -
      target_id: 1
  filename:
    -
      value: atelier-journal-bench.jpg
  uri:
    -
      value: 'public://atelier-journal-bench.jpg'
  filemime:
    -
      value: image/jpeg
  filesize:
    -
      value: 1017411
  status:
    -
      value: true
```

Note the invariants this repository maintains and which you must match:

- The `uuid` in `_meta` is identical to the filename stem of the YAML file.
- `uri` is `public://` + the exact name of the binary sitting beside it.
- `filesize` is the byte count of that binary. `tests/lib/orphan-files.py:26-29`
  compares them and increments its failure counter on a mismatch, and
  `tests/check.sh:565` asserts that counter is `0`. Get this number wrong and
  you will break a currently-passing check.
- There is no `uuid:` or `_core:` key at the top level of the mapping. The
  Kernel test `tests/src/Kernel/RequirementsTest.php:92-104` enforces that for
  `config/`; `content/` follows the same convention.

### `content/file/recommended-add-ons.yaml` — the binary that ships

Its first lines, so you can confirm you have the right file:

```
#
# A curated list of recommended add-ons, surfaced by Project Browser. This file
# is part of this site template's API and should not be renamed or removed
# unless you know precisely what you're doing.
#
```

Its exact size, which you will need:

```
wc -c content/file/recommended-add-ons.yaml
```
→ `1925`

### `tests/check.sh:293-296` — the assertions that cover this

```bash
check 'recommended add-ons list on disk' 1 \
  "$(ev 'print (int) file_exists("public://recommended-add-ons.yaml");')"
check 'Project Browser uses the shipped list' recommended \
  "$(ev 'print \Drupal::config("project_browser.admin_settings")->get("default_source");')"
```

The first of these is the one that is currently passing for the wrong reason.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Byte count of the binary | `wc -c < content/file/recommended-add-ons.yaml` | `1925` |
| Entity/binary pairing check | `python3 tests/lib/orphan-files.py content/file` | prints `0` |
| YAML parses | `python3 -c "import yaml,sys;yaml.safe_load(open(sys.argv[1]))" content/file/<new>.yml` | exit 0, no output |
| Files changed | `git status --porcelain` | only the paths in Scope |

`python3` is present. The `yaml` module may not be — if `import yaml` fails,
install it into a user site with
`python3 -m pip install --user pyyaml`, or skip that one verification and say
so in your report. **Do not** add PyYAML to any manifest in this repository as
part of this plan.

There is no build, no linter, no typecheck and no runnable test suite in this
repository. That is a known gap with its own plan in `plans/`; do not try to
fill it here.

## Scope

**In scope** (the only files you may modify or create):

- `content/file/1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10.yml` (create — see Step 1
  for why this exact UUID)
- `recipe.yml` — the `@see` comment on line 105 only
- `plans/README.md` — status row only

**Out of scope** (do NOT touch, even though they look related):

- `content/file/recommended-add-ons.yaml` itself. Do not edit, rename or
  reformat the binary. Its own header says it is part of the template's API,
  and its byte count is about to be pinned in the entity you are creating.
- `tests/lib/orphan-files.py`. Adding the reverse (binary-without-entity) pass
  is a separate plan. Doing it here would mean this change could no longer be
  reviewed as "one missing file restored".
- `tests/check.sh`. Its two existing assertions already cover this once the
  entity exists; adding more belongs to the plan that overhauls that script.
- Any other file in `content/`. In particular, do **not** go looking for other
  orphans and fix them in this commit.
- `content/file/6b2f19d4-8a07-4e53-91c6-3d05f8be71a2.yml`. Do not resurrect the
  deleted file with `git checkout cfc17de^ -- …`. Its `uri` was
  `public://recommended-add-ons_3.yaml`, which is the wrong filename and is the
  root cause of the whole problem. Write a new entity instead.

## Git workflow

- Branch: `advisor/002-restore-add-ons-file-entity`
- One commit.
- Commit messages in this repo are an imperative sentence with no prefix, often
  with a second clause. Examples from `git log --oneline`:
  - `Ship an enquiry form, and stop nine buttons opening a mail client`
  - `Fix the figure link, the emphasis, and prune dangling files where they are made`
  Write something like:
  `Ship the file entity that puts the add-ons list on disk`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create the file entity

Create `content/file/1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10.yml` with exactly
this content:

```yaml
# The bytes of this file ship beside it as `recommended-add-ons.yaml`. Default
# content only copies a binary into `public://` when an entity claims it, so
# without this file the list Project Browser is pointed at never lands on disk
# and its default source resolves to nothing. That is what happened between
# `cfc17de` and this commit.
# @see recipe.yml, the `project_browser.admin_settings` action.
_meta:
  version: '1.0'
  entity_type: file
  uuid: 1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10
  default_langcode: en
default:
  uid:
    -
      target_id: 1
  filename:
    -
      value: recommended-add-ons.yaml
  uri:
    -
      value: 'public://recommended-add-ons.yaml'
  filemime:
    -
      value: text/plain
  filesize:
    -
      value: 1925
  status:
    -
      value: true
```

Why a new UUID rather than the old one: the deleted entity's UUID
(`6b2f19d4-…`) is associated with a `uri` of `public://recommended-add-ons_3.yaml`
in this repository's history. Reusing it invites someone to `git show` the old
version and reintroduce the wrong filename. A fresh UUID has no such history.
The value above is a valid v4-shaped UUID that does not collide with anything
in this repository — verify that with the command below rather than trusting it.

**Verify**:
- `grep -rl "1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10" . --exclude-dir=.git`
  → exactly two paths: the new file and `plans/002-restore-recommended-add-ons-file-entity.md`
- `python3 -c "import yaml,sys;d=yaml.safe_load(open(sys.argv[1]));print(d['default']['filesize'][0]['value'])" content/file/1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10.yml`
  → `1925`
- `test "$(wc -c < content/file/recommended-add-ons.yaml)" -eq 1925 && echo ok` → `ok`

### Step 2: Confirm the entity/binary pairing is now complete in both directions

`orphan-files.py` only checks one direction, so run both — the second command
is the one that was silently failing before this change:

**Verify**:
- `python3 tests/lib/orphan-files.py content/file` → `0`
- Every binary now has an entity:
  ```
  python3 - <<'PY'
  import re, pathlib
  d = pathlib.Path('content/file')
  refs = set()
  for y in d.glob('*.yml'):
      m = re.search(r"value: '?public://([^'\n]+)'?", y.read_text())
      if m:
          refs.add(m.group(1))
  binaries = {p.name for p in d.iterdir() if p.suffix != '.yml'}
  missing = sorted(binaries - refs)
  print('binaries with no entity:', missing or 'none')
  PY
  ```
  → `binaries with no entity: none`

Before your change that command prints
`binaries with no entity: ['recommended-add-ons.yaml']`. Run it **before** you
create the file as well, and record both outputs in your report — it is the
proof that the fix does what it claims.

### Step 3: Fix the dangling `@see` in `recipe.yml`

`recipe.yml:105` currently reads:

```yaml
    # @see content/file/6b2f19d4-8a07-4e53-91c6-3d05f8be71a2.yml
```

Replace that single line with:

```yaml
    # @see content/file/1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10.yml, the file
    # entity that puts those bytes in `public://`. Without it the list is
    # never copied and this source resolves to a file that is not there.
```

Change nothing else in `recipe.yml`. In particular do not touch the generated
block between `# BEGIN generated: global CSS.` (`recipe.yml:132`) and
`# END generated` (`recipe.yml:139`) — those two lines are ~43 KB of machine-
written CSS spliced in by `tests/regenerate-components.sh`, and any hand edit
there will be silently overwritten on the next regeneration.

**Verify**:
- `grep -c "6b2f19d4" recipe.yml` → `0`
- `grep -c "1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10" recipe.yml` → `1`
- `python3 -c "import yaml;yaml.safe_load(open('recipe.yml'))"` → exit 0
- `git diff --stat recipe.yml` → `1 file changed, 3 insertions(+), 1 deletion(-)`
  (a larger diffstat means you touched the generated block — STOP)

## Test plan

There is no automated test suite in this repository that can be run without
first building a Drupal site, so there are no new test files to write here.
The verification is the command list above plus, **if and only if** a
disposable Drupal site with this recipe is available to you, one end-to-end
confirmation:

```
drush site:install recipes/atelier -y
drush ev 'print (int) file_exists("public://recommended-add-ons.yaml");'
```
→ `1`

That must be run on a site whose `sites/default/files` directory was **empty
before the install**, or it proves nothing — a leftover copy from any previous
install satisfies `file_exists()` regardless of what this recipe ships. If you
cannot guarantee an empty files directory, skip this step and say so in your
report rather than reporting a pass.

Do not run `tests/check.sh`. It is documented as DESTRUCTIVE
(`tests/check.sh:6-7`), it rebuilds the target site's database, and it has
independent defects that a separate plan addresses.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `test -f content/file/1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10.yml`
- [ ] `python3 tests/lib/orphan-files.py content/file` prints `0`
- [ ] The Step 2 "binaries with no entity" script prints `none`
- [ ] `grep -c "6b2f19d4" recipe.yml` returns `0`
- [ ] `python3 -c "import yaml;yaml.safe_load(open('recipe.yml'))"` exits 0
- [ ] `git diff --stat recipe.yml` shows 3 insertions and 1 deletion
- [ ] `git status --porcelain` lists only:
      `content/file/1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10.yml`, `recipe.yml`,
      `plans/README.md`
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `content/file/recommended-add-ons.yaml` is not exactly 1925 bytes. The
  `filesize` value in the plan would then be wrong, and a wrong `filesize`
  breaks the currently-green `orphan-files.py` assertion. Report the real size
  and stop.
- A file entity for `recommended-add-ons.yaml` already exists (the "binaries
  with no entity" script prints `none` *before* you change anything). Someone
  has already fixed this; report that and make no changes.
- `grep -rn "1e0a9a30-3d7f-4a4c-9d1b-5f2c7e6b4a10" .` finds a pre-existing use
  of that UUID anywhere. Pick another v4-shaped UUID, note the substitution in
  your report, and continue.
- `recipe.yml` no longer contains the `@see content/file/6b2f19d4-…` line, or
  the `project_browser.admin_settings` action has changed shape.
- Your `git diff` touches `recipe.yml` lines 132–139. Revert and retry; those
  are generated.

## Maintenance notes

For the human or agent who owns this next:

- **What a reviewer should scrutinise**: the `filesize` value against
  `wc -c`, that the `uri` has no numeric suffix (`_2`, `_3`) — that suffix is
  what broke it the first time and is what Drupal adds when a file of the same
  name is uploaded twice — and that the `recipe.yml` diff is three lines and
  not forty thousand.
- **What will interact with this**: `tests/regenerate-content.sh:38` deletes
  every `*.yml` in `content/file/` and re-exports from a live site, and its
  Python block at lines 93-107 then drops any entity whose binary is missing.
  If the live site you regenerate from has the file stored under a suffixed
  name, this entity comes back wrong. After any run of that script, re-run the
  Step 2 verification before committing.
- **Deliberately deferred**: teaching `tests/lib/orphan-files.py` to report
  binaries that no entity claims — that is the check which would have caught
  this in `cfc17de` and it belongs to the plan that builds a site-free
  validator. Until that lands, the Step 2 snippet is the only thing that
  detects this class of regression, and it lives only in this plan file.
- **Related**: `recipe.yml:104` says this mirrors `drupal_cms_blank`. That
  template's equivalent entity is
  `recipes/drupal_cms_blank/content/file/1cc8aa0c-5144-4046-a38d-d3c23296ec08.yml`
  in the `drupal_cms` repository, if you ever need to compare shapes.
