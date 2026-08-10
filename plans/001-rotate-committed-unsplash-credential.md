# Plan 001: Remove the committed third-party API credential from `tests/lib/source-images.py`, and record that it must be rotated

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fffbe98..HEAD -- tests/lib/source-images.py README.md`
> If either file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `fffbe98`, 2026-08-10

## Why this matters

`tests/lib/source-images.py` holds a live third-party API access key as a
module-level constant. It is an **Unsplash API access key (Client-ID)**. This
repository is public on GitHub (`lauriii/drupal-cms-atelier`) and is intended
for publication on drupal.org, so the value is readable by anyone who clones
it and by anyone reading the GitHub web UI.

`.gitattributes` marks `/tests export-ignore`, so the file is stripped from the
packaged Composer release. That limits *distribution*, not *disclosure* — the
value is in the git objects of a public repository and must be treated as
already compromised. Deleting the line does not undo that; only rotating the
credential at the provider does.

Two secondary defects live in the same 52-line file and are cheap to fix while
you are in it: the script crashes on its last line every single run, and it
depends on Pillow without saying so anywhere.

**This plan does not and cannot rotate the credential** — that happens in the
Unsplash developer console, which an executor has no access to. The plan's job
is to (a) get the value out of the working tree, (b) make the script read the
key from the environment instead, and (c) leave an unmissable written record
that rotation is still outstanding. Rotation itself is a human action recorded
in the "Handoff to a human" step.

## Current state

Files involved:

- `tests/lib/source-images.py` — 52 lines. A maintainer-only utility that
  searches Unsplash, downloads thumbnails, measures each one's mean luminance,
  mean saturation and saturation-weighted circular mean hue, and prints the
  candidates that fall inside the template's photographic brief. It is **not**
  called by `tests/check.sh` or by anything else — `grep -rn "source-images"
  tests/ README.md` returns only `README.md:184` and the file itself.
- `README.md` — the only documentation. Line 184 recommends the script.

The three lines that matter, as they exist today (the credential value is
deliberately not reproduced in this plan — open the file to see it):

```python
# tests/lib/source-images.py:11
KEY = '<a 43-character Unsplash access key literal>'
```

```python
# tests/lib/source-images.py:30-33
def search(q, per=10):
    u = ('https://api.unsplash.com/search/photos?query=%s&per_page=%d'
         % (urllib.parse.quote(q), per))
    r = urllib.request.Request(u, headers={'Authorization': 'Client-ID ' + KEY})
    return json.load(urllib.request.urlopen(r)).get('results', [])
