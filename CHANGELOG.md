# Changelog

All notable changes to the `article-writer` plugin are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.4.2] — 2026-08-09

### Changed
- **Marketplace location is now GitHub.** `plugin.json` gained `repository`/`homepage`
  pointing at `https://github.com/utikku1993/article-writer`. README installation
  instructions replaced the `<your-github-user>/ArticleWriter` placeholder with the real
  `utikku1993/article-writer`, and now cover switching an existing local-marketplace
  install over to the GitHub source (`/plugin marketplace remove article-writer` then
  re-add from GitHub) without affecting any run's `input`/`interim`/`output` folders,
  which live under `output_root`/the working directory — never inside the plugin's own
  install path — so they are untouched by where the plugin itself is installed from.

## [0.4.1] — 2026-08-09

### Fixed
- **`output_root` was never actually reaching `init-run.sh` — runs kept landing under
  whatever the ambient working directory was (e.g. an ephemeral session scratchpad),
  not the configured OneDrive path.** Root cause: `commands/write-article.md` told
  Claude to "read the `output_root` control... however your run's control overrides
  are supplied" — a placeholder instruction with no real mechanism behind it, so
  `AW_OUTPUT_ROOT` was never actually exported and `init-run.sh` silently fell back to
  its documented cwd default. The real mechanism (confirmed against the current Claude
  Code plugin reference) is that non-sensitive `userConfig` values are substituted
  directly into skill/command markdown content as `${user_config.KEY}` before Claude
  ever reads the file — there is no separate runtime lookup to perform.
  `commands/write-article.md` § *Resolving the run root* now embeds the literal
  `${user_config.output_root}` token so Claude Code performs that substitution, and
  explicitly guards against passing the unsubstituted placeholder string through if
  something upstream is too old to substitute it. (Note this only applies to
  `commands/*.md` and `skills/*/SKILL.md` content — `CLAUDE_PLUGIN_OPTION_<KEY>`
  environment-variable auto-injection is a separate mechanism that only reaches
  registered **hooks**, e.g. `gate-guard.sh`, not arbitrary Bash calls a skill makes
  mid-instruction; `gate-guard.sh` doesn't need `output_root` anyway, so it was
  unaffected by this bug.) No script changed — `init-run.sh`'s `AW_OUTPUT_ROOT` handling
  from 0.4.0 was already correct; only the thing that was supposed to set it was broken.

## [0.4.0] — 2026-08-09

### Added
- **`output_root` control — persistent, configurable runs directory (requirements
  §2.4/§3.1a).** All run folders (`input/`, `interim/`, `output/`) previously lived
  strictly under the current working directory, which is fine when that's a stable
  location but silently loses runs when Claude is launched from a temporary/sandboxed
  session directory that gets cleaned up. `output_root` (a plugin `userConfig` string,
  default blank = unchanged behavior) lets you point every run at a durable, persistent
  path — e.g. a OneDrive-synced folder — instead. `init-run.sh` resolves it (via
  `AW_OUTPUT_ROOT`), creates the directory if missing, always resolves it to an absolute
  path, and records it as `paths.root` in that run's `trigger.json`/`state.json` — the
  root a run is *created* with is the root it keeps for its lifetime, independent of any
  later change to the control or a later session's working directory. `make-manifest.sh`
  gained an optional `[root_dir]` second argument (defaults to `.`, so existing callers
  and tests are unaffected). `commands/write-article.md`, `skills/orchestrator`, all
  seven `skills/step-N-*`, and `agents/adversarial-reviewer` were updated to resolve and
  thread `<root>` through every `input/`/`interim/`/`output/` path reference instead of
  assuming the current working directory. `gate-guard.sh` needed **no change** — its
  `PreToolUse` matching is already path-pattern-based, not cwd-based, so it enforces the
  publish-stage guard correctly regardless of where the run root is. Backward compatible:
  runs created before this control existed (no `paths.root` field) keep resolving to the
  current working directory, and Phase B's resumability scan and the slug-dedup scan both
  check the legacy location too when a custom root is in effect.
- `state.json` now always includes a top-level `references: []` field at initialization
  (it was previously written only once Step 2 populated it, leaving it briefly absent
  from the documented schema — `contracts.md` §4 always specified it).

### Fixed
- **Every `scripts/*.sh` and `tests/*.sh` file had CRLF line endings in the working
  tree**, which made every one of them fail to parse under bash (`syntax error near
  unexpected token $'{\r''`) — i.e. the plugin could not actually run on a Windows
  checkout. The git-tracked blobs are LF; the CRLF was introduced by a Windows checkout's
  default line-ending conversion, undetected because there was no `.gitattributes`
  pinning the ending. Normalized all scripts back to LF and added `.gitattributes`
  (`*.sh`/`*.md`/`*.json`/`*.html` → `eol=lf`) so this cannot silently regress.
