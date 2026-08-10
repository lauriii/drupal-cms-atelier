# Plan 006: Cut the shipped photograph payload by ~60%, and make every declared image dimension match the file it points at

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fffbe98..HEAD -- content README.md`
> If anything under `content/` changed since this plan was written, re-run the
> Step 1 baseline before proceeding; the numbers below are measured against
> `fffbe98`.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED — this plan rewrites 27 binary files and 37 metadata
  declarations. It is mechanical and fully verifiable, but it is not small.
- **Depends on**: none. If `plans/004-static-snapshot-validator-and-ci.md` has
  landed, its `image-dimensions` and `entity-has-binary` checks verify this
  plan's result directly and eleven lines can be removed from
  `tests/lib/known-problems.txt`.
- **Category**: perf
- **Planned at**: commit `fffbe98`, 2026-08-10

## Why this matters

Two separate defects in the same set of files.

**The payload.** `content/file/` holds 27 JPEGs totalling **12.89 MB** — about
95% of everything this template ships. Individual files reach 1.33 MB
(`atelier-workshop-door.jpg`). Nothing on the produced site displays an image
wider than roughly 1100 CSS pixels: the `figure` component caps at `40vw` above
1024px and `hero` at `58vw`. `README.md:308-311` already names size as one of
four things to settle before publication, and estimates that 1200px "roughly
halves the payload". Measured, the saving is larger than that.

The cost is not only the download. `article_teasers` — the component that
renders the journal index and the "More from the bench" band under every
article — fetches `field_image.uri.url` from JSON:API, which is the **original**
file, and renders it into a 176×112 CSS box. On `/journal` that is six
originals totalling **3.48 MB** drawn as thumbnails. Every other image-bearing
component (`figure`, `hero`, `logo`, `testimonial`) goes through Canvas's
`<Image>` primitive and gets a derivative; `article_teasers` is the one that
does not. Fixing that properly means editing the component's JSX, which lives
in a separate codebase this repository does not contain — so it is **out of
scope here** and recorded as a follow-up. Shrinking the originals is the part
that can be done in this repository, and it reduces that 3.48 MB
proportionally.

**The declared dimensions.** Eleven of the thirty-seven image field values in
`content/media/*.yml` and `content/node/*.yml` declare `width`/`height` that do
not match the JPEG they point at, and four of those have the **orientation
flipped**:

| Entity YAML | File | Declared | Actual |
|---|---|---|---|
| `content/media/1298229c-9e7c-44d5-ae19-7e84c6f8c490.yml` | `atelier-service-runs.jpg` | 1800×2700 | 1600×1067 |
| `content/media/5eb80978-a637-4707-8b4d-8b6e9103084c.yml` | `atelier-workshop-inside.jpg` | 1800×2700 | 1600×900 |
| `content/media/65c8822a-f870-4caa-b15b-b4a19b2f7116.yml` | `atelier-work-shelf.jpg` | 1800×1125 | 1600×2133 |
| `content/media/731cb42a-46e3-48a2-b4ef-5fbfab4c46f3.yml` | `atelier-service-restoration.jpg` | 1800×2697 | 1800×1404 |
| `content/media/7a772863-f13b-4772-b5e9-395057248765.yml` | `atelier-ref-runs-2.jpg` | 1400×933 | 1600×1067 |
| `content/media/9788969e-bbe4-4e49-b8dd-12645cde8f5c.yml` | `atelier-ref-runs-1.jpg` | 1400×2100 | 1600×1067 |
| `content/media/b89493b3-3079-457d-b4c4-484108554830.yml` | `atelier-ref-commissions-2.jpg` | 1400×930 | 1600×1067 |
| `content/media/dae4d2fc-0f4d-49bb-88e2-b71ba7978f6a.yml` | `atelier-ref-commissions-1.jpg` | 1400×2070 | 1600×2400 |
| `content/media/f1a3c47b-6333-499e-bcf4-09eac059e143.yml` | `atelier-workshop-door.jpg` | 1800×1200 | 1800×2700 |
| `content/media/f53bd614-0d46-4687-85ba-c63f9aa491ea.yml` | `atelier-ref-restoration-3.jpg` | 1400×2100 | 1600×1067 |
| `content/media/fedfd51b-e5e4-4cdc-9bb1-7b810fbce2d7.yml` | `atelier-ref-restoration-2.jpg` | 1400×2100 | 1800×1200 |

Drupal writes those numbers into the rendered `width`/`height` attributes and
into the box Canvas's `<Image>` reserves before the file loads. A portrait box
reserved for a landscape photograph is a guaranteed layout shift, and on a hero
that is cumulative layout shift against the largest element on the page.
`content/media/731cb42a-…yml` is the Restoration page's hero.

Because this plan re-encodes every photograph anyway, **all thirty-seven
declarations get re-derived from the actual bytes** — the eleven wrong ones are
fixed as a consequence rather than as a separate pass.

## Current state

### The photographs

27 JPEGs in `content/file/`, from 119 KB to 1,325 KB, at widths of 1400 (×3),
1600 (×9), 1700 (×1) and 1800 (×14). Note that `README.md:309` says "The images
are 1800px at q80", which is true of about half of them.

Measured re-encode results across the whole set, long edge capped, progressive,
optimised:

| Cap | q78 | q82 |
|---|---|---|
| 1000px | 2.47 MB (19%) | 2.77 MB (21%) |
| 1200px | 3.39 MB (26%) | 3.80 MB (29%) |
| **1400px** | 4.45 MB (35%) | **5.01 MB (39%)** |
| 1600px | 5.82 MB (45%) | 6.49 MB (50%) |

**This plan uses a 1400px long edge at quality 82.** The reasoning, so you can
defend it in review: 1400px is already the width of three files in the set, so
it is inside the range the set already spans; it stays comfortably above the
largest CSS size any component asks for (~1113 px for a `hero` at 58vw on a
1920 viewport), which matters because Canvas's `image.style.canvas_parametrized_width`
derives everything else from these originals and cannot invent detail; and q82
keeps a margin over the q78 column for photographs that will be reproduced at
full width. The result is 5.01 MB — a 61% cut, better than the 50% the README
estimates.

### The metadata that must stay in step

Three numbers are declared about each image and all three must agree with the
bytes after a re-encode:

1. `filesize` in `content/file/<uuid>.yml`. `tests/lib/orphan-files.py:26-29`
   compares it to the real byte count and `tests/check.sh:565` asserts the
   resulting counter is `0`. Get this wrong and a currently-green assertion
   breaks.
2. `width` and `height` in the image field of `content/media/<uuid>.yml`.
3. `width` and `height` in `field_image` of `content/node/<uuid>.yml` (six
   article nodes carry one each).

A `content/file/*.yml` entity looks like this — `content/file/f1155f91-453c-4208-9fdf-9854ec1e988f.yml`:

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

and a node's image field looks like this — `content/node/3f8fc32d-fc94-4505-8018-4fea6ad12c1a.yml:46-52`:

```yaml
  field_image:
    -
      alt: 'The bench by the window'
      title: ''
      width: 1800
      height: 2685
      entity: f1155f91-453c-4208-9fdf-9854ec1e988f
```

### The photographic brief

`tests/lib/measure-images.py` reports mean luminance, mean saturation and a
saturation-weighted circular mean hue for every JPEG, against an empirical band
of luminance 62–118, saturation 0.22–0.48, hue 18–46. At `fffbe98` the set
scores **15 of 27** inside the band, which `README.md:193-197` records openly.
That script thumbnails each image to 160×160 before measuring
(`tests/lib/measure-images.py:32`), so its three numbers are resolution-
invariant: a re-encode should not move the score. Confirming that it does not
is one of this plan's verifications.

### Repo conventions

- Content YAML is Symfony `Yaml::dump` output at 2-space indent with sequence
  items on their own `-` line. Preserve the exact formatting of every line you
  do not need to change; a reformatting diff across 37 files is unreviewable.
- Helper scripts live in `tests/lib/`, are stdlib+Pillow, take paths as
  positional arguments, and carry a docstring explaining *why* they exist. See
  `tests/lib/orphan-files.py`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Pillow present | `python3 -c "import PIL; print(PIL.__version__)"` | a version string |
| Total JPEG bytes | `du -ch content/file/*.jpg \| tail -1` | `12M` before, `4.8M` after |
| Entity/binary agreement | `python3 tests/lib/orphan-files.py content/file` | `0` |
| Photographic brief | `python3 tests/lib/measure-images.py content/file \| tail -1` | `15 of 27 inside the brief` |
| YAML parses | `python3 -c "import yaml,glob;[yaml.safe_load(open(p)) for p in glob.glob('content/**/*.yml',recursive=True)]"` | exit 0 |

