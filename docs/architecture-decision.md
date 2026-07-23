# Architecture Decision — can gates be enforced deterministically?

**Decision: ADOPTED (with one refinement).** Recorded 2026-07-15.

This records the load-bearing architectural question, deliberately answered on a thin
vertical slice before any breadth was built. The question: *can gates and loop caps be
enforced deterministically, not by model self-report?*

---

## What we built to test it
- `scripts/gate-counter.sh` — sole mutator of per-gate counters; deterministically
  escalates at the cap (26/26 tests).
- `scripts/gate-guard.sh` + `hooks/hooks.json` — a `PreToolUse` backstop that blocks the
  irreversible action (9/9 tests).
- `commands/write-article.md`, `templates/scope-template.md`, `skills/step-1-scope` — the
  thinnest end-to-end vertical slice (setup → scope handshake → Step 1 gate).

## The finding

The original framing — "a hook that can **block** progression when a counter is
exceeded" — is **half right, and the wrong half is important.** Claude Code hooks fire on
**tool-use lifecycle events** (`PreToolUse`, `PostToolUse`, `Stop`, …). There is **no
tool event that represents "the model started attempt #4 at Step 5."** A step "iteration"
is model reasoning, not a tool call, so a hook literally cannot intercept it. Any design
that assumed "a hook watches the loop and stops the 4th iteration" would not have worked —
and that is exactly the assumption this slice was built to falsify. It is falsified.

The determinism that **does** hold is a composition of two real mechanisms:

1. **The number lives in code the model doesn't run, in a file the model doesn't author.**
   `gate-counter.sh` owns the counter. At the cap it returns `ESCALATE`, **never**
   `RETRY` — the model cannot obtain permission to loop again, because it is not the thing
   computing the permission. Proven by `tests/phase1-core.sh`. This makes the *per-cycle*
   cap real.

2. **The one irreversible action is guarded at a real tool event.** Emitting a deliverable
   is a `Write`/`Edit` — a genuine `PreToolUse` event. `gate-guard.sh` denies any write
   into `output/<run>/` unless `state.json` shows the pipeline legitimately reached the
   publish stage (`step-8`/`published`), fails **safe** (deny) when no run state exists,
   and denies writes past the adversarial ceiling. Proven by `tests/phase2-guard.sh`.
   This makes *premature or over-cap emission* impossible regardless of model behaviour.

## Honest residual limit (must be carried forward, not hidden)

The model still performs the gate **judgement** (is this "one clean sentence?"), and in
principle could re-enter a step after an `ESCALATE` instead of going upstream — because
escalation resets the counter. So the guarantee is **not** "the model can never loop more
than 3 times at a step." The guarantee is narrower and honest:

- The model **cannot** get a `RETRY` past the per-cycle cap (script-owned).
- The model **cannot** emit a deliverable before the pipeline legitimately reached review,
  and **cannot** write past the adversarial round ceiling (guard-owned, at a real event).
- The model **cannot** silently mutate a counter (only `gate-counter.sh` writes them).

What remains model-discipline (instruction-enforced, not physically enforced) is
*obeying the `ESCALATE` target* — moving upstream rather than re-entering the step. This
is acceptable because the **thing that matters — bounded, non-premature output — is
physically enforced**, and the unbounded-work risk at the one heavyweight loop (Step 8) is
capped by the guard at the emission point.

## Consequences (carried into the orchestrator contract)
1. **Orchestrator must treat `ESCALATE` as mandatory routing**, not advisory. Every step
   skill already calls `gate-counter.sh` and is told the script output is authoritative —
   the orchestrator enforces the upstream jump.
2. **The guard is the safety net, the scripts are the source of truth.** Keep every
   counter/round number in `state.json`, written only by scripts.
3. **Directory question resolved (requirements open-question §12):** use `commands/` for
   the trigger (matches requirements §7); step logic lives in `skills/`. The stray
   placeholder skill that collided on the name `write-article` has been removed.
4. **Step 8's round ceiling should also be enforced at a real event** (the guard already
   does this defensively; `review-loop.sh` makes it primary), because "max 5 reviews" is the other
   place unbounded work could hide.

## Evidence
- `tests/phase1-core.sh` — 26/26 (allocation, per-day reset, slug-halt, cap-3 escalation,
  counter-only-mutated-by-script, init→gate integration).
- `tests/phase2-guard.sh` — 9/9 (deny at awaiting-scope/mid-pipeline, allow at
  step-8/published, fail-safe on missing state, adversarial-ceiling deny, relative paths).

**Verdict: the deterministic-gating architecture holds, with the refinement above.**