- **Removed a broken, hardcoded `output_root` hack.** `init-run.sh` briefly contained a
  hardcoded `BASE_DIR="C:/Users/.../ArticleWriterRuns"` that created folders there — but
  the two path variables it set were unconditionally overwritten a few lines later, so it
  had no effect beyond leaving behind stray empty folders. Replaced with the general,
  configurable `output_root` mechanism above.
- **`make-manifest.sh` — shell/python injection hardening.** The two `citation_style` /
  `output_format` lookups interpolated the state path directly into a `python3 -c` source
  string; a run path containing a quote could terminate the literal and inject code. Both
  now pass the path via `argv` in a single quoted-heredoc call, matching the pattern every
  other script here already used.

### Changed
- Docs reorganised: `documentation/` → `docs/`. The development plan and task tracker were
  project-management artifacts and have been removed; the spec (`requirements.md`),
  interface contracts (`contracts.md`), workflow diagram, and the gating architecture
  decision (formerly `phase2-decision.md`, now `architecture-decision.md`) are retained —
  the scripts and skills cite them as authoritative.
- Added `LICENSE` (MIT, previously declared in the manifest but not shipped) and a
  `.gitignore` covering the `input/`/`interim/`/`output/` run folders the plugin creates in
  the working directory.
- README: documented the `PreToolUse` hook the plugin registers, installation, and license.

## [0.3.0] — 2026-07-23

### Added
- **Plagiarism detection + ethical removal/attribution (Step 5, Pass 2).** Revision now
  runs an **originality & attribution** pass right after verification and before the
  structural pass. The model detects passages that copy or lean too closely on a source,
  or borrow an idea without credit, and applies an ethical remedy per passage:
  `quote-and-attribute` (wrap + cite a notable quote), `rewrite` (genuinely re-express
  borrowed phrasing), `attribute` (cite the source of a reworded idea), or `remove` (cut,
  or re-source — never attribute to a blacklisted source).
- **`scripts/originality-check.sh`** — the deterministic half of the pass. `scan` reports
  n-gram overlap between the draft and captured source excerpts
  (`state.originality.corpus[]`), honestly reporting an empty corpus rather than a false
  "clean". `verify` confirms each blocking `state.originality.flags[]` entry's remedy
  actually landed in the current draft (copied text gone / passage now quoted / idea backed
  by a real `references[]` entry) — a hard sub-gate of the Step 5 QA gate that the model
  cannot pass by mere assertion. Self-contained (python3, no jq, no network).
- **State + manifest.** `init-run.sh` seeds a `state.originality` block and a
  `plagiarism_ngram` control (overlap sensitivity, default 8, exposed in `userConfig`).
  `make-manifest.sh` surfaces an originality summary (detection basis, corpus size, flags,
  remedies applied) in `manifest.json`/`manifest.md`, with a reminder that Steps 6–7 edit
  prose after this pass. New test harness `tests/phase-originality.sh` (17 checks).

### Fixed
- **`originality-check.sh verify` hardening — two fail-open gaps closed.**
  (a) A blocking `remove`/`rewrite` flag with an **empty/missing `passage`** is now
  UNRESOLVED (previously reported "resolved" with nothing to verify — a blocking flag could
  pass by omission, defeating the "cannot pass by assertion" guarantee).
  (b) `quote-and-attribute` now requires the passage to be **both** inside a quotation span
  **and** carry a `ref_id` that exists in `references[]` — a quote is not "attributed" until
  it is cited; previously only the quoting half was verified, so a quoted-but-uncited passage
  passed. `tests/phase-originality.sh` extended (15 → 17 checks) to lock in both.

## [0.2.0] — 2026-07-15

### Added
- **Word (.docx) output.** The published article is now emitted as `article.docx`
  (`scripts/to-docx.sh` — pandoc-preferred, python-docx fallback), with `article.md` kept
  as the source. `controls.output_format` (`docx` default | `md`) selects the format.
- **Referencing in the article.** The article now carries in-text citations and a
  bibliography. `scripts/format-references.sh` deterministically renders the run's
  structured `references[]` in the chosen style — both the in-text form and the
  bibliography (correct heading per style). A standalone `references.md` is also emitted.
  Step 2 now captures structured bibliographic fields (`references[]`, `claims[].ref_id`);
  Steps 4–5 insert in-text citations and the References section and reconcile them.
- **Citation style is an explicit Step-1 input.** `controls.citation_style` — one of
  `apa`, `mla`, `chicago-author-date`, `chicago-notes`, `harvard`, `ieee`, `vancouver`,
  `none`. Step 1 asks the human explicitly (via `AskUserQuestion`, listing the full menu)
  when it isn't already set; also exposed as a `userConfig` control. `output_format` added
  as a control too.

## [0.1.2] — 2026-07-15