If `import yaml` fails, `python3 -m pip install --user pyyaml`.

This repository has no build, no linter and no runnable test suite; a separate
plan in `plans/` adds one. Every verification here is a direct measurement of
the files.

## Scope

**In scope** (the only files you may modify or create):

- `content/file/*.jpg` — the 27 photographs (re-encoded in place)
- `content/file/*.yml` — `filesize` values only
- `content/media/*.yml` — `width` and `height` values only
- `content/node/*.yml` — `width` and `height` values only
- `tests/lib/restamp-image-metadata.py` (create — the tool that does it)
- `README.md` — the two stale numbers in the "Size" bullet
- `plans/README.md` — status row only

**Out of scope** (do NOT touch, even though they look related):

- `content/file/*.png` (the four logo marks) and `content/file/*.woff2` (the two
  fonts). The logos are line art on transparency where JPEG re-encoding would
  be actively wrong, and the fonts are already subset. Together they are 218 KB
  of a 13 MB problem.
- **`config/canvas.js_component.article_teasers.yml`.** The raw `<img
  src={article.field_image.uri.url}>` in its JSX is the reason the journal index
  serves originals, and it is a genuine defect — but that file is a vendored
  snapshot exported from a separate codebase (see
  `tests/regenerate-components.sh` and `README.md:132-135`). Hand-editing it
  would be overwritten by the next regeneration and would put a human edit into
  a generated file. Record it as a follow-up; do not change it.
