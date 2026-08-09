# Article Writer

A Claude Code plugin that turns a one-line subject into a publish-ready article by driving
it through an **8-step, gated workflow** with **deterministic loop caps** and an
**adversarial fact-check** review. Built as a batch tool: every run is isolated into its
own numbered folder set.

**Docs:** [`docs/requirements.md`](docs/requirements.md) (full spec) ·
[`docs/contracts.md`](docs/contracts.md) (state/interface contracts) ·
[`docs/architecture-decision.md`](docs/architecture-decision.md) (why gating is split the
way it is, and the honest limit of that guarantee) ·
[`docs/high-level.html`](docs/high-level.html) (workflow diagram).

## Core design: probabilistic vs. deterministic split

- **Judgement, writing, research, review** live in **skills and agents** — Claude does them.
- **Loop caps, gate enforcement, folder allocation, state** live in **hooks and scripts** —
  the harness does them. A model can't be trusted to reliably stop its own loop, so the
  bound is enforced outside the model.

## Usage (two-phase)

```
/write-article <subject>     # Phase A: set up a run, drop a scope template — does NOT write
/write-article continue      # Phase B: resume a run from its current step and execute
```

Phase A allocates the run and stops; you complete the scope template (mandatory: audience,
purpose), then Phase B reconciles scope and runs Steps 1–8. Runs live under the **run
root** — the current working directory by default, or a persistent path you configure via
the `output_root` control (see *Controls* below) — in `input/` (commission), `interim/`
(WIP + state), `output/` (deliverables), each with a per-run subfolder named
`YYYYMMDD-NNNNN-<slug>`.

## The 8 steps

1. **Define scope** — human-agent handshake; provisional hypothesis.
2. **Research deeply** — primary sources, counter-evidence, claim→source→tier.
3. **Find structure** — hypothesis hardens into thesis; through-line + outline.
4. **Draft fast and ugly** — completeness only; `[check stat]` placeholders.
5. **Revise in passes** — verification → **originality & attribution** → structural → paragraph → sentence → proof.
6. **Sharpen open & close** — intro rewritten last; promise matches payoff.
7. **Rest, then second eyes** — cold read; signal vs. noise (run is resumable for real rest).
8. **Adversarial review** — isolated agent re-sources claims independently and classifies them.

Steps 1–7 each end in a lightweight QA gate (cap 3 → escalate upstream). Step 8 is the one
heavyweight gate: min 1 / max 5 reviews with severity-based routing.

## Components

```
article-writer/
├── .claude-plugin/plugin.json        # manifest + userConfig controls (§2.4)
├── commands/write-article.md         # two-phase entry & routing
├── skills/
│   ├── orchestrator/                 # drives Steps 1–8, obeys the scripts
│   ├── step-1-scope … step-7-second-eyes
├── agents/adversarial-reviewer.md    # Step 8, isolated, re-sources independently
├── hooks/hooks.json                  # PreToolUse guard on deliverable writes
├── scripts/                          # the deterministic core (see below)
├── templates/scope-template.md       # the human's scope form
├── docs/                             # spec, contracts, architecture decision, diagram
└── tests/                            # runnable verification harnesses
```

### What this plugin runs on your machine

Installing it registers **one hook**: a `PreToolUse` matcher on
`Write|Edit|MultiEdit|NotebookEdit` that runs [`scripts/gate-guard.sh`](scripts/gate-guard.sh)
(15s timeout). On every file write, that script reads the run's `state.json` and denies
writes into `output/<run>/` unless the pipeline legitimately reached the publish stage. It
is the enforcement mechanism described above, and it is ~100 lines of reviewable bash. It
reads state and writes nothing; writes outside `output/` are passed straight through.

No script in this repo makes a network call, spawns a background process, or writes outside
the run folders under the resolved run root (the current working directory by default, or
the `output_root` you configure).

### Deterministic scripts (the enforcement core)
| Script | Role |
|---|---|
| `init-run.sh` | Resolve the run root (`output_root` or cwd), allocate `YYYYMMDD-NNNNN`, derive slug, create the 3 folders, dedup-check, init state. |
| `gate-counter.sh` | Sole mutator of per-gate counters; escalates at the cap per the §5.1 routing table. |
| `gate-guard.sh` | `PreToolUse` backstop — blocks deliverable writes to `output/` before the publish stage. |
| `review-loop.sh` | Step 8 loop control: round counting, min/max bound, severity routing. |
| `make-manifest.sh` | Emits article (.docx) + sources + references + run manifest (self-guards on status). |
| `source-check.sh` | Validates load-bearing claims rest on a whitelisted, sufficiently-high tier (§6). |
| `originality-check.sh` | Step 5 plagiarism defense: `scan` finds n-gram overlap vs captured source text; `verify` confirms each flagged passage's ethical remedy (quote-and-attribute / rewrite / attribute / remove) actually landed in the draft before the gate may pass. |
| `format-references.sh` | Renders structured `references[]` into the chosen citation style (in-text + bibliography). |
| `to-docx.sh` | Converts the final Markdown article to `.docx` (pandoc, python-docx fallback). |

