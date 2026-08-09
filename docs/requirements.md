# Requirements: `article-writer` — Claude Code Plugin

**Version:** 0.3.0
**Type:** Claude Code plugin (skills + agents + hooks, optional bundled MCP)
**Execution model:** Scope is completed jointly by human and agent (shared responsibility); Claude executes the remaining steps; deterministic hooks enforce gates, caps, and folder structure.
**Trigger:** two-phase slash command — `/write-article <subject>` sets up the run and drops a scope template for the human; `/write-article continue` resumes the run and executes the workflow.

---

## 1. Overview & goal

`article-writer` turns a one-line subject into a publish-ready article by driving it through an 8-step workflow, where each step ends in a quality-assurance (QA) gate. It is a **batch tool**: it is run repeatedly to produce many articles over time, so every run is isolated into its own numbered folder set and never collides with prior runs.

The core design principle is a split of responsibility:

- **Probabilistic work** (judgement, writing, research, review) lives in **skills and agents** — Claude does it.
- **Deterministic guarantees** (loop caps, gate enforcement, folder allocation, state) live in **hooks and scripts** — the harness does it.

This split matters because the workflow's value comes from its gates being *reliable*. A model cannot be trusted to reliably stop its own loop, so the loop bound must be enforced outside the model.

A third principle governs **scope specifically**: it is a **human-agent handshake**, not agent-only work. The agent cannot know the intended audience, the preferred angle, or the author's constraints — those live only in the human's head. So the run is set up first, the human completes a scope template, and only then does the agent reconcile and execute. This prevents the silent-assumption failure where the agent guesses an audience and produces a technically-complete but wrong article.

### Non-goals
- Not a publishing/CMS integration — output is files, not a live post.
- Not a citation-manager replacement — it records sources, it does not format a house bibliography style.
- Not a one-shot single-article tool — batch operation is a first-class requirement.

---

## 2. Black-box model (inputs / outputs / controls)

Treating the plugin as a sealed unit, three kinds of thing cross its boundary.

### 2.1 Inputs (the commission)
The input is a **record of intent**, not the article. For each run it captures:

- the raw subject string, verbatim, exactly as typed after `/write-article`;
- the trigger timestamp;
- the resolved run identifier (`YYYYMMDD-NNNNN`) and slug;
- the full set of **control** values in effect for this run (defaults + any overrides).

The input is persisted so that every run is auditable and reproducible: you can always see what was asked, separately from what was produced. The input folder also holds the **scope template** (§3.7) — blank when Phase A drops it, human-completed before Phase B — which is the human's half of the Step 1 handshake.

### 2.2 Outputs (the deliverables)
Only things worth keeping or shipping:

- the final, publish-ready article;
- the source/citation list (each cited source, with enough to relocate it and its quality tier);
- a run **manifest** summarising what happened: number of adversarial rounds, which escalations fired, final verdict, and per-gate iteration counts.

### 2.3 Interim (the work-in-progress — stays inside the box)
Everything generated during transformation that is not a deliverable:

- the working hypothesis (provisional; see §4 Step 1);
- research notes, with each claim bound to its source and quality tier;
- the outline;
- the ugly first draft;
- the `[check stat]` placeholder register;
- **run state**: current step, per-gate iteration counters, escalation history.

Interim is kept strictly separate from output so that "what we keep" is never polluted by "how we got there."

### 2.4 Controls (the tuning knobs)
Each control changes how the same input transforms into output. All have defaults so the bare command stays a one-liner; each is overridable per run or via plugin `userConfig`.

| Control | Default | Effect |
|---|---|---|
| Target reader / audience | general informed reader | Reshapes scope, vocabulary, depth |
| Angle / stance override | auto-chosen | Lets the author fix the angle instead of deriving it |
| Length / format target | medium article | Constrains scope and structure |
| Tone / voice | neutral, plain | Register and formality |
| Source policy (whitelist / blacklist) | see §6 | What evidence is admissible |
| Source-quality threshold | peer-reviewed / reputable only | Minimum tier a load-bearing claim may rest on |
| Per-gate iteration cap | 3 | Max retries per QA gate before escalation |
| Adversarial review cap | max 5, min 1 | Bounds the Step 8 review loop |
| Escalation routing | as specified §5 | Where a capped/failed gate sends the work |
| Runs root directory (`output_root`) | current working directory | Absolute path where all run folders (`input/`, `interim/`, `output/`) are stored. Lets runs persist in a durable, synced location instead of wherever the agent happened to be launched from — see §3.1a |

