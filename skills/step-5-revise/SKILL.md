---
name: step-5-revise
description: Step 5 of the article-writer workflow — Revise the ugly draft in six ORDERED passes, destructive→fine so polished work is never thrown away. Runs verification FIRST (resolve every [check stat] placeholder and re-confirm load-bearing claims), then an ORIGINALITY & ATTRIBUTION pass (detect passages that copy or lean too closely on a source, or borrow an idea without credit, and ethically quote-and-attribute / rewrite / attribute / remove each — deterministically verified by originality-check.sh), then structural, paragraph, and sentence passes, with proofreading LAST. Passes the "each pass's defect class cleared?" gate via gate-counter.sh. Use when a run is in-progress at Step 5 and /write-article continue is resuming it.
allowed-tools: Read, Edit, Bash, WebSearch, WebFetch
---

# Step 5 — Revise in passes (destructive → fine)

Revision has an ordering discipline: run the passes that *rip things out* before the
passes that *polish what remains*, so you never proofread a paragraph you are about to
delete. Verification comes first of all — it can force a claim to be corrected or cut,
which changes structure — the **originality & attribution** pass comes next, because
quoting, rewriting, or removing a copied passage also reshapes the prose — and
proofreading comes last, because its work is the most easily undone by every pass above
it.

## Entry precondition

- The run's `state.json` (at `interim/<run_id>/state.json`) is in-progress and reached
  Step 5; the complete rough draft from Step 4 is at `interim/<run_id>/draft.md`.
- Read `state.json` and `draft.md` now before doing anything else. Note the
  `placeholders[]` register (each `[check stat]` marker), `research.claims[]` (claim →
  source → tier), and the active `controls` (source policy, quality threshold).

## What this step is NOT (honesty note — requirements §5.2)

**Step 5 is not a fact-check substitute.** Its verification pass re-checks only the
claims that were *flagged* — the `[check stat]` placeholders and the load-bearing
claims your notes already marked. A claim you hold confidently but wrongly was never
flagged, so **no Step-5 loop will surface it.** Catching an unflagged falsehood is the
job of **Step 2** (finishing external verification) and **Step 8** (independent
re-sourcing that ignores the author's markers). Do not let a Step-5 pass — or a Step-5
retry loop — masquerade as fact-checking. Correct and polish what is flagged; do not
claim to have verified what was never in question.

## Actions — the six passes, run STRICTLY in this order

### Pass 1 — Clear verification FIRST (before touching structure)

Do this before any structural change, because a failed check can force a correction or
a cut that reshapes the argument.

- Resolve **every** `[check stat]` placeholder in `state.placeholders[]`. For each, find
  the actual figure/fact from an admissible source (obey the run's source policy and
  quality threshold, §6), replace the marker in `draft.md` with the confirmed value, and
  set that placeholder's `resolved = true` in state — **only when it is actually
  resolved.** Never flip `resolved` to satisfy the gate.
- Re-confirm the **load-bearing** claims already flagged in `research.claims[]`: that the
  draft still states them accurately, with caveats intact and no overstatement, resting
  on a whitelisted sufficiently-tiered source. Use WebSearch / WebFetch to re-confirm
  where the check needs an external source.
- If a load-bearing claim cannot be confirmed on an admissible source, it is
  **unsupported** — flag it; it must be independently re-sourced or cut (this is an
  external-truth problem that routes onward per §5.2, not something a proofreading pass
  fixes).
- **Reconcile the citations against `references[]`** (skip this bullet entirely if
  `controls.citation_style` is `none`):
  - Every in-text citation in the draft maps to a real entry in `state.references[]`,
    and every entry in `references[]` is cited at least once — **no orphan citations**
    (a marker pointing at nothing) and **no uncited references** (a listed source the
    body never uses). Fix drift by adding the missing citation or removing the dead
    reference/marker.
  - Confirm the **in-text citation style matches `controls.citation_style`** — numeric
    `[n]` for `ieee`/`vancouver`, author-date `(Author, Year)` otherwise. Regenerate the
    `map` (`format-references.sh ... map`) if you need the canonical strings.
  - **Regenerate the References section deterministically.** After any correction, cut or
    re-source above may have changed what is cited, so re-run
    `${CLAUDE_PLUGIN_ROOT}/scripts/format-references.sh interim/<run_id>/state.json bibliography`
    and **replace** the draft's References section with its output verbatim, so the
    formatted list is consistent with the edited body (heading included). Never hand-edit
    the reference list — always regenerate it.

**ACCEPTANCE CRITERION (§10):** no step proceeds while any `[check stat]` marker is
unresolved past this pass. Every `placeholders[].resolved` must be `true` before the
exit gate can pass.

### Pass 2 — Originality & attribution (plagiarism defense)

This pass runs **before** the structural pass because its remedies — quoting, rewriting,
or removing a copied passage — change the prose, and you must not polish text you are
about to replace. Its job is to make sure **every idea and every phrasing in the draft is
either the author's own or is properly credited to its source.** (Step 2 already required
paraphrasing in your own words; this pass is the check that it actually happened, plus the
ethical fix where it did not.)

