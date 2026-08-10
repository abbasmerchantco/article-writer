---
name: step-2-research
description: Step 2 of the article-writer workflow — Research deeply. Maps the territory, traces claims to primary sources, actively hunts disconfirming counter-evidence, triangulates across genuinely INDEPENDENT sources, and binds every claim to a source AND a quality tier under the §6 source policy. Records research.claims[], research.open_questions[], and an updated-but-still-PROVISIONAL hypothesis, then passes the "Key claims sourced + counter-evidence found?" gate via gate-counter.sh. Use when a run has passed Step 1 and /write-article continue is resuming it at current_step 1 / status step-1.
allowed-tools: Read, Edit, Bash, WebSearch, WebFetch
---

# Step 2 — Research deeply

Build the evidence base the whole article will stand on. Go **wide-but-shallow
first**, then deep on what bears weight. Actively look for the case *against* your
hypothesis, not just for it — the point of research here is to earn the thesis, not
to decorate a foregone conclusion. Do **not** write the outline or the draft; that is
Step 3 onward. The hypothesis stays **provisional** through this whole step.

## Entry precondition

**Root note:** every `input/`, `interim/`, `output/` path in this skill is relative to
this run's root `<root>` (its `state.json.paths.root`, or the current working directory
for a pre-`output_root` run) — the orchestrator that dispatched you already resolved it
to find this run; use that same value. See `commands/write-article.md` § *Resolving the
run root*.

- Step 1 passed: this run's `state.json` (at `<root>/interim/<run_id>/state.json`) is at
  `current_step: 1`, `status: step-1`, with `scope.reconciled` populated and
  `hypothesis.text` set, `hypothesis.hardened_to_thesis: false`.
- Read `state.json` now — the reconciled scope, the provisional hypothesis, the
  audience/purpose, and the active `controls` (esp. `source_policy` and
  `source_quality_threshold`). The narrowed topic in `scope.reconciled` bounds what
  you research — cover the **article's scope**, not the entire subject.
- If `hypothesis.text` is null or Step 1's gate has not passed, stop and return to
  Step 1; do not research against an unset scope.

## Step 0 — Check `research_mode` first (post_category rigor tier)

Step 1 already resolved `controls.research_mode` from the run's `post_category`
(requirements §2.4, §4 Step 1). **Read it before doing anything else** — it decides
which of the three subprocesses below you run. Never default to the heaviest one just
because it's what this step used to always do.

- **`research_mode: "none"`** (reflective tier — musings / photos / travel): skip
  straight to *Mode: reflective — capture, don't research* below. Do not call
  `WebSearch`/`WebFetch` at all for this run.
- **`research_mode: "spot-check"`** (light-check tier — learnings / movies / books /
  mba): use *Mode: spot-check — verify the named facts, nothing else* below.
