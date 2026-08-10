# Integration Contracts (Phase 1 spine)

Authoritative interface definitions that all `article-writer` components build against.
Derived from [`requirements.md`](requirements.md) §3, §5, §8. When code and this
doc disagree, this doc wins until the doc is updated. Everything here is deterministic
(scripts/hooks own it) — no model free-text ever mutates these structures (requirements
§8, §10).

---

## 1. Run identity & folders (requirements §3, §3.1a)

Run under the **run root** — by default the current working directory (where Claude was
launched), overridable via the `output_root` control to an absolute, persistent path
(requirements §3.1a). The plugin ensures three top-level folders exist under that root,
each with one subfolder per run sharing an identical name:

```
<root>/input/<run_id>/     # commission / trigger log + scope template
<root>/interim/<run_id>/   # WIP + state.json
<root>/output/<run_id>/    # deliverables (only written on success)
```

`<root>` is always resolved to an **absolute path** by `init-run.sh` and recorded as
`paths.root` in that run's `trigger.json` and `state.json` (§4, §5) — every other script
and skill reads it from there rather than re-deriving `output_root`, so a run stays
addressable even if a later session's working directory differs or the control is
changed after the run was created.

**Run id format:** `YYYYMMDD-NNNNN-<slug>`
Example: `20260715-00003-return-to-office-economics`

- `YYYYMMDD` — trigger date (lexicographic == chronological sort).
- `NNNNN` — zero-padded 5-digit sequence, **scoped per day**, resets to `00001` each new
  date. Leading zeros mandatory (§3.2).
- `<slug>` — from the subject: lowercase → spaces to `-` → strip punctuation → collapse
  repeated `-` → trim leading/trailing `-` → truncate to **40 chars** (then re-trim any
  trailing `-`). Label only; raw subject preserved verbatim in the trigger log.

**Sequence allocation (§3.3):** scan existing folder names sharing today's `YYYYMMDD`
prefix (across all three top-level folders), take the max `NNNNN`, increment. Reads the
filesystem, not memory — survives across sessions, never collides within a day.

**Same-slug-same-day (open question §12):** if the newly-derived run id (date+seq+slug)
would exactly duplicate an existing folder name, the higher sequence number already
disambiguates it — folders never collide because `NNNNN` is unique per day.

---

## 2. `init-run.sh` interface (P1-T3…T6)

```
scripts/init-run.sh <subject...>            # normal: dedup-check, then allocate + create
scripts/init-run.sh --force-new <subject...># skip dedup, allocate a fresh run
scripts/init-run.sh --reuse <run_id>        # resolve to an existing run, no allocation
```

Behaviour:

0. **Resolve the run root** — read `AW_OUTPUT_ROOT` from the environment (the caller
   exports it from the resolved `output_root` control). Empty/unset → root is the current
   working directory (original behavior). Non-empty → that path is the root: created via
   `mkdir -p` if missing, then resolved to an **absolute** path. `--reuse <run_id>` and the
   slug-dedup scan (step 1) both check this root; if it differs from the plain current
   working directory they also check the plain cwd, for backward compatibility with runs
   created before this control existed.
1. **Slug dedup scan (§3.4)** — before allocating, scan **all** runs across **all dates**
   (all three top-level folders, under the resolved root) for a **slug match** (slug, not
   exact subject). On match, the script does **not** create anything: it prints one line to
   stdout and exits 2 so the command layer can ask reuse/new/cancel:
   ```
   DUPLICATE_MATCH <matched_run_id>
   ```
   `--force-new` skips this scan. `--reuse <run_id>` performs no scan and no allocation.
2. **Allocate** `YYYYMMDD-NNNNN` per §1, derive slug, assemble `run_id`. Sequence
   allocation scans only under the resolved root (a custom `output_root` starts its own
   `00001` sequence, independent of any legacy runs under a plain cwd).