### 2.5 External dependency (declared, not hidden)
Steps 2 and 8 require **independent source access** (web search or an equivalent fact-check capability). This is not an input or a control — it is a **precondition** the plugin needs from its environment. If unavailable, the plugin can only check internal consistency, not external truth, and must say so rather than imply verification it did not perform.

---

## 3. Run initialization & folder structure

### 3.1 The three folders
On invocation, under the **run root** (§3.1a), the plugin ensures these exist:

```
input/      # one subfolder per run: the commission / trigger log
interim/    # one subfolder per run: WIP + state
output/     # one subfolder per run: deliverables
```

### 3.1a Run root (`output_root` control)

By default the run root is the current working directory (the directory the agent is run
from) — this was the only behavior before the `output_root` control existed, and remains
the default with it blank. If `output_root` is set to an absolute path, that path becomes
the run root instead: `init-run.sh` creates it if missing, resolves it to an absolute
path, and records it as `paths.root` in both `trigger.json` and every run's `state.json`.

This exists because "the directory the agent is run from" is not always a stable,
persistent location — a session may be launched from a temporary or sandboxed working
directory that is cleaned up afterward, which would otherwise silently lose completed
runs and their deliverables. Pointing `output_root` at a durable, synced folder (e.g. a
OneDrive- or Dropbox-backed directory) makes runs outlive the session that produced them.

A run's root is fixed at the moment it is created (`paths.root` in its own `state.json`)
and does not change if `output_root` is edited later or a later session's working
directory differs — every component that resumes or references an existing run reads
`paths.root` from that run's own state rather than re-deriving the currently-configured
root. A run created before this control existed has no `paths.root` field; treat that as
"this run's root is the current working directory" for backward compatibility.

### 3.2 Run identifier and folder naming
Each run gets one identifier used as the **shared folder name across all three** top-level folders:

```
YYYYMMDD-NNNNN-<slug>
```

Example: `20260715-00003-return-to-office-economics`

- **`YYYYMMDD`** — trigger date. Chosen because it sorts lexicographically the same way it sorts chronologically, keeping listings in date order automatically.
- **`NNNNN`** — zero-padded 5-digit sequence, **scoped per day**. Resets to `00001` each new date.
- **Leading zeros are mandatory.** Without them the OS sorts `1, 10, 11, 2, …`. Five digits sorts correctly to 99,999 runs/day.
- **`<slug>`** — a filesystem-safe, shortened label derived from the subject: lowercased, spaces → hyphens, punctuation stripped, collapsed hyphens, truncated to ~40 characters. The slug is only a label; the full subject is preserved verbatim in the input log.

The identical `YYYYMMDD-NNNNN-<slug>` name appears under `input/`, `interim/`, and `output/`, so one article's commission, working files, and deliverable line up by name across the three.

### 3.3 Sequence allocation
The next `NNNNN` is allocated by scanning existing folders **that share today's `YYYYMMDD` prefix**, taking the maximum sequence, and incrementing. This survives across sessions (it reads the filesystem, not memory) and never collides within a day.

### 3.4 Duplicate-subject handling (warn and ask)
Before allocating, the plugin scans **all existing runs across all dates** for a **slug match** (slug, not exact subject, so trivially reworded subjects are still caught).

- If a match is found, the plugin **halts and asks** the user, showing the matched folder: **reuse** it / create a **new** numbered run / **cancel**.
- Because of this, the trigger is not guaranteed fully unattended: a single slash command still starts it, but it may ask one question before proceeding on a collision.

### 3.5 Trigger log (contents of `input/<run>/`)
A single log record written at trigger time containing: raw subject (verbatim), derived slug, timestamp, resolved run id, and the full control set in effect. This is the "record of intent" from §2.1.

