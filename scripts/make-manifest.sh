#!/usr/bin/env bash
#
# make-manifest.sh — deterministic deliverable emitter + run manifest (task P4-T3).
#
# Emits the three OUTPUT deliverables (requirements §2.2) into output/<run_id>/:
#   - article.docx : the final article (default; converted from the draft via to-docx.sh).
#                    article.md is also kept as the Markdown source. Set controls.output_format
#                    to "md" to emit Markdown only.
#   - references.md: the formatted bibliography in controls.citation_style (format-references.sh)
#   - sources.md   : the citation list — each source + quality tier (from research.claims)
#   - manifest.json + manifest.md : what happened — adversarial rounds, which escalations
#     fired, per-gate iteration counts, final verdict, and WHICH guarantee was obtained
#     (external truth vs internal consistency only) (§2.2, §10, §11).
#
# SELF-GUARDING: refuses to run unless state.status is a publish stage (step-8 | published).
# This is defence-in-depth alongside the PreToolUse guard — deterministic emission cannot
# be talked around by invoking this script early (requirements §11).
#
# Usage:  make-manifest.sh <run_id> [root_dir]
#   <root_dir> is the run's root (requirements §2.4 output_root; contracts.md §1a) — the
#   base under which input/, interim/, output/ live. Defaults to "." (current working
#   directory, original behavior) so existing callers/tests are unaffected. When a run was
#   created with a custom output_root, the caller MUST pass that run's state.json
#   "paths.root" here — orchestrator already read that file to reach this point, so it
#   already has the value.
# No jq, no network, bash 3.2 (macOS).

set -euo pipefail