- `content/file/recommended-add-ons.yaml`.
- Deleting any photograph, or changing which photograph a page uses. This plan
  re-encodes the existing set and nothing else. The larger question — whether to
  ship stock photography at all, given `README.md:302-307` calls its licensing
  "the real gate" — is a decision for the maintainer, not an executor.
- `alt` and `title` text in any image field.
- `tests/check.sh`, `tests/regenerate-*.sh`.

## Git workflow

- Branch: `advisor/006-image-payload`
- **Two commits, in this order**: first the re-encoded binaries, then the
  metadata restamp. A reviewer can then check the second commit's diff against
  the first commit's files without the binary noise in the way.
- Commit message style is an imperative sentence with no prefix, e.g.
  `Re-encode the photographs at 1400px, and restamp what the content claims about them`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Record the baseline

```
du -ch content/file/*.jpg | tail -1
python3 tests/lib/orphan-files.py content/file
python3 tests/lib/measure-images.py content/file | tail -1
python3 - <<'PY'
from PIL import Image
import glob, os
for p in sorted(glob.glob('content/file/*.jpg')):
    w, h = Image.open(p).size
    print(f"{os.path.basename(p):40s} {w}x{h:<5d} {os.path.getsize(p):>9d}")
PY
```

Expected: `12M` total, `0` orphans, `15 of 27 inside the brief`, and 27 rows.
Save that last table — it is the before-and-after evidence for your report. If
any of the first three differ from the expectation, see STOP conditions.

### Step 2: Write the restamp tool

Create `tests/lib/restamp-image-metadata.py`. It takes the `content/` directory
and rewrites every declared `filesize`, `width` and `height` to match the bytes
on disk. It must edit **only those numbers** — a full YAML round-trip would
reformat all 37 files and bury the real change, so operate on the text with
targeted regular expressions, exactly as `tests/lib/orphan-files.py` reads them.

Follow that file's conventions: module docstring explaining why, stdlib +
Pillow, positional arguments, a printed summary, no argparse.

Behaviour:

1. Build a map of file-entity UUID → (`filename`, absolute path) by scanning
   `content/file/*.yml` for `uuid:` in `_meta` and the `public://…` value.
2. For each `content/file/*.yml`, replace the `filesize` value with the real
   byte count of the file it names.
3. For each `content/media/*.yml` and `content/node/*.yml`, find every block
   that contains a `width:`/`height:` pair followed by an `entity: <uuid>`
   line, look up that UUID, read the real dimensions with Pillow, and replace
   both numbers.
4. Print one line per change (`<yaml> <field> <old> -> <new>`) and a summary
   count. Print nothing for values that were already correct.
5. Exit non-zero if any `entity:` UUID does not resolve to a shipped file.

Do not run it yet.

**Verify**:
- `python3 -m py_compile tests/lib/restamp-image-metadata.py` → exit 0
- Dry run against the **unmodified** tree:
  `python3 tests/lib/restamp-image-metadata.py content --dry-run`
  → reports exactly **11** width/height changes and **0** filesize changes,
  and the 11 match the table in "Why this matters" line for line.

That dry run is the plan's central calibration check. If it reports a different
set, stop — either the repository has drifted or your matcher is wrong, and in
both cases running it for real would corrupt content.

### Step 3: Re-encode the photographs

Cap the long edge at 1400px, quality 82, progressive, optimised, preserving
aspect ratio. Do not upscale anything already smaller. Strip metadata (Pillow's
`save` does not carry EXIF unless asked, which is what we want).