All scripts are self-contained, use `python3` for JSON (no `jq` dependency), and make
**no network calls** — the only external capability the plugin uses is the declared
independent source access (web search/fetch) in Steps 2 and 8.

## Controls

Every tuning knob (audience, angle, length, tone, source policy, quality threshold,
per-gate cap, adversarial cap, escalation routing) has a default and is overridable via the
manifest `userConfig` or per run. See `plugin.json`.

**Runs root (`output_root`).** By default, runs are stored under `input/`, `interim/`,
`output/` in whatever directory Claude was launched from — which can be a temporary or
sandboxed session directory that disappears afterward. Set `output_root` to an absolute,
persistent path (e.g. a OneDrive- or Dropbox-synced folder) to keep every run there
instead. `init-run.sh` creates the directory if needed and records it as `paths.root` in
that run's `trigger.json`/`state.json`; the root a run was *created* with is what it keeps
for its lifetime, even if `output_root` is changed later or a later session's working
directory differs. Runs created before this control existed keep working unchanged
(resolved as "root = current working directory").

## Verification

Deterministic behaviour is covered by runnable harnesses:

```bash
bash tests/phase1-core.sh        # allocation, per-day reset, slug halt, cap-3 escalation
bash tests/phase2-guard.sh       # PreToolUse guard blocks premature deliverable writes
bash tests/phase4-review.sh      # adversarial loop routing/cap/min, manifest emission
bash tests/phase-originality.sh  # Step 5 plagiarism scan + remedy-landed verification
bash tests/phase6-refs-docx.sh   # citation formatting, docx conversion
bash tests/phase7-output-root.sh # output_root: custom root, dedup/sequence scoping, backward compat
bash tests/acceptance.sh         # every requirements §10 acceptance criterion
```

## Honest limits

The plugin verifies **external truth** only where it has independent source access;
otherwise it checks **internal consistency** only, and the run manifest says which was
obtained — it never implies fact-checking it did not perform. All loops are bounded
(per-gate 3, adversarial 5), enforced by scripts, not model self-report.

**Originality:** the Step 5 originality pass detects copying by comparing the draft against
the source excerpts the run captured (and independent search where available); with no
captured source text it can only read the draft against itself and records
`internal-only`, never a false "clean". The deterministic verifier confirms an ethical
remedy (quote-and-attribute / rewrite / attribute / remove) actually landed in the draft
text — the model cannot clear the gate by asserting a passage is fixed — but it runs at
Step 5, so the intros/closes that Steps 6–7 rewrite afterward warrant a final read (the
manifest flags this). It is a plagiarism *defense*, not a certified originality score.

## Installation

**Requirements:** Claude Code, `bash`, `python3`. Optional: `pandoc` or `python-docx` for
`.docx` output (without either, the run keeps `article.md` and says so).

From GitHub (the canonical marketplace location):

```
/plugin marketplace add utikku1993/article-writer
/plugin install article-writer@article-writer
```

Already have it installed from a local marketplace source instead? Point it at GitHub
without losing your run history: `/plugin marketplace remove article-writer` (the old
local source), then run the two commands above. Runs live under `output_root`/the
working directory, not inside the plugin's own install path, so switching marketplace
sources doesn't touch them.

To pick up new commits after the initial install, run `/plugin marketplace update
article-writer` followed by `/reload-plugins` (or restart Claude Code) — same as any
other update.

For local development instead, clone the repo, then run `/plugin`, add the folder as a
local marketplace source, and enable `article-writer`.

## Contributing

Deterministic behaviour is contract-first: [`docs/contracts.md`](docs/contracts.md) is
authoritative for `state.json` and the gate interfaces, and every script cites the spec
section it implements. Changes to the enforcement core should come with a test in
`tests/` — the existing harnesses cover 136 checks and are expected to stay green.

## License

MIT — see [LICENSE](LICENSE).