```

```python
# tests/lib/source-images.py:52  (the last line of the file)
json.dump(hits, open(sys.argv[0].rsplit('/', 1)[0] + '/harvest/hits.json', 'w'))
```

`tests/lib/` contains exactly three files — `measure-images.py`,
`orphan-files.py`, `source-images.py`. There is no `harvest/` directory, and
`.gitignore` contains only `.DS_Store`, so it was never committed. Every run of
this script therefore raises `FileNotFoundError` *after* printing its results.

The sibling script `tests/lib/measure-images.py` is the exemplar for style in
this directory: a module docstring explaining *why* the tool exists, stdlib
plus Pillow, constants in caps at the top, a `main()` returning an exit code.
Match that. Both scripts `from PIL import Image`; nothing in the repo declares
that dependency.

Repo conventions to honour:

- Comments in this repository explain *why*, not *what*, and are written in
  full sentences. See `tests/lib/orphan-files.py:1-10` for the tone.
- Shell and Python in `tests/` are maintainer tools, not shipped code. They may
  fail loudly; they must not fail silently.
- `README.md` uses `**Bold lead-in.**` for the first phrase of a bullet in its
  "Notes and known edges" list.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Confirm the file compiles | `python3 -m py_compile tests/lib/source-images.py` | exit 0, no output |
| Confirm no key literal remains | `grep -rnE "[A-Za-z0-9_-]{40,}" tests/lib/source-images.py` | no matches (exit 1) |
| Confirm the env var is read | `grep -n "UNSPLASH_ACCESS_KEY" tests/lib/source-images.py` | at least one match |
| Fail-fast behaviour | `env -u UNSPLASH_ACCESS_KEY python3 tests/lib/source-images.py "workshop"` | exit 2 with a one-line message naming the variable; **no network request** |
| Working tree clean of other edits | `git status --porcelain` | only the files listed in Scope |

There is no build, no linter and no test runner in this repository — see
`plans/README.md`. `python3 -m py_compile` is the only static gate available
for Python here, so run it.

## Scope

**In scope** (the only files you may modify):

- `tests/lib/source-images.py`
- `tests/lib/requirements.txt` (create)
- `README.md` — only the two edits described in Step 4
- `plans/README.md` — status row only

**Out of scope** (do NOT touch, even though they look related):

- `tests/lib/measure-images.py` — it shares the measurement maths with
  `source-images.py`. Do **not** refactor the duplication into a shared module.
  Deduplication would change a file this plan has no verification story for,
  and `measure-images.py` is the one referenced by `README.md:182` and
  `README.md:310`.
- `tests/check.sh` — does not call this script; changing it is out of scope.
- Rewriting git history (`git filter-repo`, `git filter-branch`, BFG). Do not
  attempt it. It rewrites every commit SHA in a repository whose `plans/`
  files pin `fffbe98` for drift detection, and it does not remove the value
  from clones or forks that already exist. Rotation is the remedy; history
  rewriting is at best cosmetic.
- `.gitattributes` — the `export-ignore` line is correct and stays.

## Git workflow

- Branch: `advisor/001-rotate-committed-credential`
- One commit for the whole plan is fine; this is a small, single-concern change.
- Commit message style in this repo is a sentence in the imperative with no
  prefix and no scope, sometimes with a second clause. Examples from
  `git log --oneline`:
  - `Fix two accessibility failures in the new form, and guard the component export`
  - `Measure photographs instead of choosing them by eye`
  Write something like:
  `Read the image-sourcing key from the environment, and stop the script crashing on exit`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Replace the hardcoded key with an environment-variable read

In `tests/lib/source-images.py`, delete the `KEY = '…'` assignment at line 11
entirely. Add an import of `os` to the existing import line, and read the key
inside a small helper so the failure message is emitted once, before any
network call:

```python
def access_key():
    """The Unsplash access key, from the environment.

    Never hardcoded. A key that lives in a source file is a key that ends up in
    a public git history, which is what happened to the last one.
    """
    key = os.environ.get('UNSPLASH_ACCESS_KEY')
    if not key:
        sys.exit('Set UNSPLASH_ACCESS_KEY to an Unsplash API access key. '
                 'Create one at https://unsplash.com/oauth/applications.')
    return key
```

Then change the `Authorization` header in `search()` to use it:

```python
    r = urllib.request.Request(u, headers={'Authorization': 'Client-ID ' + access_key()})