```
python3 - <<'PY'
from PIL import Image
import glob, os
CAP, Q = 1400, 82
total_before = total_after = 0
for p in sorted(glob.glob('content/file/*.jpg')):
    before = os.path.getsize(p); total_before += before
    im = Image.open(p).convert('RGB')
    im.thumbnail((CAP, CAP), Image.LANCZOS)
    im.save(p, 'JPEG', quality=Q, optimize=True, progressive=True)
    after = os.path.getsize(p); total_after += after
    print(f"{os.path.basename(p):40s} {before:>9d} -> {after:>9d}  {im.size[0]}x{im.size[1]}")
print(f"\ntotal {total_before/1024/1024:.2f} MB -> {total_after/1024/1024:.2f} MB")
PY
```

**Verify**:
- The final line reports roughly `12.89 MB -> 5.01 MB`. Anything above 6 MB or
  below 4 MB means the cap or quality was not applied as written — STOP.
- `du -ch content/file/*.jpg | tail -1` → about `4.8M`
- No file grew: every row's second number is smaller than its first.
- `python3 tests/lib/measure-images.py content/file | tail -1`
  → still `15 of 27 inside the brief`. The metric is resolution-invariant, so a
  different number means the re-encode changed the pictures' colour, not just
  their size — STOP.

At this point `python3 tests/lib/orphan-files.py content/file` will report a
large non-zero number, because every declared `filesize` is now wrong. That is
expected and Step 4 fixes it. Commit the binaries here, before the restamp, so
the two changes are separable in review.

### Step 4: Restamp the metadata

```
python3 tests/lib/restamp-image-metadata.py content
```

**Verify**:
- `python3 tests/lib/orphan-files.py content/file` → `0`
- `python3 tests/lib/restamp-image-metadata.py content --dry-run` → reports
  `0` changes (it is idempotent)
- Every declared dimension now matches its file:
  ```
  python3 - <<'PY'
  import re, pathlib
  from PIL import Image
  files = {}
  for y in pathlib.Path('content/file').glob('*.yml'):
      t = y.read_text()
      u = re.search(r'uuid: ([0-9a-f-]{36})', t).group(1)
      m = re.search(r"value: '?public://([^'\n]+)'?", t)
      if m:
          files[u] = 'content/file/' + m.group(1)
  bad = []
  for y in list(pathlib.Path('content/media').glob('*.yml')) + list(pathlib.Path('content/node').glob('*.yml')):
      t = y.read_text()
      for m in re.finditer(r'width: (\d+)\n\s+height: (\d+)\n\s+entity: ([0-9a-f-]{36})', t):
          w, h, u = int(m.group(1)), int(m.group(2)), m.group(3)
          p = files.get(u)
          if p and p.lower().endswith(('.jpg', '.jpeg', '.png')):
              if Image.open(p).size != (w, h):
                  bad.append((y.name, p, (w, h), Image.open(p).size))
  print('dimension mismatches:', bad or 'none')
  PY
  ```
  → `dimension mismatches: none`
- `python3 -c "import yaml,glob;[yaml.safe_load(open(p)) for p in glob.glob('content/**/*.yml',recursive=True)]"` → exit 0
- The diff touches only numbers:
  `git diff -U0 -- content/media content/node content/file/*.yml | grep -E '^[-+]' | grep -vE '^[-+]{3}' | grep -vcE '^[-+]\s*(value|width|height): [0-9]+$'`
  → `0`

### Step 5: Correct the two stale numbers in the README

`README.md:308-311` currently reads:

```
- **Size.** 36MB, of which 13MB is `content/file`. The images are 1800px at
  q80; 1200px roughly halves the payload, and `tests/lib/measure-images.py`
  will tell you whether the set still holds together afterwards.
```

Three things in that are now wrong or were never right: the 36 MB figure is a
clone including a 21 MB `.git`, not the shipped payload; the images were never
uniformly 1800px; and `measure-images.py` cannot tell you anything about a
resize, because it thumbnails to 160×160 before measuring. Replace it with:

```
- **Size.** About 5MB, nearly all of it `content/file`. The photographs are
  capped at a 1400px long edge at q82; they were 1800px and 13MB until
  `plans/006` re-encoded them. Going further is possible — 1200px is 3.8MB and
  1000px is 2.5MB — but each step costs detail on the hero, which is the one
  image reproduced near full width. `tests/lib/measure-images.py` measures the
  set's colour, not its resolution, so it will report the same 15 of 27 at any
  size; it is the wrong tool for judging a resize.
```

Adjust the leading figure to whatever Step 3 actually produced.

**Verify**:
- `grep -c '36MB' README.md` → `0`
- `grep -c '1800px at' README.md` → `0`