Detection is **judgement you perform**; whether the fix landed is **verified
deterministically** by a script — you cannot pass the gate by merely asserting a passage
is resolved.

**1. Capture the comparison corpus.** For the sources behind the draft's claims, capture
short representative excerpts of the *actual source wording* into
`state.originality.corpus[]` (each `{ "source": "<citation/URL>", "text": "<excerpt>" }`).
This is what the deterministic scan compares the draft against — with no excerpts it has
nothing to compare, and must say so rather than imply a clean result. Set
`state.originality.detection_guarantee` to `"source-comparison"` if you captured source
text (and/or used WebSearch/WebFetch to compare against known text), or `"internal-only"`
if independent source access was unavailable and you could only read the draft against
itself. **Never imply source comparison you did not perform.**

**2. Run the deterministic overlap scan** as a detection aid:

```
${CLAUDE_PLUGIN_ROOT}/scripts/originality-check.sh interim/<run_id>/state.json interim/<run_id>/draft.md scan
```

It reports draft spans that share a long run of consecutive words with any captured
excerpt — candidate verbatim/near-verbatim copies. Treat its output as leads, not a
verdict: it cannot catch a reworded-but-uncredited *idea*, and an empty corpus means it
found nothing because it had nothing to compare. **You** must also catch:

- **close paraphrase** — the sentence structure and distinctive word choices tracking a
  source too closely, even with a few words swapped;
- **an unattributed direct quote** — memorable/verbatim source wording presented as the
  author's own;
- **an uncredited idea, framing, or data interpretation** — the *analysis* is borrowed
  even if the words are original;
- **structural mimicry** — the draft reproducing a source's distinctive sequence of points.

**3. Choose the ETHICAL remedy per flagged passage.** For each problem, pick exactly one
remedy — this is the "ethical removal / attribution" step:

| Situation | Remedy (`remedy` value) | What you do |
|---|---|---|
| Verbatim/near-verbatim wording of a **notable, quotable** statement | `quote-and-attribute` | Wrap it in quotation marks **and** add an in-text citation to its source. |
| Copied/too-close phrasing that is **not** a notable quote | `rewrite` | Re-express it genuinely in your own words (not a word-swap) so no distinctive source phrasing survives. |
| A **borrowed idea / analysis / interpretation** (even if reworded) | `attribute` | Keep the reworded prose but add an in-text citation crediting the source of the *idea*. |
| Copied passage that is non-essential, **or** whose only source is **blacklisted** and may not be cited (per `config/source-policy.json`) | `remove` | Cut it (and repair the flow), or rewrite from an admissible source. **Never attribute to a blacklisted source** — remove or re-source instead. |

Attribution obeys the run's citation policy exactly as Pass 1 does: add any new source as a
structured entry in `state.references[]` (Step 2 schema), cite it in-text in
`controls.citation_style`, and **regenerate the References section deterministically** with
`format-references.sh ... bibliography` (skip only when `citation_style` is `none`). A new
attribution that isn't a real, cited reference is not an attribution.

**4. Record every flag** in `state.originality.flags[]`, one entry per passage:

```json
{
  "id": "orig1",
  "passage": "<the copied/too-close text, verbatim as it appeared in the draft BEFORE you fixed it>",
  "type": "verbatim-copy | close-paraphrase | unattributed-quote | uncredited-idea | structural-mimicry",
  "matched_source": "<the source it echoes: citation/URL, or null>",
  "similarity": "high | medium | low",
  "severity": "blocking | advisory",
  "remedy": "quote-and-attribute | rewrite | attribute | remove",
  "ref_id": "<the references[] id used to attribute it, or null>",
  "resolved_note": "<what you changed>"
}
```

Record `passage` **exactly as the draft originally read** — the verifier looks for that
string to confirm a `rewrite`/`remove` genuinely eliminated it, or that a
`quote-and-attribute` passage now sits inside quotation marks. `severity: "blocking"` is
the default; reserve `advisory` for genuinely trivial, non-actionable overlap (e.g. an
unavoidable common phrase). Then set `state.originality.checked = true`.

**5. Verify the fixes actually landed** — deterministic gate helper:

```
${CLAUDE_PLUGIN_ROOT}/scripts/originality-check.sh interim/<run_id>/state.json interim/<run_id>/draft.md verify
```