### 3.6 Two-phase command model

The workflow is split into **setup** and **execution** so scope can be a human-agent handshake (§4 Step 1).

**Phase A — `/write-article <subject>`** (setup only; does *not* start writing):
1. Capture the raw subject verbatim + timestamp.
2. Derive the slug; run the §3.4 duplicate check (warn and ask on slug match).
3. Allocate `YYYYMMDD-NNNNN` and create the `input`/`interim`/`output` triplet.
4. Write the trigger log **and** the blank **scope template** (§3.7) into `input/<run>/`.
5. Initialize the state file with status `awaiting-scope`.
6. Stop, and tell the human the template path to complete.

**Phase B — `/write-article continue`** (general resume verb):
- Continues a run **from whatever step the state file says it reached** — this is not scope-specific. The same verb resumes a run sitting after Phase A *and* a run interrupted mid-Step-5.
- **Run selection:** a run is *resumable* if it is set up but not yet published (status anywhere from `awaiting-scope` through in-progress). If exactly one run is resumable, continue it. If more than one is resumable, **list them and ask** which to resume.
- If the run is at `awaiting-scope`, Phase B first reads the completed template and runs the Step 1 reconciliation (§4 Step 1). **Mandatory-field hard-stop:** if any mandatory template field is blank, the agent does **not** proceed or guess — it lists exactly which fields are missing and stops, leaving the run at `awaiting-scope`.

### 3.7 Scope template (dropped into `input/<run>/`)

A human-completed form capturing what only the human knows. Mandatory fields hard-stop Phase B if blank; optional fields the agent may propose values for during reconciliation.

**Mandatory:**
- **Audience / target reader** — who this is for, and their assumed knowledge level.
- **Purpose / desired takeaway** — what the reader should believe, understand, or do afterward.

**Optional (agent may propose if blank):**
- **Angle / stance** — a preferred lens, if the human has one.
- **Length / format target.**
- **Tone / voice.**
- **Must-include points** — anything that has to appear.
- **Must-avoid points / constraints** — anything off-limits.
- **Source-policy overrides** — deviations from the §6 defaults.

The template is the human's half of the Step 1 handshake; the raw subject from Phase A is preserved separately in the trigger log.

---

## 4. Behavioral requirements — per step

Each step has: an **entry precondition**, **subprocess actions**, an **exit gate** (pass/fail question), and **outputs** written to `interim/` (or `output/` at the end). Steps do not advance while their gate is unpassed (subject to §5 caps).

