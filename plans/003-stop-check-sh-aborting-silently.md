# Plan 003: Stop `tests/check.sh` aborting silently, and make its floor, its skip path and its recipe-name handling honest

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fffbe98..HEAD -- tests/check.sh README.md`
> If either file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `fffbe98`, 2026-08-10

## Why this matters

`tests/check.sh` is the only meaningful verification this repository has. It
installs a throwaway Drupal site from the recipe and makes ~136 assertions
about the result. Four defects mean it currently cannot be trusted to tell you
whether it ran, let alone whether it passed.

1. **It can die silently, mid-suite, and never reach its own safety net.** The
   script runs under `set -euo pipefail` (line 18). Several assignments take
   their value from a pipeline containing `grep`. When such a `grep` matches
   nothing it exits 1, `pipefail` propagates that to the pipeline, and `set -e`
   terminates the script at the assignment. The whole tail of the suite — the
   idempotency re-apply, the pass/fail tally, and the assertion-count floor
   that exists precisely to catch "a block died and took its assertions with
   it" — never runs. The script's own comment at lines 692-695 says this class
   of failure has already happened twice.

2. **The assertion floor makes the "optional" browser block mandatory.** Line
   696 sets `expected=128`. With the browser block skipped, the maximum
   reachable count is 115. So a run without the `agent-browser` tool fails with
   *"A block exited early. Do not read the tally above as a pass"* — which
   misattributes the cause. Line 427 claims the opposite: "Skipped rather than
   failed when it is not, so the suite still runs in CI."

3. **The floor is 8 below the real total**, so eight assertions can vanish
   without tripping the guard.

4. **Two assertions hardcode `recipes/atelier`** while the rest of the script
   derives the name. Those two are the *only* checks on the theme-generation
   declaration and on the installer-card wording — and the script's own
   comments (lines 111-116, 241-243) say those two things cannot be caught any
   other way. In any checkout not literally named `atelier` they silently
   report `no`.

Fixing these is a prerequisite for trusting anything else in `plans/`.

## Current state

### The `set -e` abort — verified, not theorised

`tests/check.sh:18`:
```bash
set -euo pipefail
```

`tests/check.sh:645-659`:
```bash
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
```

The `else` branch at 656-659 exists to report a failure when there is no
stylesheet link. It is unreachable: when `grep` finds nothing the script has
already exited. Reproduce it for yourself before you start — this exact script
prints `before`, then exits 1, and never prints `after`:

```bash
cat > /tmp/pf.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
flat="no css link here"
echo "before"
css_href="$(grep -oE 'href="/x/[^"]*"' <<<"$flat" | head -1 | sed 's/href="//')"
echo "after: [$css_href]"
EOF
bash /tmp/pf.sh; echo "EXIT=$?"
```
→ prints `before`, then `EXIT=1`.

**Important distinction.** Command substitution only trips `set -e` when it is
the whole of a simple assignment. The ~70 `check '…' expected "$(ev '…')"`
calls throughout the script pass the substitution as an *argument*, and those
are safe. Only these assignment sites are at risk:

| Line | Assignment |
|---|---|
| 443 | `undecoded="$(probe "…")"` |
| 449 | `heading_paths="$(ev '…' \| tr ',' ' ')"` |
| 465 | `console_out="$(agent-browser … \|\| true)"` — already guarded, leave it |
| 572 | `base_url="$(ev 'print \Drupal::request()->getSchemeAndHttpHost();')"` |
| 587 | `body="$(curl -skL "$base_url/")"` |
| 588 | `flat="$(tr -d '\n' <<<"$body")"` |
| 594 | `menu_json="$(curl -sk "$base_url/jsonapi/menu_items/main")"` |
| 623 | `article_url="$(ev '…')"` |
| 645 | `css_href="$(… \| head -1 \| sed …)"` |
| 648 | `agg="$(curl -sk "$base_url$css_href")"` |
| 666 | `before_links="$(ev '…')"` |
| 667 | `before_nodes="$(ev '…')"` |

Line 471 already shows the intended idiom:
```bash
    errors="$(printf '%s' "$console_out" | grep -c . | tr -cd '0-9' || true)"
```
with its comment: *"`grep -c .` prints 0 and exits 1 on empty input, which
under `pipefail` kills the whole suite rather than reporting zero errors."* The
author found this once and fixed it in one place. Apply the same idiom
everywhere.

### The floor and the block sizes

`tests/check.sh:689-703`:
```bash
echo
echo "$pass passed, $fail failed"

# A block that dies early takes its assertions with it, and the tally cannot
# tell "did not run" from "passed" -- this suite has twice reported 0 failed
# with a third of it silently skipped. Assert the count itself. Raise the floor
# when you add assertions; lower it only when you delete some on purpose.
expected=128
if (( pass + fail < expected )); then
  echo "Only $(( pass + fail )) assertions ran, expected at least $expected." >&2
  echo "A block exited early. Do not read the tally above as a pass." >&2
  exit 1
fi

exit $(( fail > 0 ? 1 : 0 ))
```

The counts, derived by expanding every `check` call site including loops
(80 call sites; the pairs at 76/83 and 650-658 are mutually exclusive so each
contributes 1 and 2 respectively):

| Block | Guard | Assertions |
|---|---|---|
| Always runs | — | **86** |
| Browser block | `tests/check.sh:428` — `command -v agent-browser` **and** `SITE_URL` | **21** |
| HTTP block | `tests/check.sh:575` — non-empty `base_url` | **29** |
| **Total** | | **136** |

The 86 is: 42 single-shot calls, plus loops of 11 (modules, line 131), 5
(config names, line 159), 2 (page regions, line 266), and 9×2 (pages, line
333). The browser block's 21 is 9 fixed plus a 12-iteration heading loop (line
455: the 10 published Canvas page aliases, plus `/contact/enquiry` and
`/notes-bench-joinery-without-fixings` appended at line 454). The HTTP block's
29 is 14 paths + 3 + 3 + 7 singles + 2 from the mutually-exclusive pair.

So: browser skipped → 115 max. Both skipped → 86 max. Floor 128. Neither skip
path can pass.

### The hardcoded recipe name

`tests/check.sh:20-22` derives it properly:
```bash
DRUSH="${DRUSH:-drush}"
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPE_NAME="$(basename "$RECIPE_DIR")"
```

and `tests/check.sh:84` uses it:
```bash
    "$(ev "print \Drupal\Core\Recipe\Recipe::createFromDirectory(DRUPAL_ROOT . '/../recipes/$RECIPE_NAME')->type;")"
```

but `tests/check.sh:118` and `tests/check.sh:245` do not:
```bash
    "$(ev '$composer = json_decode(file_get_contents(DRUPAL_ROOT . "/../recipes/atelier/composer.json"), TRUE);
```
```bash
    "$(ev '$recipe = \Symfony\Component\Yaml\Yaml::parse(file_get_contents(DRUPAL_ROOT . "/../recipes/atelier/recipe.yml"));
```

Both are inside **single-quoted** shell strings, so `$RECIPE_NAME` will not
interpolate as-is. Converting them needs care with quoting — see Step 4.

### `README.md:621`

```
There is also `tests/check.sh` — 133 assertions, with a floor of 127 — which is not a substitute for
```

Both figures are wrong (136 and 128 today; 136 and 136 after this plan).

### Repo conventions

- Comments explain *why*, in full sentences, and frequently record the specific
  incident that motivated the code. Match that register — see lines 692-695,
  463-464 and 537-539 for the house style.
- Assertions are `check '<lowercase label>' <expected> "<actual>"` with the
  label padded to 52 columns by the helper at line 30. Keep labels short.
- `ev()` (line 39) runs PHP through Drush and strips all whitespace from the
  result.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Syntax check | `bash -n tests/check.sh` | exit 0, no output |
| Count assertion sites | `grep -c '^\s*check ' tests/check.sh` | `80` before, `79` after Step 5 |
| Static shell review | `shellcheck tests/check.sh` | see note below |
| Confirm no bare `atelier` path | `grep -n 'recipes/atelier' tests/check.sh` | no matches |

`shellcheck` is not installed in this environment and there is no lint config
in the repository. If it is unavailable, rely on `bash -n` and say in your
report that shellcheck was not run. Do **not** add it as a dependency here.

**You cannot run the suite end-to-end as part of this plan.** It requires a
disposable Drupal site, `drush`, and a destructive `site:install`
(`tests/check.sh:6-7`). Every verification below is therefore static. That is a
real limitation of this change and you must state it plainly in your report
rather than implying the suite was exercised.

## Scope

**In scope** (the only files you may modify):

- `tests/check.sh`
- `README.md` — line 621 only
- `plans/README.md` — status row only

**Out of scope** (do NOT touch, even though they look related):

- `tests/regenerate-components.sh` and `tests/regenerate-content.sh`. They have
  the same hardcoded-path problem and it is addressed by a different plan in
  `plans/`; those scripts are destructive and changing them here would put an
  unreviewable risk into a test-harness commit.
- `tests/lib/*.py`.
- Adding, deleting or weakening any *assertion's logic*. This plan changes how
  the script survives and how it counts, not what it checks. The one exception
  is the duplicate at lines 514-515, which Step 5 deletes.
- `recipe.yml`, `config/`, `content/`. If a fix here reveals a product bug,
  report it; do not fix it in this commit.
- Any attempt to port assertions to PHPUnit. Separate concern, separate plan.

## Git workflow

- Branch: `advisor/003-check-sh-honesty`
- Commit per step, or one commit per numbered defect — the steps are
  independent and a reviewer will thank you for the separation.
- Commit message style (imperative sentence, no prefix), e.g.
  `Stop the check suite exiting at a grep that found nothing`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Make every pipeline-valued assignment survive an empty match

For each line in the table above (except 465, which is already guarded), append
`|| true` inside the command substitution so the assignment always succeeds and
the emptiness is handled by the code that follows.

Concretely, line 645 becomes:

```bash
  css_href="$(grep -oE 'href="/sites/default/files/css/[^"]*"' <<<"$flat" \
    | head -1 | sed 's/href="//; s/"$//; s/&amp;/\&/g' || true)"
```

Apply the same to lines 443, 449, 572, 587, 588, 594, 623, 648, 666, 667.

Then add a comment above the first one you touch, in the house style:

```bash
# Every assignment below takes its value from a pipeline, and `set -euo
# pipefail` turns a grep that matched nothing into a dead suite -- the tally
# and the floor below never run, so the failure reads as silence. `|| true`
# lets the emptiness reach the code written to handle it.
```

Also make the `probe` helper (line 432) fail soft, since three bare calls at
lines 441, 478 and 494 discard its output and would abort the suite if the
browser session has died:

```bash
  probe() { agent-browser --session atelier-check eval "$1" 2>/dev/null | tr -d '"' || true; }
```

**Verify**:
- `bash -n tests/check.sh` → exit 0
- `grep -c '|| true' tests/check.sh` → at least `12`
- No assignment from a pipeline lacks a guard:
  ```
  grep -nE '^\s*[a-z_]+="\$\(' tests/check.sh | grep -v '|| true' | grep -v 'console_out'
  ```
  → no output

### Step 2: Count the blocks at runtime and derive the floor from what ran

Replace the fixed `expected=128` with a floor assembled from the blocks that
actually executed.

Near the top of the script, after `fail=0` (line 25), add:

```bash
# The floor below is assembled from the blocks that actually ran. A fixed
# number made the optional browser block mandatory: without it the suite can
# reach 115 assertions and the floor was 128, so "skipped" reported as "a block
# exited early" and the message pointed at the wrong thing.
floor_base=86
floor_browser=21
floor_http=29
ran_browser=0
ran_http=0
```

Set `ran_browser=1` as the first statement inside the `if` at line 428, and
`ran_http=1` as the first statement inside the `if` at line 575.

Then replace lines 696-701 with:

```bash
expected=$floor_base
(( ran_browser )) && expected=$(( expected + floor_browser ))
(( ran_http )) && expected=$(( expected + floor_http ))
if (( pass + fail < expected )); then
  echo "Only $(( pass + fail )) assertions ran, expected at least $expected" >&2
  echo "for the blocks that were enabled (browser=$ran_browser http=$ran_http)." >&2
  echo "A block exited early. Do not read the tally above as a pass." >&2
  exit 1
fi
if (( pass + fail > expected )); then
  echo "$(( pass + fail )) assertions ran, expected $expected." >&2
  echo "Assertions were added without updating floor_base/floor_browser/floor_http." >&2
  exit 1
fi
```

The upper bound is the point: the old floor drifted 8 below the real count
because it was only ever raised by hand and only sometimes. An exact match
turns the counter into a real invariant.

Print what was skipped, so the operator can see it. Extend the existing
`else` at line 517-519:

```bash
else
  echo "    (skipped $floor_browser browser checks: agent-browser or SITE_URL unavailable)"
fi
```
and the one at 661-663 similarly, naming `$floor_http`.

**Verify**:
- `bash -n tests/check.sh` → exit 0
- `grep -c 'floor_base\|floor_browser\|floor_http' tests/check.sh` → at least `10`
- `grep -c 'expected=128' tests/check.sh` → `0`

### Step 3: Correct the comment that claims the skip path works

`tests/check.sh:426-427` currently reads:

```bash
# Every component here hydrates in the browser, so curl proves only that the
# server emitted a custom element: a component that throws on mount still ships
# green. If a browser is available, mount the front page and read the DOM back.
# Skipped rather than failed when it is not, so the suite still runs in CI.
```

Replace the last sentence with one that is true after Step 2:

```bash
# Skipped when it is not, and the floor below drops by the number skipped, so
# the suite still runs -- it just covers less and says so.
```

**Verify**: `grep -c 'so the suite still runs in CI' tests/check.sh` → `0`

### Step 4: Use `$RECIPE_NAME` in the two hardcoded assertions

Both are inside single-quoted shell strings, so the fix is a quoting change,
not just a text substitution. Follow the pattern already used at line 84 and at
lines 344-345: switch the outer quotes to double, and escape every `$` that
belongs to PHP rather than to the shell.

Line 117-124 becomes:

```bash
check 'shell theme is declared for generation' yes \
  "$(ev "\$composer = json_decode(file_get_contents(DRUPAL_ROOT . '/../recipes/$RECIPE_NAME/composer.json'), TRUE);
    \$generated = \$composer['extra']['drupal-site-template']['generate-theme'] ?? [];
    \$default = \Drupal::config('system.theme')->get('default');
    \$declares = (\$generated['name'] ?? NULL) === \$default;
    \$hasRegions = !empty(\$generated['info']['regions']);
    \$requiresHelper = isset(\$composer['require']['drupal/site_template_helper']);
    print \$declares && \$hasRegions && \$requiresHelper ? 'yes' : 'no';")"
```

Note that every PHP string literal inside had to move from `"` to `'` because
the outer shell quoting is now double. Do the same for lines 244-258.

**This is the highest-risk edit in the plan.** A quoting mistake produces a PHP
parse error, `ev` swallows stderr (`2>/dev/null` at line 39), and the assertion
silently reports the wrong value — which is exactly the failure mode the commit
`cfc17de` message records ("`''` inside a single-quoted shell string ended the
quoting so the PHP never parsed and the check reported a ParseError rather than
a count"). Verify by extracting and syntax-checking the PHP, not by eye.

**Verify**:
- `bash -n tests/check.sh` → exit 0
- `grep -n 'recipes/atelier' tests/check.sh` → no matches
- Extract and lint the PHP of both assertions:
  ```
  bash -c 'RECIPE_NAME=atelier; source /dev/stdin <<EOF
  ev() { printf "%s" "\$1" > /tmp/a.php; php -l /tmp/a.php; }
  EOF
  ' 2>/dev/null || echo "manual check required"
  ```
  If that is awkward in your environment, do it the direct way: copy each PHP
  body into `/tmp/a.php` with a leading `<?php`, run `php -l /tmp/a.php`, and
  confirm `No syntax errors detected`. `php` is available.

### Step 5: Delete the duplicate 360px assertion

`tests/check.sh:505-515`:

```bash
  overflow=ok
  for op in / /studio /journal /faq /contact /contact/enquiry /services/commissions /notes-bench-joinery-without-fixings; do
    …
  done
  check 'no page overflows a 360px viewport' ok "$overflow"
  check 'no horizontal overflow at 360px' yes \
    "$(probe "document.documentElement.scrollWidth <= window.innerWidth ? 'yes' : 'no'")"
```

The second `check` re-tests whatever page the loop left open — always
`/notes-bench-joinery-without-fixings` — with a weaker predicate
(`window.innerWidth` includes the scrollbar; `clientWidth` does not). Delete
lines 514-515 and decrement `floor_browser` from 21 to 20.

While you are here, make the loop report every offender instead of only the
last. Change the assignment inside the loop from
`overflow="overflows on $op"` to `overflow="${overflow%ok} overflows on $op"`
— or any accumulation you prefer — so a run that fails on three templates names
three. Keep the expected value `ok`.

**Verify**:
- `bash -n tests/check.sh` → exit 0
- `grep -c '^\s*check ' tests/check.sh` → `79`
- `grep -c 'no horizontal overflow at 360px' tests/check.sh` → `0`
- `grep -n 'floor_browser=' tests/check.sh` → `floor_browser=20`

### Step 6: Recount, and update the README

Recount the assertion sites after Step 5 by expanding the loops by hand exactly
as the table in "Current state" does, and confirm `floor_base + floor_browser +
floor_http` equals the total. If Step 5 was the only assertion removed, the
numbers are 86 / 20 / 29 = **135**.

Then update `README.md:621`. It currently reads:

```
There is also `tests/check.sh` — 133 assertions, with a floor of 127 — which is not a substitute for
```

Replace the two numbers with the totals you computed, and say what the floor
now means:

```
There is also `tests/check.sh` — 135 assertions, of which 20 need a browser and
29 need HTTP access, and the suite asserts the count of whatever ran — which is
not a substitute for
```

**Verify**:
- `grep -c '133 assertions' README.md` → `0`
- `grep -c 'floor of 127' README.md` → `0`

## Test plan

There are no unit tests for a bash script here and adding a bash test
framework is out of scope. Instead, prove the two behavioural fixes with
throwaway reproductions and paste both transcripts into your report:

1. **The `set -e` fix.** Run the `/tmp/pf.sh` reproduction from "Current state"
   both with and without `|| true` on the assignment. Expected: without it,
   `before` then `EXIT=1`; with it, `before` then `after: []` then `EXIT=0`.

2. **The floor arithmetic.** Extract the new floor block into a scratch script,
   set `pass`/`fail`/`ran_browser`/`ran_http` by hand, and confirm all four
   cases: browser+http (expect 135), http only (expect 115), neither (expect
   86), and one assertion short of each (expect exit 1 with the new message
   naming which blocks ran).

Do not run `tests/check.sh` itself. It is DESTRUCTIVE and needs a disposable
site; if the operator has one and asks for a real run, that is a separate
follow-up.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n tests/check.sh` exits 0
- [ ] `grep -n 'recipes/atelier' tests/check.sh` returns no matches
- [ ] `grep -c 'expected=128' tests/check.sh` returns `0`
- [ ] `grep -c 'so the suite still runs in CI' tests/check.sh` returns `0`
- [ ] `grep -c '^\s*check ' tests/check.sh` returns `79`
- [ ] `grep -nE '^\s*[a-z_]+="\$\(' tests/check.sh | grep -v '|| true' | grep -v console_out` returns nothing
- [ ] `floor_base + floor_browser + floor_http` in the file equals the hand-recount, and the script errors when the total exceeds it
- [ ] `php -l` reports no syntax errors for both rewritten PHP bodies from Step 4
- [ ] `grep -c '133 assertions' README.md` returns `0`
- [ ] `git status --porcelain` lists only `tests/check.sh`, `README.md`, `plans/README.md`
- [ ] The report states explicitly that the suite was not executed end-to-end, and why
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The hand recount in Step 6 does not equal 135. Report your per-block numbers
  and the discrepancy; do not adjust `floor_*` to whatever makes it pass — that
  is precisely the drift that produced the 128-versus-136 gap.
- `php -l` reports a syntax error you cannot resolve in one attempt on either
  Step 4 body. Revert that hunk and report; a silently mis-parsed assertion is
  worse than a hardcoded path.
- `tests/check.sh` at HEAD does not contain `expected=128` at line 696, or the
  browser/HTTP guards are no longer at lines 428 and 575.
- You find that an assertion you did not intend to touch changed behaviour.
- You are tempted to make the browser block non-optional, or to delete it. Both
  are out of scope; the block covers hydration failures nothing else can see.

## Maintenance notes

For the human or agent who owns this next:

- **The floor is now an equality, not a floor.** Anyone adding an assertion
  must bump the matching `floor_*` constant in the same commit or the suite
  fails loudly. That is the intent — the old one-sided floor drifted eight
  assertions below reality precisely because forgetting cost nothing. Say so in
  the PR description so the next contributor is not surprised.
- **What a reviewer should scrutinise**: the Step 4 quoting (run `php -l`, do
  not read it), that no `check` label or expected value changed, and that
  `floor_base` was recounted rather than back-fitted.
- **What will interact with this**: any plan that adds assertions to
  `tests/check.sh` — including the enquiry-form and snapshot-validator plans in
  `plans/` — must update the same constants. Sequence those after this one.
- **Deliberately deferred, and worth its own plan**: the assertion at lines
  201-225 (`component classes resolve in the CSS build`) passes vacuously if
  its extraction regex matches nothing, which is the same fail-open shape the
  comment at lines 191-192 describes for a previous assertion. It needs a
  companion assertion that the extracted class corpus is non-empty. The
  per-page tree counts at lines 333-341 are change detectors that the script
  itself admits (lines 537-539) "have never once constrained anything" — worth
  replacing with structural invariants. Neither is in scope here because both
  change what is asserted, not whether the suite survives.