It checks the **current draft** against every blocking flag: a `rewrite`/`remove`
passage must no longer appear (and a blocking flag with no `passage` text cannot pass —
there is nothing to verify); a `quote-and-attribute` passage must now be inside a
quotation span **and** carry a `ref_id` that exists in `references[]` (a quote is not
attributed until it is cited); an `attribute` flag must carry a `ref_id` that exists in
`references[]`. Exit `0` = all blocking flags verified (this pass is clear); exit `3` =
one or more **UNRESOLVED** — fix them and re-run until it exits `0`. The verifier is
authoritative: **do not pass the Step 5 gate while it exits 3**, and never edit a
flag's record to satisfy it instead of actually fixing the draft.

### Pass 3 — Structural pass

Does the argument actually flow? Is every section on the through-line? **Cut anything
off the through-line** — however good it is. Reorder so each point lands where the
reader is ready for it. This is the most destructive pass, so it runs before you invest
in paragraph- and sentence-level polish.

### Pass 4 — Paragraph pass

Each paragraph makes **one** clear point. Merge paragraphs that share a point, split
paragraphs carrying two, delete paragraphs carrying none.

### Pass 5 — Sentence pass

Clarity, rhythm, and filler. Cut hedges and padding; vary sentence length; **read
aloud** to catch what the eye skims.

### Pass 6 — Proofreading LAST

Typos, punctuation, formatting, consistent style. This is deliberately last: its work is
the most easily undone by any restructuring or rewriting above, so there is no point
doing it earlier. ("Proofreading" here means surface polish only — truth *verification*
was Pass 1 and, ideally, Step 2. Keep the two concepts separate.)

## Exit gate — "Each pass's defect class cleared?"

The gate passes only when **every** pass's defect class is cleared: verification done
(all placeholders resolved, load-bearing claims re-confirmed or routed), **originality &
attribution cleared (`originality-check.sh ... verify` exits 0 — no unresolved blocking
flags)**, structure on the through-line, one point per paragraph, clean sentences, and
clean proof. If any class still has open defects, the gate fails.

**The originality verifier is a hard sub-gate.** While
`${CLAUDE_PLUGIN_ROOT}/scripts/originality-check.sh interim/<run_id>/state.json interim/<run_id>/draft.md verify`
exits `3`, the Step 5 gate has **not** passed — resolve the flagged passages first. Do
not record a `pass` with blocking originality flags still unresolved.

Record the result deterministically — the counter is mutated **only** by the script,
never by your free text (requirements §5.3, §8; contracts §3):

- **On pass:**
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-5 pass
  ```
  Then write the outputs (below), advance `current_step` to `5` and `status` to `step-5`
  (moving toward Step 6) per the state contract.

- **On fail:**
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-5 fail
  ```
  The script returns either `RETRY <n>` — loop back within Step 5, rerunning the passes
  from the earliest defect class still open (verification first), then re-test the gate —
  or, at the cap, **`ESCALATE step-3`**. Structural defects surfacing during revision
  mean the spine itself is wrong, so escalation goes back to **Step 3 — Find the
  structure** (requirements §5.1; contracts §3 routing table).

**The script's output is authoritative — obey it.** The model never mutates counters or
decides whether the loop may continue (architecture-decision: `ESCALATE` is mandatory routing,
not advisory). On `ESCALATE step-3`, hand control upstream to Step 3; do **not** loop a
further time in Step 5, and do **not** pass the gate to escape a defect you have not
actually cleared.

## Outputs (written on pass)

- `interim/<run_id>/draft.md` — the revised draft (all five passes applied), its in-text
  citations reconciled against `references[]` and its **References section regenerated
  deterministically** from `format-references.sh ... bibliography` (omitted only when
  `controls.citation_style` is `none`).
- `interim/<run_id>/state.json`:
  - every `placeholders[].resolved = true` (all `[check stat]` markers resolved);
  - `research.claims[]` updated for any load-bearing claim re-confirmed or re-tiered
    during Pass 1;
  - `originality.checked = true`, `originality.detection_guarantee` set honestly,
    `originality.corpus[]` populated with the source excerpts compared against, and
    `originality.flags[]` recording every detected passage and its ethical remedy — with
    `originality-check.sh ... verify` exiting `0` against the final draft;
  - `references[]` updated with any new entries added to attribute a borrowed quote or
    idea (References section regenerated deterministically, as in Pass 1);
  - `current_step = 5`, `status = "step-5"` (or as your orchestrator advances it toward
    Step 6), and `updated_at` bumped.

**Counter fields (`gates.*`, `escalation_history`) are mutated ONLY by
`gate-counter.sh`** — never write them from free text (contracts §3, §4).