```

`sys.exit('message')` prints to stderr and exits 1 in Python. If the fail-fast
verification below expects 2 and you get 1, use `sys.exit(2)` after an explicit
`print(..., file=sys.stderr)` — either is acceptable, but the command table
above must be updated to match whichever you produce, and the message must name
`UNSPLASH_ACCESS_KEY` verbatim.

**Verify**:
- `python3 -m py_compile tests/lib/source-images.py` → exit 0
- `grep -c "UNSPLASH_ACCESS_KEY" tests/lib/source-images.py` → `2` or more
- `grep -n "KEY = " tests/lib/source-images.py` → no matches
- `env -u UNSPLASH_ACCESS_KEY python3 tests/lib/source-images.py "workshop bench"`
  → a single line on stderr naming `UNSPLASH_ACCESS_KEY`, non-zero exit, and
  no HTTP traffic (the script must not reach `search()`).

### Step 2: Stop the script crashing on its last line

The final line writes to `…/harvest/hits.json`, a directory that does not exist,
so the script always ends in `FileNotFoundError` after printing its table.

Replace line 52 with a write that creates its own directory and reports where
it went, resolved relative to the script file rather than to `sys.argv[0]`
(which is only a bare filename when the script is invoked from inside
`tests/lib/`):

```python
out = pathlib.Path(__file__).resolve().parent / 'harvest' / 'hits.json'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(hits, indent=2))
print('\nwrote %s' % out)
```

Add `pathlib` to the imports. Then add `tests/lib/harvest/` to `.gitignore`
so the output of a maintainer run is never committed — **this is the one
exception to the out-of-scope list and it is deliberate**; append the line, do
not reorder or remove `.DS_Store`.

**Verify**:
- `python3 -m py_compile tests/lib/source-images.py` → exit 0
- `grep -n "harvest" .gitignore` → one match
- `grep -c "sys.argv\[0\]" tests/lib/source-images.py` → `0`

### Step 3: Declare the Pillow dependency

Create `tests/lib/requirements.txt`:

```
# Both measure-images.py and source-images.py need Pillow to read image data.
# Install with: python3 -m pip install -r tests/lib/requirements.txt
Pillow>=10
```

Do not add a lock file and do not pin an exact version — this repository's
`tests/src/Kernel/RequirementsTest.php:75-81` treats pinned dependencies as a
policy violation for the Composer manifest, and the same spirit applies here.

**Verify**: `test -f tests/lib/requirements.txt && grep -qi pillow tests/lib/requirements.txt && echo ok` → `ok`

### Step 4: Record the outstanding rotation, and the new prerequisites, in the README

Two edits to `README.md`, and only these two.

**Edit A** — in the "Notes and known edges" bulleted list (it begins at
`README.md:513` with `- **\`npx canvas login\` needs \`--client-id\`.**`), add a
new bullet at the end of the list, matching the surrounding style:

```markdown
- **The image-sourcing script needs an Unsplash key in the environment.**
  `tests/lib/source-images.py` reads `UNSPLASH_ACCESS_KEY`; it used to carry a
  key as a literal, which was committed to a public repository and must be
  treated as burned. If you are the maintainer of that Unsplash application,
  revoke the old key in the Unsplash developer console — deleting the line from
  the working tree does not remove it from the git history. Both scripts in
  `tests/lib/` also need Pillow: `python3 -m pip install -r tests/lib/requirements.txt`.
```

**Edit B** — `README.md:184` currently reads:

```
`tests/lib/source-images.py` searches Unsplash and returns only candidates
already inside the band.
```

Extend that sentence so a reader learns the prerequisite at the point of use:

```
`tests/lib/source-images.py` searches Unsplash and returns only candidates
already inside the band; it needs `UNSPLASH_ACCESS_KEY` set and Pillow
installed.
```

Do not restructure the surrounding paragraphs, and do not touch the photograph
list at `README.md:202-228`.

**Verify**:
- `grep -c "UNSPLASH_ACCESS_KEY" README.md` → `2`
- `grep -n "burned" README.md` → one match

### Step 5: Prove nothing that looks like a key remains anywhere in the working tree

**Verify**:
- `grep -rnE "Client-ID [A-Za-z0-9_-]{20,}" . --exclude-dir=.git` → no matches
- `grep -rnE "^[A-Z_]+ = '[A-Za-z0-9_-]{40,}'" tests/ ` → no matches
- `git status --porcelain` → exactly these paths and no others:
  `.gitignore`, `README.md`, `tests/lib/requirements.txt`,
  `tests/lib/source-images.py`, `plans/README.md`

Note that the value **is still in git history** and this grep does not and
cannot prove otherwise. That is expected; see the handoff below.

### Step 6: Handoff to a human — the part you cannot do

Append the following to your final report to the operator, verbatim. Do not
attempt any of it yourself.

