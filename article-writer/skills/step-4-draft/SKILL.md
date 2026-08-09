---
name: step-4-draft
description: Step 4 of the article-writer workflow — Draft fast and ugly, separating generation from judgment. Silences the editor (no rereading or polishing this pass), follows the outline but lets it flex, drops [check stat] placeholders instead of stopping to look things up, skips hard parts and returns, and reaches the end at all costs. Writes the complete rough draft to interim/{run_id}/draft.md and registers every placeholder in `state.placeholders` with resolved=false. Its exit gate checks COMPLETENESS ONLY (did you reach the end, are placeholders still visibly marked) — deliberately not a quality gate — via gate-counter.sh. Use when a run is at current_step 3 (Step 3 passed) and /write-article continue is resuming it.
allowed-tools: Read, Edit, Bash
---

# Step 4 — Draft fast and ugly

The whole point of this step is to **separate generation from judgment**. Getting
words onto the page and evaluating whether they are good are two different mental
modes, and doing them at once stalls both. So here you **generate only** — momentum
over polish. The editor gets silenced now and gets its turn in Step 5. A draft that
is complete and ugly is a success; a draft that is elegant but half-finished is a
failure.

## Entry precondition

**Root note:** every `input/`, `interim/`, `output/` path in this skill is relative to
this run's root `<root>` (its `state.json.paths.root`, or the current working directory
for a pre-`output_root` run) — the orchestrator that dispatched you already resolved it
to find this run; use that same value. See `commands/write-article.md` § *Resolving the
run root*.

- Step 3 has passed: the outline with claim→evidence mapping exists in
  `<root>/interim/<run_id>/state.json` and the hypothesis has hardened into a settled thesis
  (`hypothesis.hardened_to_thesis = true`).
- The run is at `current_step: 3` (i.e. Step 3 complete, Step 4 next), status advancing
  toward Step 4.
- Read the current `state.json` and the outline now, before drafting anything. The
  research notes (`state.research.claims`) are available as context for what you can
  assert from evidence versus what still needs a number.

## Actions

Draft the whole piece in one forward pass. Do not stop, do not scroll back, do not
edit what you already wrote.

1. **Silence the editor — no rereading or polishing this pass.** Do not reread
   paragraphs to smooth them, do not reword, do not second-guess phrasing. Judgment
   is Step 5's job. Any impulse to fix or improve is deferred, not obeyed.
2. **Follow the outline, but let it flex.** The Step 3 spine is your route. If a
   section wants to grow, shrink, or reorder as you write, let it — the outline serves
   the draft, not the reverse. Do not stop to re-plan.
3. **Drop `[check stat]` placeholders instead of stopping.** When a claim needs a
   number, date, name, or fact you do not have to hand, do **not** break momentum to go
   look it up. Write the sentence with a visible `[check stat] ...` marker describing
   what is needed, and **keep moving**. Register each one in `state.placeholders[]`
   (see Outputs) with `resolved: false`. Verification happens in Step 5, not here.
4. **Skip hard parts and return.** If a passage will not come, leave a short bracketed
   note of what belongs there and jump ahead. A stuck paragraph must never hold the
   whole draft hostage — come back to it after you have reached the end.
5. **Reach the end at all costs.** The single non-negotiable of this step is a draft
   that runs from opening to close with every outlined section present (however rough).
   Completeness is the deliverable.
6. **Mark in-text citations as you draft — lightweight, not polished.** When a sentence
   asserts something drawn from a source, drop the in-text citation right there. Get the
   exact strings once, before drafting, from the deterministic formatter:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/format-references.sh interim/<run_id>/state.json map
   ```
   It prints JSON `{ ref_id: "in-text citation string" }`. For each supporting claim in
   `state.research.claims[]`, look up its `ref_id` and paste the matching string next to
   the assertion — numeric styles (`ieee`/`vancouver`) render `[n]`, author-date styles
   (`apa`/`harvard`/`chicago-author-date`/`mla`) render `(Author, Year)`. **Placing them
   is what matters here; polishing them is Step 5.** Do not stop to hand-craft or verify
   citation formatting — that is Step 5's verification pass. If `controls.citation_style`
   is `none`, skip citations entirely.
7. **Append the References section at the very end.** Once you have reached the close,
   paste a formatted reference list as the final section, verbatim from:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/format-references.sh interim/<run_id>/state.json bibliography
   ```
   Its output already carries the correct heading for the chosen style
   ("References" / "Works Cited" / "Bibliography") — do not retype or reformat it. Skip
   this section only if `controls.citation_style` is `none` (the command prints nothing).