3. **Create** the `<root>/input/<run_id>/`, `<root>/interim/<run_id>/`,
   `<root>/output/<run_id>/` triplet.
4. **Write** `<root>/input/<run_id>/trigger.json` (the trigger log, §5 below), including
   `paths.root` (the resolved absolute root) and `controls.output_root` (same value).
5. **Initialize** `<root>/interim/<run_id>/state.json` (schema §4) with
   `status: awaiting-scope`, including `paths.root`.
6. **Print**, on success, exactly one line to stdout:
   ```
   RUN <run_id>
   ```
   and exit 0. All diagnostics go to stderr. (The resolved root is not printed separately —
   the caller either already knows it, because it set `AW_OUTPUT_ROOT`, or can read
   `paths.root` from the `state.json` this call just wrote.)

**Exit codes:** `0` success · `2` duplicate slug (nothing created) · `1` usage/other error.

**Controls:** defaults live in the manifest `userConfig`; `init-run.sh` accepts the
resolved control set via env vars prefixed `AW_` (e.g. `AW_PER_GATE_CAP=2`,
`AW_ADVERSARIAL_CAP=3`, `AW_AUDIENCE=...`, `AW_OUTPUT_ROOT=...`, `AW_POST_CATEGORY=...`,
`AW_RESEARCH_MODE=...`). Any unset control falls back to the §4 default (`per_gate_cap`
and `adversarial_cap` softened from 3/5 to 2/3 — requirements §2.4; `post_category`
defaults to `""` and `research_mode` to `"deep"` until Step 1 resolves them for real —
requirements §2.4a). The full resolved control set is recorded in both `trigger.json`
and `state.json`.

---

## 3. `gate-counter.sh` interface (P1-T7)

Sole mutator of per-gate counters in `state.json` (requirements §5.3, §8, §10). No model
free-text ever writes these fields.

```
scripts/gate-counter.sh <state_path> <gate> get     # print current fail count
scripts/gate-counter.sh <state_path> <gate> pass     # reset counter to 0
scripts/gate-counter.sh <state_path> <gate> fail     # increment; enforce cap
```

`<gate>` ∈ `step-1 … step-7` (Step 8 uses the adversarial loop, §6, not this counter).

**`fail` semantics (cap enforcement, §5.1):**
- Increment the gate's fail counter, then compare against the cap (`AW_PER_GATE_CAP`,
  default **2**, softened from the original 3 — requirements §2.4).