## Test plan

There are no automated tests covering `content/` in this repository, so the
verification is the measurement chain above rather than new test files. Record
these four in your report:

1. The before/after dimension-and-size table from Steps 1 and 3.
2. `python3 tests/lib/orphan-files.py content/file` → `0` after Step 4.
3. `python3 tests/lib/measure-images.py content/file | tail -1` before and
   after → identical (`15 of 27 inside the brief`).
4. The Step 4 dimension-mismatch snippet → `none`.

If `plans/004-static-snapshot-validator-and-ci.md` has landed, also run
`tests/lint.sh` and remove the eleven `image-dimensions` lines from
`tests/lib/known-problems.txt` in the same commit — the validator errors on an
allowlist line that no longer matches anything, so leaving them breaks CI.

**A visual check is worth asking for.** These are photographs and the numbers
cannot tell you whether q82 introduced visible artefacts on the two darkest
frames (`atelier-workshop-door.jpg`, `atelier-journal-door.jpg`). If the
operator can look at the produced site, ask them to; if not, say in your report
that no visual check was performed.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `du -ch content/file/*.jpg | tail -1` reports between 4 MB and 6 MB
- [ ] No JPEG in `content/file/` has a long edge greater than 1400 px
- [ ] `python3 tests/lib/orphan-files.py content/file` prints `0`
- [ ] `python3 tests/lib/measure-images.py content/file | tail -1` prints `15 of 27 inside the brief`
- [ ] The Step 4 dimension-mismatch snippet prints `none`
- [ ] `python3 tests/lib/restamp-image-metadata.py content --dry-run` reports 0 changes
- [ ] Every YAML under `content/` parses
- [ ] The Step 4 diff-purity check returns `0` (only numeric values changed)
- [ ] `grep -c '36MB' README.md` returns `0`
- [ ] `git status --porcelain` lists only paths from the Scope list
- [ ] The report names the follow-up left undone (`article_teasers` serving originals) and why
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The Step 2 dry run reports anything other than exactly the eleven
  width/height changes listed in this plan. Do not "fix" the extra ones and do
  not proceed — a matcher that finds twelve is finding something this plan did
  not analyse.
- Step 1's baseline differs: not `12M`, not `0` orphans, or not `15 of 27`.
- After Step 3, `measure-images.py` reports a different score. The re-encode
  should be colour-neutral; a change means quality or colour handling went
  wrong. Restore the binaries with `git checkout -- content/file` and report.
- Total size after re-encoding falls outside 4–6 MB.
- Any `content/*/*.yml` fails to parse, or the diff-purity check finds a
  non-numeric line changed.
- You conclude the fix requires editing `config/canvas.js_component.article_teasers.yml`.
  It does not — that is a separate, out-of-scope follow-up. Report it.
- The operator asks you to delete photographs rather than re-encode them. That
  is a different plan with a different risk profile; stop and get it written.

## Maintenance notes

For the human or agent who owns this next:

- **What a reviewer should scrutinise**: that the metadata commit contains only
  numeric changes (the diff-purity command proves it), that `orphan-files.py`
  is back to `0`, and — if they can — one look at the two darkest photographs
  at full size.
- **This will be undone by a content regeneration.**
  `tests/regenerate-content.sh:38` deletes every `content/file/*.yml` and
  re-exports from a live site, so `filesize` and the dimensions will be
  restamped from whatever that site holds. If the site still has the 1800px
  originals, the numbers come back wrong. Re-upload the re-encoded files to the
  site before the next regeneration, or run
  `tests/lib/restamp-image-metadata.py content` immediately afterwards. Say so
  in the PR description; this is the most likely way this change silently
  reverts.
- **The follow-up this plan deliberately leaves**: `article_teasers` renders
  `<img src={article.field_image.uri.url}>` — the original file — into a
  176×112 box, and it also declares `width="160" height="120"`, which is a
  different aspect ratio from the `h-28 w-44` (112×176 px) it actually
  occupies. Every sibling component uses Canvas's `<Image>` primitive and gets
  a derivative from `image.style.canvas_parametrized_width`; this one does not,
  and its wrapper `config/canvas.component.js.article_teasers.yml` is the only
  one of the five image-rendering wrappers without that image style in its
  dependencies. The fix belongs in the paired React codebase, pushed through
  the Canvas CLI and re-exported — not hand-edited here.
- **Further compression is available and was deliberately not taken**: 1200px
  is 3.8 MB and 1000px is 2.5 MB. If the maintainer resolves the licensing
  question at `README.md:302-307` by replacing or dropping the stock
  photography, revisit the cap at the same time rather than re-encoding twice.