## Exit gate — "Complete draft, placeholders still visible?"

This gate is **completeness only, by design.** It asks two things, and *only* these:

1. **Did you reach the end?** Every outlined section is present as prose (rough is
   fine), the piece runs start to finish, and no section is a stub left un-drafted.
2. **Are the placeholders still visibly marked?** Every unresolved fact is still a
   visible `[check stat]` marker and is registered in `state.placeholders[]` with
   `resolved: false`. Nothing was silently "resolved" by inventing a number — an
   invented figure is worse than a visible gap, because Step 5 can only fix what it can
   still see.

Also confirm, as part of completeness, that a **References section is present** as the
final section (pasted from `format-references.sh ... bibliography`) — **unless**
`controls.citation_style` is `none`, in which case there is deliberately no References
section. Formatting quality of citations is *not* checked here; that is Step 5.

It is **deliberately not a quality check.** Do **not** fail this gate because the prose
is ugly, clumsy, repetitive, or unpolished — that is expected and is Step 5's to fix.
Failing an ugly-but-complete draft here would defeat the entire purpose of the step,
which is to protect drafting momentum by walling generation off from judgment.

Record the gate result deterministically — the counter is mutated **only** by the
script, never by your free text:

- **On pass** (the draft reaches the end and placeholders are still visible):
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-4 pass
  ```
  Then write the outputs (below), advance `current_step` to `4`, and set `status` to
  `step-4` (moving toward Step 5) per the state contract.

- **On fail** (the draft is *incomplete* — a section is missing, the piece does not
  reach its end, or placeholders were silently resolved/erased rather than left
  visible):
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-4 fail
  ```
  The script returns either `RETRY <n>` — loop back within Step 4 and keep drafting until
  you reach the end (do not restart; extend the existing draft) — or, at the cap,
  `ESCALATE step-3`.

**The script's output is authoritative — obey it.** If it prints `ESCALATE step-3`,
stop drafting and go back to Step 3: repeated inability to draft to the end signals a
**broken outline**, not a drafting problem — you cannot draft against a structure that
does not hold, so the fix is upstream in the spine, not here. Do **not** loop a further
time, and do **not** pass the gate on an incomplete draft to escape the loop.

## Outputs (written on pass)

Write the rough draft to a file and reference it from state:

- `interim/<run_id>/draft.md` — the **complete rough draft**, opening to close, with all
  `[check stat]` markers left visibly in place, **in-text citations placed inline** (from
  the `map` output) and a **formatted References section as the final section** (from the
  `bibliography` output) — both omitted only when `controls.citation_style` is `none`.
  This is WIP: it stays under `interim/` and never leaks into `output/`.

Write to `interim/<run_id>/state.json`:

- `draft.path = "interim/<run_id>/draft.md"` (reference the draft file; store a
  `draft.complete = true` flag alongside it if your orchestrator expects one).
- `placeholders[]` — the populated register. Append one entry per `[check stat]` marker,
  each shaped `{ "id": str, "text": "[check stat] ...", "resolved": false }` (state
  contract §4). **Every entry is `resolved: false` at this stage** — Step 5's
  verification pass is what flips them true; this step never resolves a placeholder.
- `current_step = 4`, `status = "step-4"` (or as your orchestrator advances it toward
  Step 5), and `updated_at` bumped.

**Counter fields (`gates.*`, `escalation_history`) are mutated ONLY by
`gate-counter.sh`** — never write them from free text (state contract §3, §4).