### Step 1 — Define scope *(shared human-agent responsibility)*
- **Entry precondition:** the human has completed the scope template (§3.7); Phase B has read it.
- **Responsibility split:**
  - *Human owns* (only they know these): audience, purpose/takeaway, angle preference, must-include / must-avoid, constraints.
  - *Agent owns* (it's better at these): stress-testing the one-sentence thesis, catching an over-broad scope, checking the angle has friction, surfacing contradictions in what the human asked for.
- **Reconciliation actions:** take the human's template as the authoritative spec; propose values for any *optional* fields left blank (for human awareness, not silent substitution); flag tensions (e.g. "audience = policymakers but angle is highly technical — which wins?"); interrogate the topic to find the narrower piece; set a **provisional working hypothesis / central question** — explicitly *not* a locked takeaway.
- **Mandatory-field hard-stop:** if a mandatory template field is blank, do **not** proceed or guess — list the missing fields and stop (run stays `awaiting-scope`).
- **Anti-bias requirement:** the hypothesis is provisional to avoid confirmation bias. It must not harden into a takeaway until after Step 2.
- **Exit gate (passed jointly):** *One clean sentence?* — angle + reader + hypothesis in a single non-vague sentence, consistent with the human's template. The agent does not pass this gate on the human's behalf while mandatory inputs are missing.
- **Outputs:** reconciled scope record, working hypothesis.

### Step 2 — Research deeply
- **Actions:** map the territory wide-but-shallow first; go to primary sources, tracing claims to their root; actively hunt disconfirming evidence (find the strongest opponent); triangulate across **independent** sources; capture as you go.
- **Source policy:** obey the whitelist/blacklist and quality threshold in §6.
- **Stop when:** saturation (new sources stop surprising you); every part of the thesis, including objections, is arguable from evidence; the article's *scope* is covered (not the whole topic).
- **Probe further when:** a surprise; a source conflict; a load-bearing claim; an unsourced "everyone knows" consensus.
- **Documentation requirement:** paraphrase in own words (comprehension + plagiarism defense); attach a source **and quality tier** to every claim; keep facts, sources, and own-thinking visibly separate; organize notes around **questions/claims, not sources**.
- **Source-independence requirement:** verify that multiple supporting sources are genuinely independent origins, not the same origin repeated.
- **Exit gate:** *Key claims sourced + counter-evidence found?*
- **Outputs:** research notes (claim → source → tier), open-questions list, updated/confirmed hypothesis.

### Step 3 — Find the structure
- **Actions:** extract defensible claims from the research (**the hypothesis now becomes a settled thesis**, or is revised to fit findings); find the single through-line; sequence by reader dependencies (not discovery order); design the opening tension and closing payoff (mark their jobs, don't write them yet); outline one line per section.
- **Exit gate:** *Every claim on-spine & backed?* (no orphan claims; nothing off the through-line).
- **Outputs:** outline with claim→evidence mapping.

### Step 4 — Draft fast and ugly
- **Actions:** silence the editor (no rereading/polishing this pass); follow the outline but let it flex; drop `[check stat]` placeholders instead of stopping; skip hard parts and return; reach the end at all costs.
- **Exit gate (completeness only, by design):** *Complete draft, placeholders still visible?* — deliberately **not** a quality check, to protect drafting momentum.
- **Outputs:** complete rough draft; populated placeholder register.

### Step 5 — Revise in passes
- **Actions, ordered destructive → fine so polished work is never thrown away:**
  1. **Clear verification first** — resolve `[check stat]` markers and re-confirm load-bearing claims *before* touching structure.
  2. **Originality & attribution (plagiarism defense)** — detect passages that copy or lean too closely on a source, or borrow an idea/framing without credit, and apply an ethical remedy per passage: **quote-and-attribute** (wrap a notable verbatim statement in quotation marks and cite it), **rewrite** (genuinely re-express borrowed phrasing in your own words), **attribute** (cite the source of a reworded idea), or **remove** (cut it, or re-source — never attribute to a blacklisted source). This is the check that Step 2's "paraphrase in your own words" actually happened, with the fix where it did not. It runs before the structural pass because its remedies reshape the prose. The chosen remedy is **deterministically verified to have landed in the draft** (`scripts/originality-check.sh verify`) before the gate may pass — a copied passage still present, or a "quote" that isn't quoted, keeps the gate failed. Detection compares against captured source excerpts (and independent search where available); with no source text it can only read the draft against itself and must say so, never implying originality it did not check.
  3. Structural pass — does the argument flow? cut anything off the through-line.
  4. Paragraph pass — one clear point each.
  5. Sentence pass — clarity, rhythm, filler; read aloud.
  6. **Proofreading last** — typos, punctuation, formatting (the pass whose work is most easily undone by the ones above).
- **Note on terminology:** "proofreading" is surface polish and comes last; *verification* of truth is a separate concern handled first here and, ideally, back in Step 2.
- **Exit gate:** *Each pass's defect class cleared?*
- **Outputs:** revised draft.

### Step 6 — Sharpen open and close
- **Actions:** rewrite the intro **last**, to match what the piece became; make the hook create tension; check the opening's promise matches the ending's payoff and realign whichever drifted; land the ending on an implication/turn, not a summary; test the seams (intro→body, body→close) as continuous reads.
- **Exit gate:** *Promise matches payoff?*
- **Outputs:** final opening and closing fused to the body.

### Step 7 — Rest, then second eyes
- **Actions:** let it sit (ideally overnight) to gain distance; reread cold as a reader, marking confusion/boredom; get an outside reader and ask where they lost the thread; separate signal from noise (fix genuine confusion, not every preference); final read.
- **Exit gate:** *Cold-read confusions resolved?*
- **Outputs:** near-final article ready for adversarial review.

### Step 8 — Adversarial review gate (see §5.2 for the loop)
- **Actions:** invert the goal — the reviewer tries to make the piece **fail**, not help it (best run as an isolated agent so it doesn't inherit the author's assumptions); extract every checkable claim **afresh, ignoring the author's markers**; **re-source each claim independently — never reuse the author's citation**; check each claim actually matches its source (catch overstatement, stripped caveats, correlation-as-causation); attack load-bearing claims hardest with multiple confirmations; **classify** each claim as `verified / wrong / unsupported / misrepresented`.
- **Honesty requirement:** independent sourcing checks *external truth*; a reviewer sharing the author's sources can only check *internal consistency*. The manifest must state which guarantee was actually obtained.
- **Outputs:** classified claim ledger; routing decision (§5.2); on success, the published article + sources + manifest to `output/`.

---

## 5. Gate & loop control requirements (the deterministic core)

Specified separately from behavior because these must be **enforced by hooks/scripts, not model self-report**. Iteration counts are read from and written to the run **state file** in `interim/`.

### 5.1 Per-step QA gates (Steps 1–7)
- Each gate is a single pass/fail question (§4).
- On **fail**: loop back **within the step**, incrementing that gate's counter.
- **Cap = 3** (control-configurable). On the 3rd consecutive fail, do **not** loop a 4th time — **escalate** to an earlier step, because repeated local failure signals a deeper upstream defect.
- **Escalation targets** (as drawn in the flowchart):

  | Failing gate | Escalates to | Rationale |
  |---|---|---|
  | Step 1 scope | halt & flag run for human input | nothing upstream of scope to fix |
  | Step 2 research | Step 1 | scope may be unresearchable as framed |
  | Step 3 structure | Step 2 | can't build a spine on thin research |
  | Step 4 draft | Step 3 | can't draft against a broken outline |
  | Step 5 revise | Step 3 | structural defects surfacing in revision |
  | Step 6 open/close | Step 5 | ends won't fuse to an unstable body |
  | Step 7 second-eyes | Step 5 | reader confusion is usually a revision issue |

- Gates must stay lightweight (a single fast question), so they act as tripwires, not mini-reviews. Step 8 is the one heavyweight gate.

### 5.2 Adversarial loop (Step 8)
- **min 1** review always runs; **max 5** (control-configurable).
- Early-stop condition: a review finds **nothing substantive** left to attack. Cosmetic nitpicks do **not** count as a reason to loop — only substantive weaknesses do.
- **Severity-based routing**, driven by the fact-check verdict, each returning to a different step then re-entering the gate:

  | Verdict | Routes to | Why |
  |---|---|---|
  | Unsupported (no independent source found) | Step 2 | research didn't finish — source it or cut it |
  | Wrong, peripheral | Step 5 | correct in place, re-review |
  | Wrong / misrepresented, **load-bearing** | Step 3 (or Step 1) | thesis rests on a false premise — rebuild, or rethink the angle |

- If real problems persist at review 5, that signals a deep structural flaw: drop to Step 1/3 rather than publishing.
- **Reverting to Step 5 does not, by itself, fix false claims.** Step 5 only re-checks *flagged* claims; a confidently-held false claim was never flagged. Independent re-sourcing in Step 8 (and finishing verification in Step 2) is what catches those. The requirements must not treat a Step-5 loop as a substitute for independent fact-checking.

### 5.3 Enforcement
- All caps and counters are enforced by a deterministic `command` hook maintaining the state file. The model may *perform* a gate's judgement (a skill, or a `prompt`/`agent` hook), but may not be the thing that decides whether the loop is allowed to continue.

---

## 6. Source policy (whitelist / blacklist)

Default policy for research (Steps 2 and 8). Overridable per run via the source-policy control, but these are the shipped defaults.

> **Implementation note:** the machine-readable, single-source-of-truth version of this policy lives at `config/source-policy.json`. It is enforced deterministically by `scripts/source-check.sh` and read as guidance by `skills/step-2-research` and `agents/adversarial-reviewer`. Edit the policy there; keep this section as the human-readable spec it derives from.

### 6.1 Blacklist — excluded by default
Do **not** rely on, and do not cite as load-bearing:

- personal or company **blogs** and opinion posts;
- **marketing / promotional / PR** material;
- **propaganda**, whether **government** or **corporate**;
- content farms, SEO filler, and undated aggregators;
- circular sources (multiple outlets all quoting one unverified origin);
- forums and social posts as evidence (may be used only as leads to trace to a primary source).

### 6.2 Whitelist — preferred by default
Actively seek and prefer:

- **peer-reviewed research** and meta-analyses;
- **reputable journals** and established, editorially-accountable publications;
- **primary data** and official statistical/records sources (used critically, not as propaganda);
- reputable, independent long-form journalism;
- primary documents (the actual study/dataset/filing behind a claim).

### 6.3 Tiering requirement
Every recorded source carries a **quality tier**. A **load-bearing** claim must rest on a whitelisted, sufficiently high tier; if only a blacklisted or low-tier source exists, the claim is treated as **unsupported** and must be independently re-sourced or cut (routes per §5.2).

---

## 7. Component inventory (technical interface)

Mapping workflow → Claude Code plugin components. Directory layout (all components at plugin **root**, only `plugin.json` inside `.claude-plugin/`):

```
article-writer/
├── .claude-plugin/
│   └── plugin.json                 # manifest (name, version, userConfig controls)
├── commands/
│   └── write-article.md            # /write-article (setup) + continue (resume) entry
├── skills/
│   ├── orchestrator/SKILL.md       # runs Steps 1–8, manages state
│   ├── step-1-scope/SKILL.md
│   ├── step-2-research/SKILL.md
│   ├── step-3-structure/SKILL.md
│   ├── step-4-draft/SKILL.md
│   ├── step-5-revise/SKILL.md
│   ├── step-6-sharpen/SKILL.md
│   └── step-7-second-eyes/SKILL.md
├── agents/
│   └── adversarial-reviewer.md     # Step 8, isolated context, re-sources independently
├── hooks/
│   └── hooks.json                  # gate enforcement, cap counting, folder init
├── scripts/
│   ├── init-run.sh                 # allocate YYYYMMDD-NNNNN, slug, 3 folders, dup-check
│   ├── gate-counter.sh             # read/increment/reset per-gate counters; enforce cap=3
│   ├── source-check.sh             # optional: validate source tiers against policy
│   └── originality-check.sh        # Step 5: scan draft/source overlap; verify remedy landed
└── CHANGELOG.md
```

- **Steps** are skills (each `SKILL.md` carries that step's subprocess from §4).
- **Orchestrator** is a skill/agent coordinating the run and reading/writing state.
- **Step 8** is an **agent** (subagent) for isolated context — so it genuinely re-derives verification rather than reusing the author's notes.
- **Gates/caps/folder allocation** are **hooks + scripts** (deterministic).
- The `/write-article` trigger is a `commands/*.md` skill (kebab-case, matching the skill `name`); Phase A may ask the §3.4 duplicate question and Phase B the §3.6 run-selection question via elicitation.

*(Component model verified against current Claude Code plugin reference: components live at plugin root; hooks support `command`/`http`/`mcp_tool`/`prompt`/`agent` types; agents support isolated context. Confirm exact frontmatter fields against the live docs at build time, as the schema evolves.)*

---

## 8. Data & state contract

The run **state file** (e.g. `interim/<run>/state.json`) is the working memory passed between steps. It must hold at least:

- run id, slug, raw subject, timestamps;
- **the run's root directory** (`paths.root`, §3.1a) — the absolute base for this run's
  `input/`, `interim/`, `output/` folders, fixed at creation and never re-derived from a
  later session's working directory or a subsequently-edited `output_root` control;
- **run status** (`awaiting-scope` → in-progress per step → `published`), used by `continue` to resume and to decide resumability;
- whether the scope template has been completed, and which mandatory fields (if any) are still blank;
- active control values;
- current step and status;
- the working hypothesis (and whether it has hardened into a thesis);
- research notes index (claim → source → tier), and the open-questions list;
- the `[check stat]` placeholder register and their resolution status;
- **per-gate iteration counters** and **escalation history**;
- adversarial-round count and the classified claim ledger.

Rules:
- Every step reads state on entry and writes it on exit.
- Counters are only ever mutated by the deterministic hook/script, never by free-text model output.
- Nothing scratch leaks into `output/`; deliverables are copied/written there only at successful completion.

---

## 9. Interfaces

- **Invocation (two-phase):** `/write-article <subject>` sets up the run and writes the scope template (may ask the duplicate-collision question); `/write-article continue` resumes a run from its current step (asks which run if more than one is resumable; hard-stops if mandatory scope fields are blank).
- **Controls at runtime:** overridable via flags/args or `userConfig` (audience, angle, length, tone, source policy, quality threshold, per-gate cap, adversarial cap, escalation routing).
- **Required capability:** independent source access (web search / fact-check) for Steps 2 and 8; degrade honestly if absent (§2.5).

---

## 10. Acceptance criteria (falsifiable)

A gate that fails 3× **escalates rather than looping a 4th time**, per the §5.1 routing table.
The Step 8 reviewer **re-sources claims without reading Step 2's citations**.
**No step proceeds while its `[check stat]` markers are unresolved** past Step 5's verification pass.
Article numbers **reset to `00001` per day** and carry a `YYYYMMDD` prefix.
Folder names **sort chronologically** in the OS with no leading-zero breakage, across all three folders.
A **slug collision halts and prompts** (reuse / new / cancel) rather than silently overwriting.
Every load-bearing claim rests on a **whitelisted, sufficiently-tiered source**; otherwise it is flagged unsupported and routed per §5.2.
The Step 5 originality pass will **not pass its gate while a flagged copied passage is still present unquoted, or an "attribute" remedy lacks a real cited reference** — remedy landing is verified against the draft text by the deterministic hook, not by model assertion.
The run **manifest** states how many adversarial rounds ran, which escalations fired, and whether external truth or only internal consistency was verified.
Blacklisted source types (blogs, marketing, government/corporate propaganda) **do not appear as load-bearing citations** in `output/`.
Iteration counters in state are **only mutated by the deterministic hook**, never by model free-text.
`/write-article <subject>` **creates folders and a scope template but does not begin writing**; only `/write-article continue` executes the workflow.
A blank **mandatory** scope field (audience or purpose) causes `continue` to **hard-stop and list the missing fields**, leaving the run at `awaiting-scope` — the agent never guesses them.
`continue` resumes from the run's **current step** (general resume), and **asks which run** when more than one is resumable.

---

## 11. Non-functional & safety

- **Bounded everywhere:** no unbounded loops — every gate is capped (per-gate 3, adversarial 5). This is the whole reason caps are enforced deterministically.
- **Trust note:** plugin hooks and scripts run real code on the user's machine at the same trust level as the shell. The plugin should ship with reviewable scripts and no hidden network calls beyond the declared source-access capability.
- **Honest scope limits:** the plugin can only verify *external truth* where it has independent source access; otherwise it must clearly report that it checked only internal consistency, and must not imply fact-checking it did not perform.
- **Auditability:** the `input/` commission plus the `output/` manifest together make every run reconstructable after the fact.
- **Reproducibility caveat:** identical inputs + identical controls should yield a comparable process, but generative steps are not bit-for-bit deterministic; the manifest, not byte-equality, is the record of what happened.

---

## 12. Open questions / to confirm at build time
- Exact `SKILL.md` / agent frontmatter fields against the current Claude Code schema (evolves between releases).
- Whether the orchestrator is best as a skill or a long-running agent given context-window limits across 8 steps.
- Slug truncation length and collision-within-slug handling (e.g. two different subjects producing the same 40-char slug on the same day).
- Where `state.json` should live if a run is resumed in a later session (it is in `interim/`, but resumption semantics need defining).