> The Unsplash API access key that was at `tests/lib/source-images.py:11` as of
> commit `fffbe98` is still present in this repository's git history and the
> repository is public. Removing it from the working tree does not remediate
> it. Revoke that key in the Unsplash developer console
> (<https://unsplash.com/oauth/applications>) and issue a new one, then set
> `UNSPLASH_ACCESS_KEY` locally when you need the script. No other credential
> was found in the repository.

## Test plan

This repository has no automated test suite that covers `tests/lib/` — see
`plans/README.md` for the wider picture. The verification for this plan is
therefore the command list above rather than new test files, and that is a
deliberate scoping decision, not an oversight.

Do **not** add a Python test framework, a `tests/lib/test_*.py`, or a CI
workflow as part of this plan. A separate plan in `plans/` covers adding
automated verification to this repository, and doing it here would make this
change unreviewable.

One manual check, only if you have a valid key available (skip it otherwise and
say so in your report):

```
UNSPLASH_ACCESS_KEY=<your key> python3 tests/lib/source-images.py "workshop bench"
```

Expected: a table of candidates, then `wrote …/tests/lib/harvest/hits.json`,
then exit 0 — no traceback.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `python3 -m py_compile tests/lib/source-images.py` exits 0
- [ ] `grep -n "KEY = " tests/lib/source-images.py` returns no matches
- [ ] `grep -rnE "Client-ID [A-Za-z0-9_-]{20,}" . --exclude-dir=.git` returns no matches
- [ ] `env -u UNSPLASH_ACCESS_KEY python3 tests/lib/source-images.py x` exits non-zero and its stderr contains `UNSPLASH_ACCESS_KEY`
- [ ] `grep -c "sys.argv\[0\]" tests/lib/source-images.py` returns `0`
- [ ] `test -f tests/lib/requirements.txt` succeeds and the file names Pillow
- [ ] `grep -c "UNSPLASH_ACCESS_KEY" README.md` returns `2`
- [ ] `git status --porcelain` lists only the five paths named in Step 5
- [ ] The Step 6 handoff paragraph appears verbatim in the executor's report
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `tests/lib/source-images.py` at HEAD does not match the excerpts in "Current
  state" — in particular, if line 11 is no longer a key literal, someone has
  already done part of this work and you must not guess at the rest.
- You find a **second** credential anywhere in the repository. Report its
  `file:line` and the credential *type* only. Never paste the value into a
  commit message, a report, an issue, or a PR description.
- Any verification command in Steps 1–5 fails twice after one reasonable fix
  attempt.
- You conclude that history rewriting is necessary. It is explicitly out of
  scope; report the reasoning instead of acting on it.
- `git status --porcelain` shows a file outside the Scope list.

## Maintenance notes

For the human or agent who owns this next:

- **What a reviewer should scrutinise**: that the diff contains no key-shaped
  literal, that the env-var read happens *before* any network call (a key read
  inside the request loop would still allow one unauthenticated request), and
  that `README.md` states plainly that the old key must be revoked rather than
  implying deletion was sufficient.
- **What will interact with this**: any future plan that adds CI to this
  repository must not add `UNSPLASH_ACCESS_KEY` as a CI secret. This script is
  a maintainer utility run by hand; it has no place in an automated pipeline,
  and putting the key in CI would re-create the exposure with extra steps.
- **Deliberately deferred**: `tests/lib/measure-images.py` and
  `tests/lib/source-images.py` duplicate ~15 lines of colour-measurement maths
  (`measure-images.py:33-42` vs `source-images.py:17-27`), including a
  duplicated `LUM`/`SAT`/`HUE` band definition that can silently diverge. That
  is real duplication and worth fixing — but not in a plan whose whole point is
  a reviewable, minimal, security-motivated diff. Raise it separately.
- **The rotation is not done when this merges.** Until a human confirms the old
  key is revoked, treat the credential as live.