die() { echo "make-manifest.sh: $1" >&2; exit "${2:-1}"; }
[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || die "usage: make-manifest.sh <run_id> [root_dir]" 1
RUN="$1"
ROOT_DIR="${2:-.}"
STATE="$ROOT_DIR/interim/$RUN/state.json"
DRAFT="$ROOT_DIR/interim/$RUN/draft.md"
OUTDIR="$ROOT_DIR/output/$RUN"
[ -f "$STATE" ] || die "state file not found: $STATE" 1
[ -d "$OUTDIR" ] || die "output dir not found: $OUTDIR" 1

python3 - "$STATE" "$DRAFT" "$OUTDIR" "$RUN" <<'PY'
import json, os, sys, shutil
from datetime import datetime, timezone

state_path, draft_path, outdir, run = sys.argv[1:5]
state = json.load(open(state_path))

status = state.get("status", "")
if status not in ("step-8", "published"):
    sys.stderr.write("make-manifest.sh: refusing to emit deliverables — run '%s' is at "
                     "status '%s', not a publish stage (step-8|published).\n" % (run, status))
    sys.exit(2)

# --- article.md (copy the near-final draft) ---
if os.path.isfile(draft_path):
    shutil.copyfile(draft_path, os.path.join(outdir, "article.md"))

# --- sources.md (citation list with quality tiers, from the author's research) ---
claims = (state.get("research", {}) or {}).get("claims", []) or []
seen, src_lines = set(), []
for c in claims:
    if not isinstance(c, dict): continue
    s = c.get("source"); t = c.get("tier", "unrated"); ind = c.get("independent")
    if not s or s in seen: continue
    seen.add(s)
    mark = "independent" if ind else "single-origin"
    src_lines.append("- **%s** — tier: %s (%s)" % (s, t, mark))
with open(os.path.join(outdir, "sources.md"), "w") as f:
    f.write("# Sources — %s\n\n" % run)
    f.write("\n".join(src_lines) if src_lines else "_No sources recorded._")
    f.write("\n")

# --- verdict + guarantee from the adversarial record ---
adv = state.get("adversarial", {}) or {}
rounds = adv.get("rounds", 0)
ledger = adv.get("ledger", []) or []
guarantee = adv.get("verification_guarantee", "internal-consistency-only")
n_unresolved = sum(1 for i in ledger if isinstance(i, dict)
                   and i.get("verdict") in ("wrong", "misrepresented", "unsupported"))
verdict = "clean-review" if n_unresolved == 0 else "published-with-unresolved"

# --- per-gate iteration counts (cumulative attempts) + escalations ---
gates = state.get("gates", {}) or {}
gate_counts = {g: (v or {}).get("attempts", 0) for g, v in gates.items()}
escalations = state.get("escalation_history", []) or []

# --- originality / plagiarism summary (Step 5, Pass 2) ---
orig = state.get("originality", {}) or {}
orig_flags = orig.get("flags", []) or []
orig_blocking = [f for f in orig_flags if isinstance(f, dict) and f.get("severity", "blocking") == "blocking"]
def _remedy_counts(flags):
    out = {}
    for f in flags:
        if isinstance(f, dict):
            out[f.get("remedy") or "unspecified"] = out.get(f.get("remedy") or "unspecified", 0) + 1
    return out
originality = {
    "checked": bool(orig.get("checked")),
    "detection_guarantee": orig.get("detection_guarantee"),
    "corpus_excerpts": len(orig.get("corpus", []) or []),
    "flags_total": len(orig_flags),
    "flags_blocking": len(orig_blocking),
    "remedies": _remedy_counts(orig_flags),
}

controls = state.get("controls", {}) or {}
post_category = controls.get("post_category") or None
rigor_tier = controls.get("rigor_tier") or None
research_mode = controls.get("research_mode", "deep")
manifest = {
    "run_id": run,
    "raw_subject": state.get("raw_subject"),
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": status,
    "final_verdict": verdict,
    "post_category": post_category,
    "rigor_tier": rigor_tier,
    "research_mode": research_mode,
    "adversarial_rounds": rounds,
    "unresolved_claims": n_unresolved,
    "verification_guarantee": guarantee,
    "originality": originality,
    "escalations_fired": escalations,
    "per_gate_iteration_counts": gate_counts,
    "citation_style": controls.get("citation_style", "apa"),
    "output_format": controls.get("output_format", "docx"),
    "reference_count": len(state.get("references", []) or []),
    "controls": controls,
}
with open(os.path.join(outdir, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2); f.write("\n")

# --- human-readable manifest.md ---
guar_txt = ("Independent re-sourcing was available — **external truth** was checked."
            if guarantee == "external-truth" else
            "Independent source access was NOT available — only **internal consistency** "
            "was checked. This run does NOT constitute external fact verification.")
tier_txt = (
    "**%s** (post_category: %s, research_mode: %s) — " % (rigor_tier, post_category, research_mode) +
    ("no external research or fact-checking was attempted for this run; it was skipped "
     "BY DESIGN because this is a personal/reflective post, not because source access "
     "was unavailable." if research_mode == "none" else
     "only the handful of hard, named facts in the piece were spot-checked; this run did "
     "not attempt full territory-mapping, counter-evidence hunting, or source "
     "triangulation." if research_mode == "spot-check" else
     "the full research + independent fact-check pipeline ran for this run.")
) if rigor_tier else "_Not recorded on this run (pre-existing before post_category was added)._"

lines = [
    "# Run manifest — %s" % run, "",
    "**Subject:** %s  " % state.get("raw_subject"),
    "**Generated:** %s  " % manifest["generated_at"],
    "**Final verdict:** %s  " % verdict,
    "**Adversarial rounds:** %d  " % rounds,
    "**Unresolved claims at close:** %d  " % n_unresolved, "",
    "## Post category & rigor tier", tier_txt, "",
    "## Verification guarantee", guar_txt, "",
]

# --- originality / plagiarism section ---
if originality["checked"]:
    og = originality["detection_guarantee"]
    og_txt = ("compared against captured source text / independent search (**source-comparison**)"
              if og == "source-comparison" else
              "**internal-only** — no independent source text was available to compare against, "
              "so copying from external sources could NOT be detected this run")
    lines += [
        "## Originality & attribution (Step 5, Pass 2)",
        "Detection basis: %s.  " % og_txt,
        "Corpus excerpts compared: %d  " % originality["corpus_excerpts"],
        "Passages flagged: %d (blocking: %d)  " % (originality["flags_total"], originality["flags_blocking"]),
    ]
    if originality["remedies"]:
        lines.append("Ethical remedies applied: " +
                     ", ".join("%s×%d" % (k, v) for k, v in sorted(originality["remedies"].items())) + "  ")
    lines += ["", "> Note: Steps 6–7 may edit prose after this pass; give the open/close a final read.", ""]
else:
    lines += ["## Originality & attribution (Step 5, Pass 2)",
              "_No originality record on this run._", ""]

lines += ["## Escalations fired"]
if escalations:
    for e in escalations:
        lines.append("- gate `%s` → `%s` at %s" % (e.get("gate"), e.get("target"), e.get("at")))
else:
    lines.append("_None._")
lines += ["", "## Per-gate iteration counts (cumulative attempts)"]
for g in sorted(gate_counts):
    lines.append("- `%s`: %s" % (g, gate_counts[g]))
if verdict != "clean-review":
    lines += ["", "> ⚠️ The 5-review cap was reached with %d unresolved claim(s). "
              "Published with disclosure per requirements §10; these claims were NOT "
              "cleanly verified." % n_unresolved]
with open(os.path.join(outdir, "manifest.md"), "w") as f:
    f.write("\n".join(lines) + "\n")

sys.stdout.write("MANIFEST %s verdict=%s rounds=%d guarantee=%s unresolved=%d\n"
                 % (run, verdict, rounds, guarantee, n_unresolved))
PY

# --- deliverable rendering (bash layer; sibling scripts, no python subprocess) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Read both controls in one pass, one value per line. The state path is passed via argv
# and never interpolated into the python source — a path containing a quote must not be
# able to inject code (this matches the argv pattern every other script here uses).
CONTROLS="$(python3 - "$STATE" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])).get("controls") or {}
print(c.get("citation_style") or "apa")
print(c.get("output_format") or "docx")
PY
)"
STYLE="${CONTROLS%%$'\n'*}"
FORMAT="${CONTROLS#*$'\n'}"

# Standalone formatted bibliography (references.md), in the chosen style (skip if 'none').
if [ "$STYLE" != "none" ]; then
  "$SCRIPT_DIR/format-references.sh" "$STATE" bibliography > "$OUTDIR/references.md" 2>/dev/null || true
fi

# Convert the article to .docx (default). The article.md already carries in-text citations
# and its References section (added by the drafting/revision steps).
if [ "$FORMAT" = "docx" ] && [ -f "$OUTDIR/article.md" ]; then
  if "$SCRIPT_DIR/to-docx.sh" "$OUTDIR/article.md" "$OUTDIR/article.docx" >/dev/null 2>&1; then
    echo "  emitted: article.docx (+ article.md source)"
  else
    echo "  WARNING: no docx engine (pandoc/python-docx) available — kept article.md only" >&2
  fi
fi
