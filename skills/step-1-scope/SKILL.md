---
name: step-1-scope
description: Step 1 of the article-writer workflow — Define scope as a human-agent handshake. Reads the human-completed scope template, hard-stops if a mandatory field (audience or purpose) is blank, reconciles the human spec with agent proposals for blank optional fields, flags tensions, narrows the topic, sets a PROVISIONAL working hypothesis, and passes the "one clean sentence?" gate via gate-counter.sh. Use when a run is at status awaiting-scope and /write-article continue is resuming it.
allowed-tools: Read, Edit, Bash, AskUserQuestion
---

# Step 1 — Define scope (shared human-agent responsibility)

Scope is a **handshake**, not agent-only work. The audience, purpose, preferred
angle, and constraints live only in the human's head — you must not invent them.
Your job is to reconcile what the human wrote with what you can stress-test, and to
set a *provisional* working hypothesis. Do not begin research or writing here.

## Entry precondition

**Root note:** every `input/`, `interim/`, `output/` path in this skill is relative to
this run's root `<root>`, not necessarily the current working directory. Whatever
dispatched you (`write-article.md` / the orchestrator) already resolved `<root>` to find
this run in the first place — use that same value throughout (it also lives in
`state.json.paths.root` once you read that file, for a pre-`output_root` run with no such
field, fall back to the current working directory). See `commands/write-article.md` §
*Resolving the run root*.

- The human has completed `<root>/input/<run_id>/scope-template.md`.
- Phase B has already read the template and this run's `state.json` (at
  `interim/<run_id>/state.json`) is at `status: awaiting-scope`, `current_step: 0`.
- Read the completed template and the current `state.json` now before doing anything
  else. The raw subject is in `input/<run_id>/trigger.json` (read-only context).

## Step 0 — MANDATORY-FIELD HARD-STOP (do this first)

Two template fields are mandatory: **Audience / target reader** and
**Purpose / desired takeaway**. A field is blank if it is empty or still holds only
its placeholder guidance (e.g. `(write here)`).

- If **either** mandatory field is blank:
  1. Do **NOT** proceed, and do **NOT** guess or infer a value for it.
  2. List, back to the human, *exactly* which mandatory field(s) are blank.
  3. Ensure `state.scope.template_completed` reflects reality and
     `state.scope.missing_mandatory` lists the blank field keys
     (`"audience"` and/or `"purpose"`).
  4. Leave `status: awaiting-scope` and **STOP** the run. Tell the human to fill the
     listed field(s) in the template and re-run `/write-article continue`.
- Only when **both** mandatory fields are non-blank do you continue below.

You must never call the gate `pass` while a mandatory field is missing (see Exit
gate). Mandatory inputs are the human's to provide.

## Responsibility split

- **Human owns** (only they know these — take as given, never override):
  audience, purpose/takeaway, angle preference, must-include / must-avoid points,
  constraints, source-policy overrides.
- **Agent owns** (you are better at these):
  stress-testing the one-sentence thesis, catching an over-broad scope, checking the
  chosen angle actually has friction (is arguable, not a truism), and surfacing
  contradictions in what the human asked for.

## Reconciliation

Treat the completed template as the **authoritative spec**. Then:

1. **Propose values for blank OPTIONAL fields** (angle, length/format, tone,
   must-include, must-avoid, source-policy overrides). Surface each proposal *to the
   human for awareness* — this is a proposal, not a silent substitution. Make clear
   it is your suggestion and can be overridden.
2. **Flag tensions** between what the human asked for — do not quietly resolve them.
   Example: "audience = policymakers, but the angle you gave is highly technical —
   which should win?" Ask the human to adjudicate genuine conflicts.
3. **Interrogate the topic to find the narrower piece.** The subject as typed is
   almost always too broad for one article. Identify the specific, defensible slice
   that fits the audience, purpose, length, and available evidence.
4. **Set a PROVISIONAL working hypothesis / central question** — the angle you will
   test, phrased so research could confirm *or* overturn it. It is explicitly **not**
   a locked takeaway.

## Resolve the citation / referencing style (ask explicitly)

The article will carry in-text citations and a bibliography, so the run needs a
referencing style. **Do not silently pick one.** Resolve it in this order:

1. If the human wrote a style in the template's *Referencing / citation style* field, or
   `controls.citation_style` is already set to a non-default explicit value, use that.
2. **Otherwise, ASK the human explicitly** with `AskUserQuestion`, listing the full menu
   of supported schemes so they can choose. Present **all** of these options (the tool
   shows a few as buttons and an "Other" entry — name the rest in the question text so
   every option is visible):

   - **apa** — APA (7th ed.), author–date
   - **mla** — MLA (9th ed.), author–page
   - **chicago-author-date** — Chicago author–date
   - **chicago-notes** — Chicago notes & bibliography
   - **harvard** — Harvard author–date
   - **ieee** — IEEE, numeric `[n]`
   - **vancouver** — Vancouver, numeric
   - **none** — no referencing

3. Record the chosen value in `state.controls.citation_style` (one of the tokens above).
   Step 2 gathers the bibliographic fields that style needs; Steps 4–5 render the
   citations with `scripts/format-references.sh`. The default if the human truly has no
   preference is `apa`.

## Resolve the post category & rigor tier (ask explicitly)

How much external research and adversarial fact-checking a run does is driven by
**what kind of post this is**, not a one-size-fits-all default. A late-night musing
and a deeply reported explainer do not deserve the same amount of source-hunting.
**Do not silently pick a tier or skip this** — resolve it in this order:

1. If the human wrote a category in the template's *Post category* field, or
   `controls.post_category` is already set to a non-blank explicit value, use that
   (match case-insensitively; an unrecognized token is treated as `deep-dive` — tell
   the human you didn't recognize it and are defaulting to full rigor, don't guess a
   lighter tier for an unknown category).
2. **Otherwise, ASK the human explicitly** with `AskUserQuestion`, presenting all of
   these options (the tool shows a few as buttons and an "Other" entry — name the
   rest in the question text so every option is visible):

   - **musings** — late-night thoughts, personal reflection *(reflective tier)*
   - **photos** — captions / accounts of memories *(reflective tier)*
   - **travel** — trip plans or trip logs *(reflective tier)*
   - **learnings** — systems, techniques, ideas worth sharing *(light-check tier)*
   - **movies** — an opinion/review of a film *(light-check tier)*
   - **books** — a summary/reflection on a book *(light-check tier)*
   - **mba** — course notes and reflections *(light-check tier)*
   - **deep-dive** — anything else needing full research + independent fact-checking
     *(journalistic tier)*

3. **Map the category to a rigor tier** and set the derived controls accordingly.
   Never invent a tier outside this table:

   | `post_category` | `rigor_tier` | `research_mode` | `adversarial_cap` |
   |---|---|---|---|
   | musings, photos, travel | `reflective` | `none` — no external research; Step 2 becomes a personal-context capture pass | `0` — the orchestrator skips Step 8 (the adversarial-reviewer dispatch and `review-loop.sh`) entirely for this tier; there is nothing externally-checkable in a personal account, so the gate has nothing to do |
   | learnings, movies, books, mba | `light-check` | `spot-check` — verify only the handful of hard, named facts the piece states | `2` — and the reviewer only attacks that same class of hard named facts, at the same single-source bar Step 2 used (see `agents/adversarial-reviewer.md`) |
   | deep-dive (or unrecognized) | `journalistic` | `deep` — full territory mapping, counter-evidence hunting, source triangulation | leave `controls.adversarial_cap` exactly as it already is (the plugin's configured/default value) — do **not** overwrite an explicit human/config override with a tier default |

   Write `controls.post_category` (the raw token), `controls.rigor_tier`, and
   `controls.research_mode` per the table. For `reflective` and `light-check`, also
   overwrite `controls.adversarial_cap` with the table value — this is a deliberate,
   explicit tier override, not a silent substitution; mention it to the human in your
   Step 1 summary (e.g. "category: musings → no research step, one quick review pass,
   no fact-checking — say so if you'd rather this got the full treatment"). Leave
   `controls.adversarial_min`, `controls.per_gate_cap`, and every other control
   untouched — the tier only governs research depth and the adversarial ceiling.
   `controls.rigor_tier` is read by Step 2 and reported in the manifest; it never
   gates anything by itself.

## ANTI-BIAS requirement (provisional hypothesis)

The hypothesis stays **provisional** to defend against confirmation bias. It must
**not** harden into a settled thesis until after Step 2's research. Therefore:

- Frame it as a working hypothesis / open central question, not a conclusion.
- Write `state.hypothesis.text` to the provisional statement, and set
  `state.hypothesis.hardened_to_thesis = false`. It is Step 3 — after research —
  that flips this to a settled thesis, never Step 1.

## Exit gate — "One clean sentence?"

The gate passes only if you can state **angle + reader + hypothesis in a single,
non-vague sentence** that is consistent with the human's template.
(e.g. "For [reader], this piece argues [angle] by testing whether [hypothesis].")

Record the gate result deterministically — the counter is mutated **only** by the
script, never by your free text:

- **On pass:**
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-1 pass
  ```
  Then write the outputs (below), advance `current_step` to `1`, and set `status`
  to `step-1` (moving toward Step 2) per the state contract.

- **On fail** (the sentence is still vague, over-broad, self-contradictory, or the
  angle has no friction):
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-1 fail
  ```
  The script returns either `RETRY <n>` — loop back within Step 1 to tighten the
  scope and hypothesis, then re-test the gate — or, at the cap, `ESCALATE HALT-HUMAN`.

**The script's output is authoritative — obey it.** If it prints
`ESCALATE HALT-HUMAN`, halt the run and flag it for human input (nothing is upstream
of scope to fix). Do **not** loop a further time, and do **not** pass the gate on the
human's behalf to get past a mandatory-input problem — if inputs are missing, go back
to the hard-stop, do not force a pass.

## Outputs (written on pass)

Write to `interim/<run_id>/state.json`:

- `scope.reconciled` — the reconciled scope record: the human's mandatory fields, the
  final (human-given or agent-proposed) optional fields with each proposal marked as
  such, the flagged tensions and how they were resolved, and the narrowed topic.
- `scope.template_completed = true`, `scope.missing_mandatory = []`.
- `controls.citation_style` — the referencing scheme, explicitly chosen (one of the menu
  tokens; default `apa`). Never leave this unresolved.
- `controls.post_category`, `controls.rigor_tier`, `controls.research_mode` — the
  resolved post category and its derived rigor tier/research mode (see *Resolve the
  post category & rigor tier* above). `controls.adversarial_cap` is also overwritten
  per the tier table for `reflective`/`light-check`. Never leave `post_category`
  unresolved.
- `hypothesis.text` — the provisional working hypothesis / central question.
- `hypothesis.hardened_to_thesis = false` (stays false until Step 3).
- `current_step = 1`, `status = "step-1"` (or as your orchestrator advances it toward
  Step 2), and `updated_at` bumped.

**Counter fields (`gates.*`, `escalation_history`) are mutated ONLY by
`gate-counter.sh`** — never write them from free text (state contract §3, §4).