- If `count < cap`: print `RETRY <count>` and exit 0.
- If `count >= cap`: do **not** allow a further local loop — print `ESCALATE <target>`
  using the routing table below, append to `escalation_history`, reset the gate counter to
  0 (the escalation restarts the upstream step's budget), and exit 3.

**`pass`:** reset counter to 0, print `PASS`, exit 0.
**`get`:** print the integer count, exit 0.

**Escalation routing table (§5.1):**

| Failing gate | `ESCALATE` target token | Rationale |
|---|---|---|
| step-1 | `HALT-HUMAN` | nothing upstream of scope to fix |
| step-2 | `step-1` | scope may be unresearchable as framed |
| step-3 | `step-2` | can't build a spine on thin research |
| step-4 | `step-3` | can't draft against a broken outline |
| step-5 | `step-3` | structural defects surfacing in revision |
| step-6 | `step-5` | ends won't fuse to an unstable body |
| step-7 | `step-5` | reader confusion is usually a revision issue |

All counter mutations write `state.json` atomically (write temp file, then move) and bump
`updated_at`.

---

## 4. `state.json` schema (requirements §8) — P1-T2

Lives at `<root>/interim/<run_id>/state.json`, where `<root>` is this same run's
`paths.root` below (requirements §3.1a). Initialized by `init-run.sh`, thereafter read on
every step entry and written on every step exit. Counters mutated **only** by
`gate-counter.sh`.

```json
{
  "schema_version": 1,
  "run_id": "20260715-00003-return-to-office-economics",
  "date": "20260715",
  "sequence": "00003",
  "slug": "return-to-office-economics",
  "raw_subject": "The economics of return-to-office mandates",
  "created_at": "2026-07-15T18:11:00Z",
  "updated_at": "2026-07-15T18:11:00Z",

  "status": "awaiting-scope",

  "paths": { "root": "/absolute/path/to/runs-root" },

  "scope": {
    "template_completed": false,
    "missing_mandatory": ["audience", "purpose"],
    "reconciled": null
  },

  "controls": {
    "output_root": "/absolute/path/to/runs-root",
    "audience": "general informed reader",
    "angle": "auto",
    "length": "medium",
    "tone": "neutral, plain",
    "source_policy": "default",
    "source_quality_threshold": "peer-reviewed / reputable only",
    "per_gate_cap": 2,
    "adversarial_cap": 3,
    "adversarial_min": 1,
    "escalation_routing": "default",
    "citation_style": "apa",
    "output_format": "docx",
    "post_category": "",
    "research_mode": "deep",
    "rigor_tier": null
  },

  "current_step": 0,

  "hypothesis": { "text": null, "hardened_to_thesis": false },

  "research": { "claims": [], "open_questions": [] },

  "references": [],

  "placeholders": [],

  "gates": {
    "step-1": { "fails": 0 },
    "step-2": { "fails": 0 },
    "step-3": { "fails": 0 },
    "step-4": { "fails": 0 },
    "step-5": { "fails": 0 },
    "step-6": { "fails": 0 },
    "step-7": { "fails": 0 }
  },

  "escalation_history": [],

  "originality": {
    "checked": false,
    "detection_guarantee": null,
    "corpus": [],
    "flags": []
  },

  "adversarial": { "rounds": 0, "ledger": [] }
}
```

**Field notes:**
- `paths.root` (requirements §3.1a): the absolute directory under which this run's
  `input/<run_id>/`, `interim/<run_id>/`, `output/<run_id>/` all live. Set once by
  `init-run.sh` at creation and never changed afterward — every script/skill that resumes
  or references this run reads it from here rather than re-deriving the currently-active
  `output_root` control, so a run stays addressable even if that control changes later or
  a later session's working directory differs. Absent on runs created before this field
  existed; treat that as "root = the current working directory."
- `status`: `awaiting-scope` → `step-1` … `step-8` → `published`. Used by
  `/write-article continue` for resumability and run selection (requirements §3.6, §8).
  A run is *resumable* when status is anything from `awaiting-scope` through in-progress
  (i.e. not `published`).
  **Canonical convention (all step skills + orchestrator MUST follow it):**
  `status: step-N` means **step N is complete** (its gate passed), with `current_step == N`.
  The orchestrator dispatches **step N+1** when it reads `status: step-N`. A step skill's
  entry precondition is therefore `status: step-(N-1)`; on passing its gate it sets
  `status: step-N`. A step never advances `status` past its own number. **Exception:**
  `step-8` denotes the adversarial-review/publish stage itself (not "step 8 done") — once
  the orchestrator enters Step 8 it sets `status: step-8`, which is the point at which the
  guard (`gate-guard.sh`) permits deliverable writes to `output/<run>/`; the terminal
  state is `published`.
- `scope.missing_mandatory`: recomputed when the completed template is read; a non-empty
  list hard-stops Phase B (requirements §3.6, §4 Step 1).
- `research.claims[]`: each `{ "claim": str, "source": str, "tier": str,
  "independent": bool, "ref_id": str }` — claim → source → tier; `ref_id` links the claim
  to a structured entry in `references[]` for in-text citation (requirements §4 Step 2, §6.3).
- `references[]`: structured bibliographic entries, the basis for formatted citations. Each:
  `{ "id": "ref1", "authors": ["Yasuoka, K.", "Yasuoka, M."], "year": "2011",
  "title": "On the Prehistory of QWERTY", "container": "ZINBUN",
  "publisher": "Kyoto University", "url": "https://…", "accessed": "2026-07-15",
  "tier": "peer-reviewed" }`. `authors` are in `Last, F. M.` form (an organisation is a
  single string with no comma). `id` is stable and used as the in-text citation key.
- `controls.citation_style`: the referencing scheme, chosen by the human in Step 1
  (explicitly, from a listed menu). One of: `apa`, `mla`, `chicago-author-date`,
  `chicago-notes`, `harvard`, `ieee`, `vancouver`, `none`. `scripts/format-references.sh`
  renders `references[]` in this style (both the in-text form and the bibliography).
- `controls.output_format`: the final deliverable format for the article. `docx` (default)
  or `md`. `make-manifest.sh` emits `article.docx` (via `scripts/to-docx.sh`) accordingly.
- `controls.post_category` / `controls.rigor_tier` / `controls.research_mode`
  (requirements §2.4a): `post_category` is one of `musings|photos|travel` (reflective),
  `learnings|movies|books|mba` (light-check), or `deep-dive` (journalistic) — blank
  (`""`) until Step 1 resolves it, never guessed. `rigor_tier` is the tier that maps to
  (`reflective|light-check|journalistic`), `null` until resolved. `research_mode` is
  `none|spot-check|deep` and is what `skills/step-2-research` actually branches on;
  defaults to `deep` (unchanged, full-rigor behavior) so a pre-existing run with no
  `post_category` set behaves exactly as before. Step 1 also overwrites
  `controls.adversarial_cap` per the §2.4a tier table for `reflective`/`light-check`
  runs (never for `journalistic`, which keeps whatever cap was already configured).
- `placeholders[]`: each `{ "id": str, "text": "[check stat] ...", "resolved": bool }`.
- `hypothesis.hardened_to_thesis`: false until Step 3 (requirements §4 Step 1/3).
- `escalation_history[]`: each `{ "gate": str, "target": str, "at": iso8601 }`, appended
  only by `gate-counter.sh`.
- `adversarial.ledger[]`: each `{ "claim": str,
  "verdict": "verified|wrong|unsupported|misrepresented", "load_bearing": bool }`.
- `originality` (Step 5, Pass 2 — plagiarism defense): `checked` (bool),
  `detection_guarantee` (`"source-comparison"` | `"internal-only"` | `null`), `corpus[]`
  (each `{ "source": str, "text": str }` — source excerpts the deterministic scan compares
  the draft against), and `flags[]`. Each flag: `{ "id": str, "passage": str (verbatim,
  as the draft read BEFORE the fix), "type":
  "verbatim-copy|close-paraphrase|unattributed-quote|uncredited-idea|structural-mimicry",
  "matched_source": str|null, "similarity": "high|medium|low", "severity":
  "blocking|advisory", "remedy": "quote-and-attribute|rewrite|attribute|remove", "ref_id":
  str|null, "resolved_note": str }`. Only the model (step-5-revise) writes this block;
  `originality-check.sh` reads it and gates on it but never mutates it.
- `controls.plagiarism_ngram`: minimum run of consecutive words the originality `scan`
  treats as a verbatim/near-verbatim match (default **8**, min 3). Detection sensitivity
  only — the ethical remedy is still chosen per passage.

---

## 5. `trigger.json` — trigger log (requirements §2.1, §3.5)

Lives at `<root>/input/<run_id>/trigger.json` (`<root>` = this same run's `paths.root`).
Written once by `init-run.sh`, never mutated. The immutable "record of intent".

```json
{
  "run_id": "20260715-00003-return-to-office-economics",
  "raw_subject": "The economics of return-to-office mandates",
  "slug": "return-to-office-economics",
  "timestamp": "2026-07-15T18:11:00Z",
  "controls": { "...": "the full resolved control set, same shape as state.controls" },
  "paths": { "root": "/absolute/path/to/runs-root" }
}
```

---

## 6. Adversarial loop (Step 8) — not part of `gate-counter.sh`

Bounded separately (requirements §5.2): min 1 / max 3 rounds for `light-check`/
`journalistic` runs, tracked in `state.adversarial.rounds`. Severity routing
(Unsupported→Step 2, peripheral-wrong→Step 5, load-bearing-wrong→Step 3/1) is enforced in
Phase 4, not by `gate-counter.sh`. Documented here only so Phase 1 authors know Step 8 is
deliberately out of the per-gate counter's scope.

**`reflective`-tier exception (requirements §2.4a):** the orchestrator skips Step 8
entirely for a `reflective` run — no reviewer dispatch, no `review-loop.sh` call. The
min-1 floor above does not apply to this tier. `state.adversarial` stays at its
`init-run.sh` default (`{rounds: 0, ledger: []}`); `make-manifest.sh` recognizes this case
(`rigor_tier == "reflective"` and `rounds == 0` with no `verification_guarantee` set) and
records `verification_guarantee: "skipped-reflective-tier"` — a distinct, honest value
from `"internal-consistency-only"`, since the latter would misstate why 0 rounds ran (a
deliberate choice, not an unavailable capability).

---

## 7. `originality-check.sh` interface (Step 5, Pass 2 — plagiarism defense)

Deterministic half of the originality & attribution pass. The model detects and remedies;
this script scans and **verifies the remedy landed**. It reads `state.originality` and the
draft; it never mutates state (the model owns `state.originality`).

```
scripts/originality-check.sh <state_path> <draft_path> verify   # (default)
scripts/originality-check.sh <state_path> <draft_path> scan
```

**`verify`** — for each `state.originality.flags[]` entry with `severity == "blocking"`:
- `remove` | `rewrite` → the `passage` must NO LONGER appear in the draft (normalized:
  lowercase, unified quotes, collapsed whitespace). Still present → **UNRESOLVED**.
- `quote-and-attribute` → the `passage` must appear **inside a `"…"` quotation span** in
  the draft. Present but unquoted → **UNRESOLVED**.
- `attribute` → `ref_id` must be non-null and exist in `state.references[]` (Step 5 Pass 1
  separately guarantees that reference is actually cited in the body). Missing →
  **UNRESOLVED**.
Advisory flags are reported, never fail. Exit **0** = all blocking flags resolved (the
Step 5 gate may pass); exit **3** = ≥1 unresolved (gate must fail and loop); exit 1 =
usage / unreadable inputs.

**`scan`** — a detection aid: reports draft spans sharing a run of ≥ `N` consecutive
normalized words with any `state.originality.corpus[]` excerpt (`N` from
`AW_PLAGIARISM_NGRAM`, else `controls.plagiarism_ngram`, else 8). An **empty corpus** is
reported as `detection_guarantee: "internal-only"` with no overlaps — never a false clean.
Always exits 0 (it informs the model; it does not gate). Prints JSON to stdout.

Self-contained: python3, no jq, **no network** (requirements §11), bash 3.2. Loop control
stays with the Step 5 gate (`gate-counter.sh step-5`) — this script only reports
resolved/unresolved, consistent with the deterministic/probabilistic split.

---

## 8. `make-manifest.sh` interface (requirements §2.2, §3.1a)

```
scripts/make-manifest.sh <run_id> [root_dir]
```

`root_dir` is this run's resolved root (`state.json.paths.root`) — the base under which
`interim/<run_id>/` and `output/<run_id>/` live. Defaults to `.` (current working
directory) when omitted, matching the original single-argument signature so pre-existing
callers and tests are unaffected. The orchestrator, which already read `state.json` to
reach the publish stage, always has `paths.root` on hand and passes it explicitly rather
than relying on the default. Self-guards on `status` exactly as before (§ README);
adding `root_dir` does not change the publish-stage check, only where it looks.
```