### Added
- **Domain / URL hard-blocking in the source policy.** `config/source-policy.json` now has
  `blocked_domains` (host-suffix matched — e.g. `reddit.com` also blocks `old.reddit.com`),
  `blocked_url_patterns` (substring), and `preferred_domains` (guidance). Seeded blocks:
  Reddit, Quora, LinkedIn, Wikipedia, Medium, Substack, Fandom, WikiHow, and the major
  social platforms. `source-check.sh` treats a blocked-domain/URL hit as a HARD violation
  for **any** claim (load-bearing or not), distinct from the softer tier-keyword blacklist.
  The research skill and adversarial reviewer now reference these blocks.

### Fixed
- Removed platform names and over-broad tokens (`reddit`, `tweet`, `social`, `marketing`,
  `forum`) from the tier-keyword `blacklist.signals` — they caused substring false positives
  (`social` matched "social science journal"; `reddit` matched "notreddit.com"). Platform
  blocking now lives precisely in `blocked_domains`. Added a regression test.

## [0.1.1] — 2026-07-15

### Changed
- **Centralized the source policy.** The whitelist/blacklist/tiering rule now live in a
  single canonical file, `config/source-policy.json`, instead of being duplicated across
  the script and the prose. `scripts/source-check.sh` loads its signal lists from that
  file (no hardcoded arrays; resolves the path relative to the plugin root, with an
  `AW_SOURCE_POLICY_FILE` override); `skills/step-2-research` and `agents/adversarial-reviewer`
  now reference the file as authoritative rather than restating the lists. Edit the policy
  in one place and every consumer follows. All tests still pass.

## [0.1.0] — 2026-07-15

First complete build of the plugin, delivered phase-by-phase against the original
development plan. All deterministic behaviour is covered by runnable tests; every
requirements §10 acceptance criterion passes.

### Phase 1 — Deterministic core
- `plugin.json` manifest with all §2.4 controls exposed as `userConfig`.
- `state.json` schema defined as the integration contract (`docs/contracts.md`).
- `init-run.sh` — run-id allocation (`YYYYMMDD-NNNNN-<slug>`, per-day reset, leading zeros),
  slug derivation, cross-date slug dedup (warn-and-ask contract), trigger log + state init.
- `gate-counter.sh` — sole mutator of per-gate counters; cap=3 with escalation per the §5.1
  routing table; atomic writes; cumulative `attempts` tracking for the manifest.
- `tests/phase1-core.sh` — 26 checks (incl. the init→gate integration point).

### Phase 2 — Command + gate spike (architecture de-risk)
- `commands/write-article.md` — two-phase entry (setup / `continue` resume).
- `templates/scope-template.md` — human scope form (mandatory: audience, purpose).
- `skills/step-1-scope` — scope handshake with mandatory-field hard-stop + provisional
  hypothesis (anti-bias).
- `gate-guard.sh` + `hooks/hooks.json` — `PreToolUse` backstop that blocks premature
  deliverable writes to `output/` and enforces the adversarial ceiling.
- `docs/architecture-decision.md` — **GO** decision, with the honest refinement that
  determinism = scripts own the numbers + a blocking guard owns deliverable emission;
  resolved the `commands/` vs `skills/` directory question. `tests/phase2-guard.sh` — 9 checks.

### Phase 3 — Step skills
- `skills/step-2-research … step-7-second-eyes` — each carrying its §4 subprocess, exit gate
  (recorded via `gate-counter.sh`), and state read/write.
- `skills/orchestrator` — sequences Steps 1–8, treats `ESCALATE` as mandatory routing.
- Unified the `status: step-N` = "step N complete" convention across all skills (fixed an
  off-by-one in the step-6/step-7 status advancement).

### Phase 4 — Adversarial agent + loop
- `agents/adversarial-reviewer.md` — isolated reviewer that re-sources claims independently
  (no `Edit` tool; forbidden from reading the author's citations) and classifies each claim.
- `review-loop.sh` — deterministic Step 8 control: round counting, min/max bound, early-stop,
  severity routing (Unsupported→2, peripheral-wrong→5, load-bearing-wrong→3/1).
- `make-manifest.sh` — emits article + sources (with tiers) + run manifest, stating rounds,
  escalations, per-gate iteration counts, verdict, and the honest verification guarantee.
- `tests/phase4-review.sh` — 20 checks.

### Phase 5 — Polish & acceptance
- `source-check.sh` — validates load-bearing claims rest on a whitelisted, sufficiently-high
  tier (§6); flags violations as unsupported.
- Honest-degradation invariant wired through orchestrator → reviewer → `review-loop.sh` →
  manifest (external truth vs. internal consistency only).
- `tests/acceptance.sh` — walks every requirements §10 criterion (22 checks).
- Trust review: no network calls, no `eval`/`system`, no `jq` dependency in any script.

[0.1.0]: #010--2026-07-15
