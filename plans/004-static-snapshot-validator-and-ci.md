# Plan 004: Add a site-free validator for the shipped snapshot, and run it plus the PHPUnit tests in CI

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fffbe98..HEAD -- config content recipe.yml tests`
> If any of those changed since this plan was written, re-run the baseline
> capture in Step 1 before proceeding; a validator calibrated to stale numbers
> is worse than none.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (purely additive — no shipped artifact changes)
- **Depends on**: `plans/002-restore-recommended-add-ons-file-entity.md` should
  land first, or Step 3's `--strict` run will fail on a defect that plan fixes.
  If 002 has not landed, follow the instruction in Step 3 for the known-failure
  allowlist.
- **Category**: tests
- **Planned at**: commit `fffbe98`, 2026-08-10

## Why this matters

This repository has **no CI of any kind** — no `.github/`, no `.gitlab-ci.yml`,
nothing, across 48 commits. And its only real verification, `tests/check.sh`,
begins with a destructive `drush site:install` against a disposable Drupal site
(`tests/check.sh:6-7,43`). So the feedback loop for "did I break the shipped
YAML?" is: build a Drupal CMS project, place this checkout at `recipes/atelier`,
install, wait for cron, and read 136 lines of output.

That is the wrong shape for what this repository actually is: 49 config files,
33 content entity YAMLs, a `recipe.yml`, and a README. The majority of the
regressions that have actually happened here are statically checkable in under
a second:

- A binary in `content/file/` with no entity YAML beside it — so it is never
  copied into the site's files directory. This shipped in commit `cfc17de` and
  was still shipping at `fffbe98`. `tests/lib/orphan-files.py` cannot see it,
  because it only walks entities→binaries and never the reverse.
- Image entities whose declared `width`/`height` do not match the JPEG they
  point at. **Eleven of thirty-seven are wrong at `fffbe98`**, four of them
  with the orientation flipped (e.g. `content/media/f1a3c47b-…yml` declares
  1800×1200 for a file that is 1800×2700).
- A `component_version` pinned in a shipped tree that is not the wrapper's
  `active_version` — one exists today, in the header page region.
- Type drift in shipped content: two `columns: 3` (integer) where the prop
  schema declares `type: string, enum: ['2','3','4']` and thirteen sibling
  values are `'3'`.
- Numeric claims in `recipe.yml`'s description going stale against what
  actually ships. There is already an assertion for this (`tests/check.sh:244`)
  but it needs a whole installed site to run.

Meanwhile the canonical site-template scaffold — `drupal/drupal_cms_site_template_base`,
which this template's `composer.json` requires — ships a ready-made
`.github/workflows/phpunit.yml` that stands up DDEV, creates a Drupal project,
installs the site template from a path repository, and runs its PHPUnit tests.
This repository is hosted on GitHub and does not have that file.

This plan adds the fast static gate and turns both it and the existing PHPUnit
tests on.

## Current state

### What exists to validate against

- `config/canvas.js_component.<name>.yml` — 21 files. Each has `props:`,
  `slots:`, and a `js:` mapping with `original` (JSX source) and `compiled`.
- `config/canvas.component.js.<name>.yml` — 21 files, one per component. Each
  has `id: js.<name>`, `active_version: <16 hex chars>`, and a
  `versioned_properties:` mapping whose keys are `active` plus zero or more
  historical version hashes.
- Component trees live in three places and reference components by id:
  - `content/canvas_page/*.yml` — 10 files. Trees are a list under
    `default.components`, each item having `component_id` and `inputs`, and
    **no** `component_version` (the importer binds them to the active version).
  - `config/canvas.page_region.atelier_theme.{header,footer}.yml` — trees are a
    mapping under `component_tree`, each item having `component_id` **and**
    `component_version`.
  - `config/canvas.content_template.node.article.full.yml` — same shape as a
    page region.
- `content/file/*.yml` — 33 file entities; each declares `filename`, `uri`
  (`public://<name>`), and `filesize`. 34 binaries sit beside them.
- `content/media/*.yml`, `content/node/*.yml` — image field values carry
  `width`, `height` and an `entity:` UUID pointing at a file entity.

### The one existing static check, and its shape

`tests/lib/orphan-files.py` is the model to follow — a small stdlib script that
prints a count, invoked from `tests/check.sh:565-566`:

```python
"""Counts file entities in a recipe's content/file whose bytes are missing.

Shipped without its binary, a file entity makes the importer log a warning and
leave a managed row pointing at nothing. Nothing else in the suite can see it,
because no media references it and the media count is unaffected.

Kept as a file rather than inline in check.sh: the first two attempts were a
sed expression that matched nothing and a heredoc that silently swallowed the
twenty assertions after it.
"""

import pathlib
import re
import sys

directory = pathlib.Path(sys.argv[1])
binaries = {p.name for p in directory.iterdir() if p.suffix != '.yml'}
missing = 0
for entity in sorted(directory.glob('*.yml')):
    text = entity.read_text()
    match = re.search(r"value: '?public://([^'\n]+)'?", text)
    if not match or match.group(1) not in binaries:
        missing += 1
        continue
    # A binary replaced without re-running the export leaves the entity
    # claiming a size the bytes do not have.
    declared = re.search(r'filesize:\n\s+-\n\s+value: (\d+)', text)
    if declared and int(declared.group(1)) != (directory / match.group(1)).stat().st_size:
        missing += 1
print(missing)
```

Note the conventions: a docstring that says *why*, stdlib only, no argparse, a
path as `sys.argv[1]`, and a single number on stdout. `tests/lib/measure-images.py`
follows the same shape but additionally uses Pillow and returns 0 from `main()`
deliberately (see its lines 60-62).

### The canonical CI workflow this repository is missing

`drupal/drupal_cms_site_template_base` ships this at `.github/workflows/phpunit.yml`.
It is reproduced here in full because you will be copying it and the executor
may not have network access:

```yaml
# Contains a GitHub Actions workflow to run PHPUnit tests for this site template.
# You can delete this file if you're not using hosting the repository on GitHub.
#
# See https://docs.github.com/en/actions for documentation about GitHub Actions.
#
on:
  - push
  - pull_request
jobs:
  phpunit:
    name: Run PHPUnit tests
    runs-on: ubuntu-latest
    steps:
      # Use DDEV to set up the environment, because it gives us everything we
      # need and it just works.
      - name: Set up DDEV
        uses: ddev/github-action-setup-ddev@v1
        with:
          autostart: false

      # Test with a plain Drupal project, like the default GitLab CI setup does.
      - name: Initialize DDEV and create a Drupal project
        # @see https://docs.ddev.com/en/stable/users/quickstart/#drupal
        run: |
          ddev config --project-type=drupal11 --docroot=web

          # For performance, don't audit dependencies.
          ddev config --web-environment-add="COMPOSER_NO_AUDIT=1"

          # Fully copy the site template into the project, rather than symlinking it.
          ddev config --web-environment-add="COMPOSER_MIRROR_PATH_REPOS=1"

          # Set environment variables needed by PHPUnit.
          # @see https://docs.ddev.com/en/stable/users/extend/custom-commands/#environment-variables-provided
          ddev config --web-environment-add='SIMPLETEST_BASE_URL=$DDEV_PRIMARY_URL'
          ddev config --web-environment-add='SIMPLETEST_DB=$DDEV_DATABASE_FAMILY://db:db@db/db'

          ddev start
          ddev composer create-project --no-install drupal/recommended-project

          # Require development dependencies like PHPUnit, but don't install them yet.
          ddev composer require --no-update --dev drupal/core-dev

      # Check out this repository.
      - uses: actions/checkout@v5
        with:
          path: source

      # We'll need to know the package name in the next step, so extract it into an
      # environment variable now.
      - name: Extract package name
        run: echo "PACKAGE_NAME=$(jq -r .name ./source/composer.json)" >> $GITHUB_ENV

      - name: Install the site template
        run: |
          ddev composer repository add source path source
          ddev composer config allow-plugins.drupal/site_template_helper true
          ddev composer require --update-with-all-dependencies "$PACKAGE_NAME:@dev"

      - name: Run tests
        run: ddev exec phpunit --configuration=./web/core ./recipes/$(basename $PACKAGE_NAME)
```

Two things about it that matter for this repository specifically:

- `composer.json:12` requires `drupal/jsonapi_search_api: ^1.0@RC`. That
  package has **no stable release** — only `1.0.0-rc1` through `1.0.0-rc5`.
  Composer only honours inline stability flags declared in the *root* package,
  so on a `drupal/recommended-project` root (default `minimum-stability: stable`)
  this dependency may fail to resolve. If the `Install the site template` step
  fails on stability, that is a genuine finding about the template's
  installability, not a CI bug — see the STOP conditions.
- This repository's `composer.json:1` names the package `drupal/atelier`, so
  `$(basename $PACKAGE_NAME)` is `atelier` and the tests are discovered at
  `./recipes/atelier`.

### The three PHPUnit tests that workflow would run

- `tests/src/Kernel/RequirementsTest.php` — conformance: no bundled
  `*.info.yml`, `type: Site`, a valid unprefixed `composer.json` with a licence
  and no pinned or patched dependencies, no `_core`/stray `uuid` in `config/`.
- `tests/src/Functional/ValidationTest.php` — applies the recipe to an empty
  site and asserts every component used in a tree has a `canvas.component.*.yml`.
- `tests/src/Functional/InstallTest.php` — installs Drupal from this recipe;
  `testInstall()` is `$this->expectNotToPerformAssertions()`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Python present | `python3 --version` | 3.9 or newer |
| YAML module | `python3 -c "import yaml"` | exit 0 (see note) |
| Pillow present | `python3 -c "import PIL; print(PIL.__version__)"` | a version string |
| Compile the validator | `python3 -m py_compile tests/lib/validate-snapshot.py` | exit 0 |
| Run the validator | `python3 tests/lib/validate-snapshot.py .` | see Step 3 |
| Shell syntax | `bash -n tests/lint.sh` | exit 0 |
| Workflow YAML parses | `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/phpunit.yml'))"` | exit 0 |

**PyYAML may not be installed.** If `import yaml` fails, install it into a user
site with `python3 -m pip install --user pyyaml`. Add it to
`tests/lib/requirements.txt` (create the file if it does not exist) alongside
`Pillow`; do **not** add it to `composer.json`.

## Scope

**In scope** (the only files you may modify or create):

- `tests/lib/validate-snapshot.py` (create)
- `tests/lint.sh` (create)
- `tests/lib/requirements.txt` (create, or extend if it already exists)
- `.github/workflows/phpunit.yml` (create)
- `.github/workflows/lint.yml` (create)
- `.gitattributes` — add `/.github export-ignore`
- `README.md` — one new subsection under `## Tests`
- `plans/README.md` — status row only

**Out of scope** (do NOT touch, even though they look related):

- **Any file the validator reports a problem in.** This plan builds the
  detector, not the fixes. If `validate-snapshot.py` flags eleven wrong image
  dimensions, you record them in the allowlist and stop. Fixing them is a
  different plan with a different reviewer question.
- `tests/check.sh` — a separate plan is rewriting its floor arithmetic and its
  `set -e` behaviour. Two agents editing that file is a merge conflict waiting
  to happen. **Do not wire the validator into `check.sh`**; the CI job is
  enough for now.
- `tests/lib/orphan-files.py` and `tests/lib/measure-images.py` — leave them.
  The new validator supersedes the first but removing it would change
  `tests/check.sh:565`, which is out of scope.
- `tests/regenerate-*.sh`.
- `composer.json` — do not add a `scripts` block, and above all do not add or
  change a `require` constraint. `tests/src/Kernel/RequirementsTest.php:68-82`
  enforces rules about that file and this plan has no business there.

## Git workflow

- Branch: `advisor/004-static-validator-and-ci`
- Commit per step is ideal: the validator, the runner, then CI.
- Commit message style is an imperative sentence with no prefix, e.g.
  `Check the shipped snapshot without building a site, and run it in CI`
- Do NOT push or open a PR unless the operator instructed it. **If the operator
  does ask you to push**: the CI workflow will run for the first time on that
  push and will likely surface pre-existing failures. That is the point. Report
  what it found; do not start fixing product defects to make CI green.

## Steps

### Step 1: Capture the baseline

Before writing anything, record what the repository looks like now, so the
validator's expected counts are measured rather than guessed. Run and keep the
output:

```
ls config/canvas.js_component.*.yml | wc -l      # expect 21
ls config/canvas.component.js.*.yml | wc -l      # expect 21
ls content/canvas_page/*.yml | wc -l             # expect 10
ls content/media/*.yml | wc -l                   # expect 31
ls content/file/*.yml | wc -l                    # expect 33
ls content/file | grep -v '\.yml$' | wc -l       # expect 34
grep -c '^\s*check ' tests/check.sh              # expect 80
git rev-parse --short HEAD
```

If any number differs from the expectation, the repository has drifted since
this plan was written — see STOP conditions.

### Step 2: Write `tests/lib/validate-snapshot.py`

Create a stdlib+PyYAML script that takes the repository root as `sys.argv[1]`,
prints one line per problem to stdout, prints a summary count last, and exits
non-zero if any problem was found (unless `--allow` is given, see Step 3).

Follow `tests/lib/orphan-files.py`'s conventions: a module docstring explaining
why the tool exists and what class of bug it catches, no argparse ceremony,
plain functions.

Implement exactly these eight checks and no others. Each is written as
"name — what it reads — what it reports":

1. **`yaml-parses`** — every `*.yml` under `config/`, `content/`, plus
   `recipe.yml`. Report any file that does not parse.

2. **`binary-has-entity`** — for every non-`.yml` file in `content/file/`,
   check that some `content/file/*.yml` declares `uri: public://<that name>`.
   Report each unclaimed binary. *This is the check that would have caught the
   `recommended-add-ons.yaml` regression.*

3. **`entity-has-binary`** — the existing `orphan-files.py` logic: every
   `content/file/*.yml` names a `public://` file that exists, and its declared
   `filesize` equals that file's byte count. Report each mismatch with the
   filename and both numbers.

4. **`image-dimensions`** — for every `width`/`height` pair in
   `content/media/*.yml` and `content/node/*.yml` that sits beside an
   `entity: <uuid>` referencing a file entity, decode the real dimensions from
   the binary and compare. Report `<yaml> <filename> declared WxH actual WxH`.
   Use Pillow (`from PIL import Image; Image.open(p).size`) — it is already a
   dependency of `tests/lib/measure-images.py:23`.

5. **`component-ids-resolve`** — collect every `component_id` from
   `content/canvas_page/*.yml` (list under `default.components`),
   `config/canvas.page_region.*.yml` and `config/canvas.content_template.*.yml`
   (mappings under `component_tree`). For each id of the form `js.<name>`,
   require both `config/canvas.component.js.<name>.yml` and
   `config/canvas.js_component.<name>.yml` to exist. Report any that do not.

6. **`version-pins-are-active`** — for every tree item that carries a
   `component_version`, require it to equal the `active_version` of the
   matching `config/canvas.component.js.<name>.yml`. Report
   `<file> <component_id> pinned <hash> active <hash>`. *One of these fails at
   `fffbe98`: the header page region pins `js.button` at `7f1fc8c10644f943`
   while the wrapper's `active_version` is `f8e3a3c941940e1a`.*

7. **`enum-inputs-are-strings`** — for every tree item's `inputs`, look up the
   prop in `config/canvas.js_component.<name>.yml`'s `props`. Where the prop
   declares `type: string` with an `enum`, require the shipped value to be a
   Python `str`, and require it to be in the enum. Report
   `<file> <component_id>.<prop> is <type> <value>`. *Two of these fail at
   `fffbe98`: `columns: 3` as an integer.*

8. **`recipe-description-counts`** — parse `recipe.yml`'s `description`, and
   require that the number-word before "components" equals the count of
   `config/canvas.js_component.*.yml` and the number-word before "pages" equals
   the count of `content/canvas_page/*.yml`. Reuse the word→number table from
   `tests/check.sh:246-249` verbatim so both stay in agreement.

Print a trailing summary in this shape, which is what CI and humans both read:

```
yaml-parses            ok
binary-has-entity      1 problem
entity-has-binary      ok
image-dimensions       11 problems
component-ids-resolve  ok
version-pins-are-active 1 problem
enum-inputs-are-strings 2 problems
recipe-description-counts ok

15 problems
```

**Verify**:
- `python3 -m py_compile tests/lib/validate-snapshot.py` → exit 0
- `python3 tests/lib/validate-snapshot.py .` → runs to completion, prints all
  eight check names, exits non-zero
- The reported problems match the numbers stated above for `fffbe98`. If they
  do not, see STOP conditions — do not adjust the validator until the counts
  match, and do not adjust the repository.

### Step 3: Add a known-failures allowlist so CI can be turned on today

The validator finds ~15 real problems at `fffbe98`. Fixing them is other plans'
work, so CI must be able to go green on the *current* state while still failing
on anything **new**.

Add a `--allow <file>` option. The file lists one problem line per row (the
exact string the validator prints), plus `#` comments. Problems present in the
allowlist are reported as `known` and do not affect the exit code; problems not
in it fail. A line in the allowlist that no longer matches any problem is
itself an error — that is what stops the file rotting.

Create `tests/lib/known-problems.txt`, generated from the current run, with a
header in the house style:

```
# Problems that ship at the commit this file was generated from. They are real
# and each has a plan in `plans/`; they are listed here so CI can fail on
# anything *new* rather than staying off until they are all fixed.
#
# Remove a line when its problem is fixed. A line here that no longer matches
# anything is an error: this file is not allowed to describe a past.
#
# Generated at: <the SHA from Step 1>
```

**Verify**:
- `python3 tests/lib/validate-snapshot.py . --allow tests/lib/known-problems.txt`
  → exits 0, prints `<N> known, 0 new`
- Prove it detects a new problem without committing one: copy the repository to
  a scratch directory, delete one `content/file/*.yml` entity there, run the
  validator against the copy, confirm it exits non-zero and names the newly
  unclaimed binary. Delete the scratch copy. **Do not** make that edit in the
  working tree.

### Step 4: Add `tests/lint.sh` as the single site-free entry point

Create an executable `tests/lint.sh`, modelled on the header style of
`tests/check.sh:1-22` (shebang, a comment block saying what it is and how to
run it, `set -euo pipefail`, paths derived from `BASH_SOURCE`):

```bash
#!/usr/bin/env bash
#
# Everything that can be checked without building a Drupal site.
#
# `tests/check.sh` needs a disposable site and a destructive install, so it is
# not something you run before every commit. This is: it reads the shipped
# YAML and the shipped binaries and nothing else, and it takes about a second.
#
# Usage:
#   tests/lint.sh
#
# Requires python3 with PyYAML and Pillow:
#   python3 -m pip install -r tests/lib/requirements.txt

set -euo pipefail

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "$RECIPE_DIR/tests/lib/validate-snapshot.py" "$RECIPE_DIR" \
  --allow "$RECIPE_DIR/tests/lib/known-problems.txt"
```

Make it executable (`chmod +x tests/lint.sh`) — `tests/check.sh` and both
regenerate scripts are `755`, so match them.

**Verify**:
- `bash -n tests/lint.sh` → exit 0
- `test -x tests/lint.sh && echo ok` → `ok`
- `tests/lint.sh` → exits 0, prints the summary

### Step 5: Add the two CI workflows

Create `.github/workflows/phpunit.yml` with the canonical content reproduced
verbatim in "Current state" above. Change nothing in it.

Create `.github/workflows/lint.yml`:

```yaml
# The site-free half of this repository's verification: it reads the shipped
# YAML and binaries and needs no Drupal, so it finishes in seconds and runs on
# every push. The PHPUnit workflow beside it covers what needs a real site.
on:
  - push
  - pull_request
jobs:
  lint:
    name: Validate the shipped snapshot
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: python3 -m pip install -r tests/lib/requirements.txt
      - run: tests/lint.sh
      - name: Check the shell scripts
        run: |
          sudo apt-get update && sudo apt-get install -y shellcheck
          shellcheck tests/*.sh
```

If `shellcheck tests/*.sh` reports pre-existing warnings on
`tests/check.sh` or the regenerate scripts, **do not fix them here** — those
files are out of scope. Instead add `|| true` to that one step with a comment
saying it is advisory until those scripts are cleaned up, and note it in your
report. Silent green is worse than an honest advisory.

Then add `/.github export-ignore` to `.gitattributes`. It currently reads:

```
# Dev-only paths, stripped from the packaged release. Matches what the shipped
# Drupal CMS site templates export-ignore.
/tests export-ignore
```

CI configuration is dev-only in exactly the same sense, and the canonical
scaffold's `.gitattributes.example` lists `/.github export-ignore` for this
reason.

**Verify**:
- `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/phpunit.yml'))"` → exit 0
- `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/lint.yml'))"` → exit 0
- `grep -c 'export-ignore' .gitattributes` → `2`
- `.github/workflows/phpunit.yml` matches the canonical content quoted in
  "Current state" character for character. Check it by diffing against a copy
  of that block: paste the quoted YAML into `/tmp/canonical.yml` and run
  `diff /tmp/canonical.yml .github/workflows/phpunit.yml` → no output. Do not
  "improve" the file; diverging from upstream means losing upstream's fixes.

### Step 6: Document it

Add a subsection to `README.md` immediately after the paragraph that ends
`...only run it against a disposable site.` (currently `README.md:626`):

```markdown
`tests/lint.sh` is the half that needs no site: it parses every shipped YAML,
checks that every binary in `content/file/` is claimed by an entity and vice
versa, that declared image dimensions match the files, that every
`component_id` resolves to both halves of its config, that every pinned
`component_version` is the wrapper's active one, that enum-typed inputs are
strings, and that `recipe.yml`'s description states the counts that actually
ship. It runs in about a second and on every push, via
`.github/workflows/lint.yml`. `tests/lib/known-problems.txt` lists the
problems that ship today so the gate fails on new ones; each has a plan in
`plans/`.

Both `tests/lint.sh` and `tests/lib/measure-images.py` need Python packages:
`python3 -m pip install -r tests/lib/requirements.txt`.

`.github/workflows/phpunit.yml` runs the three PHPUnit tests above on every
push, using the workflow the site-template scaffold ships.
```

**Verify**: `grep -c 'tests/lint.sh' README.md` → at least `2`

## Test plan

The validator is itself the test infrastructure, so the test plan is proving it
detects each of its eight problem classes. In a **scratch copy** of the
repository (`cp -r . /tmp/atelier-validator-check && cd /tmp/…`), introduce one
defect at a time and confirm the validator names it, then discard the copy:

| Check | Defect to introduce in the scratch copy | Expected |
|---|---|---|
| `yaml-parses` | append `\t- broken` to a config file | that file named |
| `binary-has-entity` | delete one `content/file/*.yml` | its binary named |
| `entity-has-binary` | change a `filesize` value by 1 | that entity named |
| `image-dimensions` | change a `width` value | that media file named |
| `component-ids-resolve` | rename `config/canvas.component.js.hero.yml` | `js.hero` named |
| `version-pins-are-active` | already fails at HEAD | header/`js.button` named |
| `enum-inputs-are-strings` | already fails at HEAD | both `columns` sites named |
| `recipe-description-counts` | delete a `canvas.js_component.*.yml` | count mismatch named |

Record the eight transcripts in your report. **Delete the scratch copy when
done** and confirm `git status --porcelain` in the real working tree lists only
the Scope files.

Do not run `tests/check.sh` — it is destructive and needs a Drupal site.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `python3 -m py_compile tests/lib/validate-snapshot.py` exits 0
- [ ] `python3 tests/lib/validate-snapshot.py .` exits non-zero and reports all eight check names
- [ ] `tests/lint.sh` exits 0 with the allowlist, printing `<N> known, 0 new`
- [ ] `test -x tests/lint.sh` succeeds
- [ ] `tests/lib/known-problems.txt` exists, has the `Generated at:` header, and every line matches a current problem
- [ ] `.github/workflows/phpunit.yml` and `.github/workflows/lint.yml` both parse as YAML
- [ ] `.github/workflows/phpunit.yml` is byte-identical to the canonical content quoted in this plan
- [ ] `grep -c 'export-ignore' .gitattributes` returns `2`
- [ ] `grep -c 'tests/lint.sh' README.md` returns at least `2`
- [ ] `tests/lib/requirements.txt` names both PyYAML and Pillow
- [ ] The eight scratch-copy detection transcripts appear in the report
- [ ] `git status --porcelain` lists only the Scope paths
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any Step 1 baseline number differs from its stated expectation. The
  repository has changed since this plan was written and the validator's
  calibration would be wrong.
- The validator finds **fewer** problems than stated (1 unclaimed binary, 11
  dimension mismatches, 1 stale version pin, 2 integer enum values). Fewer
  means either another plan already landed — check `plans/README.md` — or your
  check is not doing what it claims. Do not proceed by lowering the
  expectation.
- The validator finds problems in a class this plan did not predict. Report
  them; they may be real findings nobody has seen yet. Do not fix them.
- You are tempted to fix any flagged file to make the validator pass. That is
  explicitly out of scope. The allowlist exists so you do not have to.
- The `phpunit.yml` workflow, when run, fails at `Install the site template`
  with a Composer *stability* error naming `drupal/jsonapi_search_api`. That is
  a genuine installability defect of this template (that package has no stable
  release and inline `@RC` flags are ignored outside the root package), not
  something to work around by editing the workflow or `composer.json`. Report
  the exact Composer error and stop.
- Adding PyYAML turns out to require changing `composer.json`. It does not;
  if you think it does, stop.

## Maintenance notes

For the human or agent who owns this next:

- **The allowlist is a ratchet, not a wastebasket.** Every line in
  `tests/lib/known-problems.txt` should disappear as the plans in `plans/` land.
  The validator errors on a stale line specifically so the file cannot outlive
  the problems it describes. If a reviewer sees a line *added* in a PR, that PR
  is shipping a new defect and hiding it.
- **What a reviewer should scrutinise**: that `.github/workflows/phpunit.yml`
  was copied and not "improved" (it is upstream's, and diverging from it means
  losing upstream's fixes), that the allowlist's contents match the problems
  the other plans describe rather than anything extra, and that no shipped
  artifact under `config/` or `content/` changed in this commit.
- **What will interact with this**: `tests/regenerate-components.sh` and
  `tests/regenerate-content.sh` rewrite exactly the artifacts this validator
  reads. Running `tests/lint.sh` immediately after either script — before
  committing the diff — is the highest-value habit this repository can adopt;
  say so in the PR description.
- **Deliberately deferred**: wiring the validator into `tests/check.sh` (that
  file is being changed by another plan concurrently); replacing
  `tests/lib/orphan-files.py`, which check 3 supersedes but which
  `tests/check.sh:565` still calls; and a `.gitlab-ci.yml`, which
  `README.md:312-315` says belongs with a drupal.org publication and which
  would duplicate the GitHub workflows until then.
