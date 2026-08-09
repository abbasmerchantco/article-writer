---
name: step-3-structure
description: Step 3 of the article-writer workflow — Find the structure. Extracts defensible claims from Step 2 research, hardens the provisional hypothesis into a SETTLED thesis (or revises it to fit findings), finds the single through-line, sequences sections by reader dependencies, marks the jobs of the opening tension and closing payoff without writing them, and produces a one-line-per-section outline with a claim→evidence mapping. Passes the "every claim on-spine & backed?" gate via gate-counter.sh; on cap escalates to step-2. Use when a run is at status step-2/step-3 and /write-article continue is resuming it.
allowed-tools: Read, Edit, Bash
---

# Step 3 — Find the structure

Step 2 gathered evidence. Step 3 turns that pile into a **spine**: one through-line,
every section earning its place, every claim traceable to evidence. This is also the
moment the piece stops being exploratory and commits — the provisional hypothesis
**hardens into a settled thesis** here (or is revised to fit what the research actually
showed). You do **not** write prose in this step: you decide what the article argues, in
what order, and why — Steps 4 and 6 do the writing.

## Entry precondition

**Root note:** every `input/`, `interim/`, `output/` path in this skill is relative to
this run's root `<root>` (its `state.json.paths.root`, or the current working directory
for a pre-`output_root` run) — the orchestrator that dispatched you already resolved it
to find this run; use that same value. See `commands/write-article.md` § *Resolving the
run root*.

- Step 2 has passed its gate; `<root>/interim/<run_id>/state.json` shows research captured under
  `research.claims[]` (each `{ claim, source, tier, independent }`) and
  `research.open_questions[]`, with `hypothesis.hardened_to_thesis` still **false** and
  `hypothesis.text` holding the *provisional* working hypothesis from Step 1.
- The run is at `current_step: 2` (moving into Step 3). Read the current `state.json` and
  the reconciled scope (`scope.reconciled`) now, before doing anything else, so the spine
  serves the human's audience and purpose.

## Actions (the Step 3 subprocess)

1. **Extract the defensible claims.** From `research.claims[]`, pull the claims the article
   can actually stand on — each backed by a whitelisted, sufficiently-tiered source
   (requirements §6.3). A claim resting only on a blacklisted or low-tier source is
   **not** defensible; treat it as unsupported (leave it for Step 2 re-sourcing or drop it).
2. **Harden the hypothesis into a thesis** — the key event of this step (see below). Compare
   the provisional hypothesis against the extracted evidence:
   - If the evidence confirms it, promote it to a settled thesis (sharpen the wording; it is
     now a claim the piece asserts, not a question it tests).
   - If the evidence overturns or bends it, **revise the thesis to fit the findings** — do
     not bend the findings to fit the hypothesis. The thesis follows the evidence.
3. **Find the single through-line.** State the one spine the whole piece serves — the line
   an intelligent reader should be able to trace start to finish. There is exactly one.
   Anything that does not advance it is a **candidate for cutting**.
4. **Map claim → evidence.** Bind each defensible claim to the specific source(s) that back
   it. No claim may enter the outline without evidence behind it (the exit-gate test).
5. **Sequence by reader dependencies, not discovery order.** Order sections so each rests
   only on what the reader already has — a claim that needs a prior idea comes after it. The
   order you *found* things is irrelevant; the order the reader *needs* them is everything.
6. **Design the opening and closing as MARKED JOBS, not prose.** Decide what tension the
   opening must create and what payoff the close must deliver — and check the opening's
   promise and the closing's payoff are two ends of the same through-line. Record these as
   *jobs to be done*, not written sentences. **Do not draft them here** — the hook is
   written fast-and-ugly in Step 4 and sharpened in Step 6.
7. **Outline one line per section.** Each line names the section's **job** (what it does for
   the argument) and its **point** (the claim it lands), and carries the claim→evidence
   link. Anything off the through-line does not get a line — it is cut.

## KEY EVENT — hypothesis hardens into thesis (Step 3, never earlier)

This is the single step where `hypothesis.hardened_to_thesis` flips from `false` to
`true`. The hypothesis was deliberately kept **provisional** through Steps 1 and 2 to
defend against confirmation bias (requirements §4 Step 1, anti-bias): if the takeaway had
locked before the research, you would have gone looking to confirm it rather than to test
it. It must **not** have hardened in Step 1 or Step 2 — verify on entry that it is still
`false`, and only set it `true` **after** you have weighed the evidence in the actions
above. Hardening means either "the evidence held, thesis promoted" or "the evidence forced
a revision, thesis rewritten" — never "assert it anyway."

## Exit gate — "Every claim on-spine & backed?"

The gate passes only if **all three** hold:

- **On-spine:** nothing in the outline is off the through-line (no section survives that
  does not advance the spine).
- **Backed:** every claim in the outline maps to specific evidence (no orphan claims resting
  on nothing).
- **No stranded evidence conflicts:** the thesis is consistent with the evidence, not
  propped up against it.

Record the gate result deterministically — the counter is mutated **only** by the script,
never by your free text (contracts §3; architecture-decision: the script's `ESCALATE` output is
authoritative and the model never mutates counters):

- **On pass:**
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-3 pass
  ```
  Then write the outputs (below), advance `current_step` to `3`, and set `status` to
  `step-3` (moving toward Step 4) per the state contract.

- **On fail** (claims are orphaned, sections wander off the spine, or no single through-line
  holds the pieces together):
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-3 fail
  ```
  The script returns either `RETRY <n>` — loop back **within Step 3** to rework the outline
  (drop off-spine material, re-source or cut orphan claims, re-sequence, re-test the gate) —
  or, at the cap, `ESCALATE step-2`.

**The script's output is authoritative — obey it.** If it prints `ESCALATE step-2`, you
cannot build a spine on thin research: stop reworking the outline and route the run **back
to Step 2** to research deeper (requirements §5.1 — "can't build a spine on thin research").
Do **not** loop a further time within Step 3, and do **not** pass the gate by keeping an
orphan or off-spine claim to get past a research shortfall.

## Outputs (written on pass)

Write to `interim/<run_id>/state.json`:

- `outline` — the structure, as an ordered array of section objects, each shaped roughly:
  ```json
  {
    "order": 1,
    "job": "what this section does for the argument",
    "point": "the claim this section lands",
    "claims": ["<claim text or research.claims[] reference>"],
    "evidence": ["<source ref / tier from research.claims[]>"]
  }
  ```
  Include the through-line statement (e.g. an `outline.through_line` field or a leading
  record) and the two marked jobs — `outline.opening_job` (the tension the intro must
  create) and `outline.closing_job` (the payoff the ending must deliver) — as *jobs*, not
  written prose.
- `hypothesis.hardened_to_thesis = true`, and `hypothesis.text` set to the **settled thesis**
  (the promoted or revised statement — no longer phrased as an open question).
- `current_step = 3`, `status = "step-3"` (or as your orchestrator advances it toward
  Step 4), and `updated_at` bumped.

**Counter fields (`gates.*`, `escalation_history`) are mutated ONLY by
`gate-counter.sh`** — never write them from free text (state contract §3, §4).
