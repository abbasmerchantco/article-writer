---
name: step-6-sharpen
description: Step 6 of the article-writer workflow — Sharpen the open and close. Rewrites the intro LAST so both ends fuse to what the piece actually became instead of being bolted on from the outline, makes the hook create tension, checks the opening's PROMISE against the ending's PAYOFF and realigns whichever drifted, lands the close on an implication/turn rather than a summary, and tests both seams as continuous reads. Passes the "promise matches payoff?" gate via gate-counter.sh. Use when a run is at status step-6 (revised body in hand) and /write-article continue is resuming it.
allowed-tools: Read, Edit, Bash
---

# Step 6 — Sharpen open and close

The opening and closing are the last things written, **not** the first. The intro you
sketched in the outline was a promise made before the piece existed; by now the argument
has moved. Rewriting both ends *after* the body means they **fuse** to what the piece
actually became instead of bolting on from a stale plan. Do not touch the body's argument
here — Step 5 owns structure and claims; Step 6 only makes the two ends fit the body and
each other.

## Entry precondition

- The run's `state.json` (at `interim/<run_id>/state.json`) is at `status: step-5`,
  `current_step: 5`, with Step 5's revision passed — the body is stable. (Convention:
  `status: step-N` means step N is *complete*; the orchestrator dispatches step N+1.)
- Read the current `state.json` and the revised draft at `interim/<run_id>/draft.md` now,
  before doing anything else. Read the reconciled scope and hardened thesis
  (`scope.reconciled`, `hypothesis`) — they define what the opening is allowed to promise.
- If the body is not stable (Step 5 not passed), stop: ends cannot fuse to a moving body.

## Actions

Work the body-first, ends-last discipline in order:

1. **Rewrite the intro LAST.** Reread the finished body first, then write the opening to
   match the piece as it now stands — not the outline's original plan. The opening is
   drafted *after* the body precisely so it fits reality, not the intention.
2. **Make the hook create tension.** The first lines must open a gap the reader needs
   closed — a question, a surprise, or a friction. Not a throat-clear, a definition, or a
   summary of what follows. If the hook could be deleted with nothing lost, it is not a
   hook.
3. **Check PROMISE ↔ PAYOFF.** State, in one line to yourself, the *promise* the opening
   makes (the question/tension it sets up) and the *payoff* the ending delivers. They must
   answer each other. If they have drifted apart, **realign whichever drifted** — usually
   the intro (rewritten here anyway), but move the close if the body earned a different,
   truer payoff. Do not force a false match; make them genuinely meet.
4. **Land the ending on an implication or turn, NOT a summary.** The close pays off the
   promise and then opens outward — a consequence, a reframing, a "so what now." Never a
   recap of the sections. If the last paragraph merely restates the body, rewrite it.
5. **Test the seams as continuous reads.** Read intro→body and body→close each as one
   uninterrupted passage. A seam fails if the join feels like a gear-change — a repeated
   phrase, a dropped thread, a tonal jump. Smooth the seam until each reads continuous.

Write the final opening and closing into `interim/<run_id>/draft.md` (Edit the existing
draft in place — the body is preserved, only the two ends change).

## Exit gate — "Promise matches payoff?"

The gate passes only if the opening's promise and the ending's payoff genuinely answer
each other, the hook creates real tension, the close lands on an implication (not a
summary), and both seams read continuous.

Record the gate result deterministically — **the counter is mutated only by the script,
never by your free text** (contracts §3; architecture-decision: the script's ESCALATE is
authoritative and mandatory, the model never mutates counters):

- **On pass:**
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-6 pass
  ```
  Then write the outputs (below), advance `current_step` to `6`, and set `status` to
  `step-6` (Step 6 complete; the orchestrator dispatches Step 7 next) per the state contract.

- **On fail** (promise and payoff still don't meet, the hook is inert, the close only
  summarizes, or a seam still jars):
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-6 fail
  ```
  The script returns either `RETRY <n>` — loop back within Step 6, rewrite the intro
  again against the body and re-test — or, at the cap, `ESCALATE step-5`.

**The script's output is authoritative — obey it.** If it prints `ESCALATE step-5`, do
**not** loop a further time in Step 6: route back to Step 5. Repeated failure to fuse the
ends is a signal the *body itself* is unstable (contracts §3 routing table: "ends won't
fuse to an unstable body"), so the fix is upstream revision, not more polishing of the
open and close. Never pass the gate on your own authority to escape the loop.

## Outputs to state

Write to `interim/<run_id>/state.json` on pass:

- The final opening and closing, fused to the body, are saved in
  `interim/<run_id>/draft.md` (body unchanged; only the two ends rewritten).
- `current_step = 6`, `status = "step-6"` (Step 6 complete; the orchestrator dispatches
  Step 7 next), and `updated_at` bumped.

**Counter fields (`gates.*`, `escalation_history`) are mutated ONLY by
`gate-counter.sh`** — never write them from free text (contracts §3, §4; architecture-decision).
