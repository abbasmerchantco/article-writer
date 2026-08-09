---
name: step-7-second-eyes
description: Step 7 of the article-writer workflow — Rest, then second eyes. Buys distance from the near-final draft (a deliberate cold re-read pass, with genuine overnight rest offered as a resumable pause), rereads cold AS A READER marking confusion and boredom, optionally solicits an outside human reader via AskUserQuestion, separates signal (genuine confusion → fix) from noise (mere stylistic preference → leave), does a final read, and passes the "cold-read confusions resolved?" gate via gate-counter.sh. Use when a run at status step-7 is resuming after Step 6 via /write-article continue.
allowed-tools: Read, Edit, Bash, AskUserQuestion
---

# Step 7 — Rest, then second eyes

The draft is finished-looking but you wrote it, so you can no longer see it. This
step buys **distance** and borrows **another pair of eyes** to find the confusions
you're now blind to. Its discipline is separating **signal** (genuine reader
confusion — fix it) from **noise** (a different taste than yours — leave it).
Distance is *bought, not manufactured on demand*: you cannot will yourself to read
your own fresh prose as a stranger, so this step deliberately creates gap.

## Entry precondition

**Root note:** every `input/`, `interim/`, `output/` path in this skill is relative to
this run's root `<root>` (its `state.json.paths.root`, or the current working directory
for a pre-`output_root` run) — the orchestrator that dispatched you already resolved it
to find this run; use that same value. See `commands/write-article.md` § *Resolving the
run root*.

- The run's `state.json` (at `<root>/interim/<run_id>/state.json`) is at `status: step-6`,
  `current_step: 6` (Step 6 sharpened the open and close and passed its gate). (Convention:
  `status: step-N` means step N is *complete*; the orchestrator dispatches step N+1.)
- The near-final article is in `interim/<run_id>/draft.md` with a fused opening and
  closing.
- Read the current `state.json` and `interim/<run_id>/draft.md` now before doing
  anything else.

## Actions

### 1. Let it sit — buy distance (this run is RESUMABLE)

Genuine overnight rest is the ideal and it is a **human** option, not something the
agent can fake in-session. Because run state persists in `interim/`, Step 7 may
legitimately **pause the whole run and be continued later** — nothing is lost.

- **Offer the real pause.** Tell the human they can stop here and resume with
  `/write-article continue` after a real break (ideally overnight). Leave `status`
  at `step-7`; the state file is the resume point. If they take it, **STOP** — do
  not force the gate to get past the rest.
- **If they'd rather continue now**, the agent's minimum substitute for distance is
  a *deliberate cold re-read pass*: approach the draft from the top as if seeing it
  for the first time, not skimming for the sentences you remember writing. This is a
  weaker distance than sleep, so be honest that it is a substitute, not equivalent.

### 2. Reread cold — AS A READER, not as the author

Read the whole piece straight through in the reader's role. Do **not** edit while
reading. Mark, in place, the two things a stranger feels but an author cannot:

- **Confusion** — where a reader would lose the thread, hit an undefined term, or
  can't tell why a paragraph is here.
- **Boredom** — where attention drops: a stretch that sags, over-explains, or stalls
  the argument.

Collect these as a marked list; resolution comes after the outside read, so signal
and noise can be judged together.

### 3. Get an outside reader (may ask the human)

An outside reader catches what even your cold read misses. Use **AskUserQuestion** to
invite the human to act as (or route the draft to) that reader, and to answer the one
question that matters: **where did you lose the thread?** — plus any spot that bored
or confused them.

- This is optional but strongly preferred. If no outside reader is available, say so
  plainly and rely on the cold re-read alone; do not pretend an outside read happened.

### 4. Separate SIGNAL from NOISE (the core discipline)

Now merge your cold-read marks with the outside reader's feedback and sort every item:

- **SIGNAL — genuine confusion / lost thread / real boredom → FIX.** These are places
  the piece fails a reader regardless of taste.
- **NOISE — mere stylistic preference → LEAVE.** A reader wanting a different word,
  a different tone, or "I'd have done it differently" is *not* a defect. Do **not**
  chase every preference; that dilutes the piece and never converges.

The test: *would most readers in the target audience be misled or lost here, or is
this just one reader's taste?* Fix the former; record and decline the latter.

### 5. Final read

After applying the signal fixes, read the piece through one last time to confirm the
confusions are gone and nothing new broke. Update `interim/<run_id>/draft.md` in place
to this near-final version — the article that will go to Step 8's adversarial review.

## Exit gate — "Cold-read confusions resolved?"

The gate passes only if the genuine confusions and lost-thread points surfaced by the
cold read and the outside reader have been **fixed** (not merely noted), noise was
correctly declined rather than chased, and the final read is clean.

Record the gate result deterministically — the counter is mutated **only** by the
script, never by your free text:

- **On pass:**
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-7 pass
  ```
  Then write the outputs (below), advance `current_step` to `7`, and set `status` to
  `step-7` (Step 7 complete; the orchestrator dispatches the Step 8 adversarial review
  next) per the state contract.

- **On fail** (real confusions remain, the piece still loses the reader, or a genuine
  boredom/clarity defect is unresolved):
  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/gate-counter.sh interim/<run_id>/state.json step-7 fail
  ```
  The script returns either `RETRY <n>` — loop back within Step 7 to resolve the
  outstanding confusions, then re-test the gate — or, at the cap, `ESCALATE step-5`.

**The script's output is authoritative — obey it.** If it prints `ESCALATE step-5`,
do **not** loop a 4th time: go back to Step 5 (revision). Reader confusion is usually
a **revision** issue — repeated cold-read failure signals the prose/structure needs
reworking upstream, not another local polish pass (requirements §5.1).

## Outputs to state

Write to `interim/<run_id>/state.json` (on pass):

- Update `interim/<run_id>/draft.md` to the near-final article — cold-read confusions
  fixed, ready for Step 8's adversarial review.
- `current_step = 7`, `status = "step-7"` (Step 7 complete; the orchestrator dispatches
  the Step 8 adversarial review next), and `updated_at` bumped.

If instead you paused for genuine rest (Action 1), leave `status: step-6` and
`current_step: 6` unchanged (Step 7 not yet complete) so `/write-article continue`
re-enters Step 7 later.

**Counter fields (`gates.*`, `escalation_history`) are mutated ONLY by
`gate-counter.sh`** — never write them from free text (state contract §3, §4).