- **`research_mode: "deep"`** (journalistic tier — deep-dive, or absent on a
  pre-existing run for backward compatibility): use *Mode: deep — the full
  subprocess* below (everything in this file from "Step 0 — Check independent source
  access" onward, unchanged).

---

### Mode: reflective — capture, don't research

There is nothing here to independently verify — this is the human's own account,
opinion, or memory, not a claim resting on outside evidence. Do **not** manufacture
research to satisfy a gate that doesn't fit the content:

1. Read `scope.reconciled` and the completed scope template for the material to draft
   from (must-include points, angle, any specific memories/details the human already
   gave you).
2. Set `research.claims = []` and `research.open_questions = []` — unless the human's
   own template flagged something they explicitly want fact-checked (e.g. a date they
   weren't sure of inside an otherwise personal piece), in which case record *only*
   that as a claim and check it, still without going into full triangulation mode.
3. Leave `hypothesis.text` as Step 1 set it (a personal piece doesn't need a thesis
   "hardened" against counter-evidence the way an argumentative one does).
4. **Exit gate for this mode: "Is there enough personal detail/context captured to
   draft from?"** — not "sourced + counter-evidence found." Pass immediately once
   there's enough material; do not hold this gate open waiting for sourcing that will
   never come.
5. Pass via `gate-counter.sh ... step-2 pass` as usual (see *Exit gate* below), and
   record `research.open_questions` noting, honestly, that external research was
   skipped **by design** for this `post_category` — not because source access was
   unavailable. This distinction matters for the manifest (§11 honest-degradation):
   "skipped, none needed" is not the same claim as "attempted, unavailable."

Skip *Source policy*, *Source-independence requirement*, *Stop when* / *Probe further
when*, and *Capture structured references* below entirely for this mode — there is no
research to police.

### Mode: spot-check — verify the named facts, nothing else

The piece will state a small number of hard, checkable facts (a film's release year
and director, a book's author and publication year, a named framework/tool/technique,
a course or case-study name) alongside the human's own opinion/experience, which is
not itself a claim to verify. Trim the full subprocess down to just those facts:

1. From `scope.reconciled` and the draft material, list the specific named facts that
   will appear in the piece. Opinions, evaluations, and personal experience are not on
   this list.
2. Look each one up directly and confirm it — one reasonably reliable source per fact
   is enough. Still obey the hard domain blocks in
   `${CLAUDE_PLUGIN_ROOT}/config/source-policy.json` (never cite a blocked domain), but
   you do **not** need to triangulate multiple independent sources, hunt disconfirming
   evidence, seek saturation, or map the wider territory — none of that applies to a
   review/notes piece whose substance is the human's own take.
3. Record each spot-checked fact in `research.claims[]` with its source and tier as
   usual (so `source-check.sh` and the manifest still see it), but do not require
   `independent: true` corroboration — a single admissible source per fact is
   sufficient at this tier.
4. If a named fact can't be confirmed, record it in `research.open_questions[]` as
   unsupported (routes per §5.2 same as always) rather than blocking on it forever.
5. **Exit gate for this mode: "Are the handful of checkable facts confirmed?"** — not
   the full "counter-evidence found" bar. There is no thesis to stress-test with an
   opposing case; there's a film/book/technique to get the facts right about.

Skip the full *Stop when* / *Probe further when* saturation-seeking criteria and the
*Source-independence requirement*'s multi-source corroboration below for this mode —
apply the *Source policy* (hard blocks) and *Documentation requirement* (paraphrase,
attach source+tier) sections as normal, just scoped to the short fact list above.

### Mode: deep — the full subprocess

Unchanged. Continue with *Step 0 — Check independent source access* below and every
section through *Outputs*, exactly as this file has always specified.

---

## Step 0 — Check independent source access (do this first)

Steps 2 and 8 require **independent source access** (web search / fetch or an
equivalent fact-check capability) — a *precondition*, not a control (requirements
§2.5). Before researching:

- Confirm you can actually reach external sources (WebSearch / WebFetch here).
- **If you cannot**, you may only check the **internal consistency** of what you
  already have — you cannot verify external truth. Do **not** imply verification you
  did not perform. In that case: mark affected claims `independent: false`, record the
  limitation in `research.open_questions[]` (e.g. "no independent source access —
  claims unverified against external sources"), and carry this honesty forward so the
  Step 8 manifest can state that only internal consistency was checked. See *Honesty
  on source access* below.

## Actions (the research subprocess)

1. **Map the territory wide-but-shallow first.** Get the lay of the land before
   drilling — identify the sub-questions the article's scope actually contains.
2. **Go to primary sources; trace claims to their root.** Follow every load-bearing
   claim back to the actual study / dataset / filing / official record behind it, not
   the outlet that repeated it.
3. **Actively hunt disconfirming evidence.** Find the *strongest* opponent of the
   hypothesis and state their best case from evidence. Confirmation-only research
   fails this step.
4. **Triangulate across independent sources.** Corroborate load-bearing claims with
   multiple sources that are genuinely different origins (see *Source-independence*).
5. **Capture as you go** — one claim at a time, each bound to its source and tier,
   organized around questions/claims (see *Documentation requirement*).

## Source policy (obey §6 — whitelist / blacklist / tiering)

**The canonical whitelist, blacklist, and tiering rule live in one file — read it and
obey it:** `${CLAUDE_PLUGIN_ROOT}/config/source-policy.json`. Do not rely on a remembered
copy; open it at the start of research so you are working from the current policy. The
same file is what `source-check.sh` enforces deterministically, so there is exactly one
source of truth.

Every claim gets **both** a source **and** a quality tier. Follow the run's
`controls.source_policy` / `source_quality_threshold`; absent overrides, the file's
defaults apply. In short (the file is authoritative):

- **Whitelist (`whitelist.categories`) — actively prefer:** peer-reviewed research /
  meta-analyses; reputable editorially-accountable journals & publications; primary data
  and official statistics/records; reputable independent long-form journalism; the primary
  document behind a claim.
- **Blacklist (`blacklist.categories`) — never load-bearing:** blogs / opinion posts;
  marketing / PR / promotional; propaganda (government *or* corporate); content farms /
  SEO / undated aggregators; circular sources; forums / social posts (usable only as
  **leads** to trace to a primary source).
- **Tiering (`tiering.rule`):** a **load-bearing** claim must rest on a whitelisted,
  sufficiently high tier meeting `source_quality_threshold`. If only a blacklisted or
  low-tier source exists, that claim is **unsupported** — do not treat it as established;
  record it (with `tier` reflecting the weak source), add it to
  `research.open_questions[]`, and let it be independently re-sourced or cut (routes §5.2).
- **Hard domain blocks (`blocked_domains` / `blocked_url_patterns`):** sources on these
  domains (e.g. Reddit, Quora, LinkedIn, Wikipedia, Medium, social platforms) are
  **rejected outright** for *any* claim, load-bearing or not — never cite them. You may
  still read them privately as a **lead** to find the primary source, then cite that
  primary source. `source-check.sh` enforces these blocks; prefer `preferred_domains`
  (e.g. `.gov`, `.edu`, primary research/records) when choosing among candidates.

## Source-independence requirement

For any claim supported by "multiple" sources, verify the sources are **genuinely
independent origins** — not the same wire story, press release, or single study
re-published under different mastheads (a circular source, §6.1). Only mark a claim
`independent: true` when at least two truly separate origins corroborate it. If the
corroboration collapses to one origin, set `independent: false` and treat the claim as
still needing verification.

## Stop when

- **Saturation** — new sources stop surprising you; you keep landing on what you
  already have.
- **Every part of the thesis is arguable from evidence**, *including its objections* —
  you can state both the case for and the strongest case against.
- **The article's scope is covered** — the narrowed slice from Step 1, not the whole
  topic. Do not over-research beyond scope.

## Probe further when

- A **surprise** — a finding that contradicts your expectation.
- A **source conflict** — two credible sources disagree; resolve or record the tension.
- A **load-bearing claim** — anything the thesis rests on gets extra confirmations.
- An **unsourced "everyone knows"** consensus — a claim asserted without a traceable
  origin. Trace it or downgrade it.

## Documentation requirement

- **Paraphrase in your own words** — both for comprehension and as a plagiarism
  defense. Do not paste source prose as your notes.
- **Attach a source AND a quality tier to every claim** — no bare claims.
- **Keep facts, sources, and your own thinking visibly separate** — never let your
  inference blur into what a source actually said.
- **Organize notes around questions/claims, not sources** — one entry per claim (with
  its source + tier), grouped by the sub-question it answers, so the structure step can
  map claim → evidence directly.

## Capture structured references (for citations)

Notes alone aren't enough to *format* citations later. For every distinct source you
actually **cite**, capture structured bibliographic metadata now so Step-8 formatting can
render it deterministically in any style — you gather the fields; you do **not** choose the
style.

- **Build `research`/`state.references[]`** — one entry per distinct cited source, each:
  `{ "id": "<stable-slug, e.g. yasuoka2011>", "authors": ["Last, F. M.", ...],
  "year": "2011", "title": "...", "container": "<journal / site / publisher container>",
  "publisher": "...", "url": "...", "accessed": "<ISO date>", "tier": "..." }`.
  - `authors` in **`Last, F. M.`** form; an **organisation** is a single string with **no
    comma** (e.g. `"Smithsonian Magazine"`).
  - Capture enough to format the reference in **any** scheme (APA / MLA / Chicago / IEEE /
    etc.) — `authors`, `year`, `title`, `container`, `publisher`, `url` are the load-bearing
    fields; fill what the source actually provides.
  - `id` is a **stable slug** (e.g. `yasuoka2011`) reused as the in-text citation key; keep
    it distinct per source.
- **Link every claim to its reference** — set each `research.claims[].ref_id` to the `id`
  of the `references[]` entry that source it, so in-text citations can be generated from the
  claim → reference binding.
- **The style is already chosen.** `controls.citation_style` was set in **Step 1** (a human
  choice); Step 2 does **not** pick it. Your job is only to gather the fields that style
  will need — capture generously so no scheme is starved of a field.
- **Honesty rule still binds (§6 tiering).** A claim whose only source is
  blocked / blacklisted / below `source_quality_threshold` stays **unsupported** — it does
  **not** get promoted into a `references[]` entry used as **load-bearing**. Record it as an
  open question and let it be re-sourced or cut (per *Source policy* above); only genuinely
  citable sources earn a reference.

## Honesty on source access (§2.5)

Independent sourcing checks **external truth**; without it you can check only
**internal consistency**. If independent source access was unavailable (Step 0), or a
given claim could only be checked for internal consistency, **say so** — set
`independent: false`, note the limitation in `research.open_questions[]`, and never
phrase a claim as verified when it was only checked for consistency. This honesty is
load-bearing: the Step 8 manifest must be able to state which guarantee was actually
obtained, and it can only do that if this step recorded the truth.

## Exit gate — "Key claims sourced + counter-evidence found?"

**This is the `research_mode: "deep"` gate question.** The `reflective` and
`spot-check` modes above use their own, lighter gate question instead (see *Step 0 —
Check `research_mode` first*) — do not hold a reflective or spot-check run to this
full bar. What follows applies to `deep` mode only.

The gate passes only when **every load-bearing claim rests on a sourced, sufficiently
tiered whitelisted source**, *and* you have genuinely surfaced the counter-evidence /
strongest opposing case — not merely confirmed the hypothesis. If key claims are still
unsourced, rest on blacklisted/low tiers, or no disconfirming evidence was sought, the
gate fails.

Record the gate result deterministically — the counter is mutated **only** by the
script, never by your free text:

- **On pass:**
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-2 pass
  ```
  Then write the outputs (below), advance `current_step` to `2`, and set `status` to
  `step-2` (moving toward Step 3) per the state contract.

- **On fail:**
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-2 fail
  ```
  The script returns either `RETRY <n>` — loop back **within Step 2** to research more
  (source the unsourced claims, hunt the missing counter-evidence, replace low-tier
  sources) and re-test the gate — or, at the cap, `ESCALATE step-1`.

**The script's output is AUTHORITATIVE — obey it** (architecture-decision: the number lives
in code you don't run; you cannot obtain permission to loop past the cap). On
`RETRY <n>`, loop **once** and re-test — do not loop past a RETRY. On `ESCALATE step-1`,
the scope may be unresearchable as framed: **go back to Step 1** to re-narrow or
re-angle the scope; do **not** loop a 4th time in Step 2, and do **not** self-mutate any
counter (`gates.*`, `escalation_history` are owned by `gate-counter.sh` alone).

## Outputs (written on pass)

Write to `interim/<run_id>/state.json`:

- `research.claims[]` — one entry per claim, each
  `{ "claim": str, "source": str, "tier": str, "independent": bool, "ref_id": str }`. Every
  claim has a source and a tier; `independent` is `true` only when genuinely independent
  origins corroborate it (per *Source-independence* and *Honesty on source access*);
  `ref_id` links the claim to its `references[]` entry (per *Capture structured references*).
- `references[]` — one structured bibliographic entry per distinct **cited** source, each
  `{ "id": str, "authors": [str], "year": str, "title": str, "container": str,
  "publisher": str, "url": str, "accessed": str, "tier": str }` (per *Capture structured
  references*). Basis for the citations `controls.citation_style` will render in Step 8;
  blocked / blacklisted / low-tier-only sources are **not** promoted here as load-bearing.
- `research.open_questions[]` — unresolved questions, source conflicts left open,
  claims still unsupported / needing independent re-sourcing, and any source-access
  limitation from Step 0.
- `hypothesis.text` — the hypothesis **updated or confirmed** against the findings, but
  still framed as a working hypothesis / central question. In `reflective` mode this
  is simply left as Step 1 set it.
- `controls.research_mode`/`controls.rigor_tier` — carried through unchanged from
  Step 1; this step reads them, it does not set them.
- `hypothesis.hardened_to_thesis` — **stays `false`.** Hardening into a settled thesis
  happens in **Step 3**, after research, never here.
- `current_step = 2`, `status = "step-2"` (or as your orchestrator advances it toward
  Step 3), and `updated_at` bumped.

**Counter fields (`gates.*`, `escalation_history`) are mutated ONLY by
`gate-counter.sh`** — never write them from free text (contracts §3, §4).
