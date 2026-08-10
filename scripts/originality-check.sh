#!/usr/bin/env bash
#
# originality-check.sh — deterministic plagiarism / attribution verifier (Step 5, Pass 2).
#
# The model (step-5-revise, Pass 2) does the PROBABILISTIC work: it detects passages that
# copy or lean too closely on a source, or borrow an idea without credit, and picks an
# ETHICAL remedy per passage (quote-and-attribute | rewrite | attribute | remove). This
# script does the DETERMINISTIC work: it (a) offers a keyword-free n-gram overlap SCAN of
# the draft against captured source excerpts as a detection aid, and (b) VERIFIES that each
# flagged blocking passage's chosen remedy actually landed in the current draft text — the
# model cannot pass the gate by merely asserting "resolved" (requirements §4 Step 2
# plagiarism-defense, §5.3; contracts.md §3/§4). Loop control stays with the Step 5 gate
# (gate-counter.sh step-5); this script only reports resolved vs unresolved.
#
# Usage:
#   originality-check.sh <state_path> <draft_path> verify   # (default) check remedies landed
#   originality-check.sh <state_path> <draft_path> scan     # n-gram overlap detection aid
#
# verify semantics (per state.originality.flags[] entry with severity == "blocking"):
#   remedy remove | rewrite            -> the verbatim passage must NO LONGER appear in the
#                                         draft (normalized). Still present -> UNRESOLVED. An
#                                         empty/missing passage -> UNRESOLVED (nothing to
#                                         verify; a blocking flag may not pass by omission).
#   remedy quote-and-attribute         -> the passage must appear INSIDE a quotation span in
#                                         the draft (so it reads as a quote, not the author's
#                                         own prose) AND carry a ref_id that exists in
#                                         state.references[] — a quote is not "attributed"
#                                         until it is cited. Unquoted OR uncited -> UNRESOLVED.
#   remedy attribute (reworded idea)   -> ref_id must be non-null AND exist in
#                                         state.references[] (Step 5 Pass 1 separately
#                                         guarantees that reference is actually cited in the
#                                         body — no uncited references). Missing -> UNRESOLVED.
#   Advisory flags are reported but never fail the check.
#
#   exit 0 — every blocking flag's remedy is verified in the draft (gate may pass)
#   exit 3 — one or more blocking flags are UNRESOLVED (Step 5 gate must fail and loop)
#   exit 1 — usage / unreadable state / unreadable draft
#
# scan semantics: report draft spans that share a run of >= N consecutive normalized words
# with any excerpt in state.originality.corpus[] (each {source, text}). N comes from
# AW_PLAGIARISM_NGRAM env, else controls.plagiarism_ngram, else 8. An EMPTY corpus is
# reported honestly (no source text to compare against) — never a false "clean". scan is a
# detection aid for the model; it does not set an exit code failure (always exit 0).
#
# Self-contained: python3 for all logic, no jq, NO network (requirements §11), bash 3.2.

set -euo pipefail
die() { echo "originality-check.sh: $1" >&2; exit "${2:-1}"; }

# Resolve a python3 interpreter (Windows may only expose python.exe/py.exe, not a
# python3 alias) and force UTF-8 I/O so non-ASCII characters in state.json/the draft
# survive read round-trips instead of being mangled by the system locale codepage.
if command -v python3 >/dev/null 2>&1; then PY3=python3
elif command -v python >/dev/null 2>&1; then PY3=python
elif command -v py >/dev/null 2>&1; then PY3="py -3"
else die "no python3 interpreter found on PATH (tried python3, python, py -3)" 1
fi
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

[ "$#" -ge 2 ] || die "usage: originality-check.sh <state_path> <draft_path> [verify|scan]" 1
STATE_PATH="$1"
DRAFT_PATH="$2"
ACTION="${3:-verify}"
case "$ACTION" in verify|scan) ;; *) die "unknown action '$ACTION' (expected verify|scan)" 1 ;; esac
[ -f "$STATE_PATH" ] || die "state file not found: $STATE_PATH" 1
[ -f "$DRAFT_PATH" ] || die "draft file not found: $DRAFT_PATH" 1

NGRAM_ENV="${AW_PLAGIARISM_NGRAM:-}"

$PY3 - "$STATE_PATH" "$DRAFT_PATH" "$ACTION" "$NGRAM_ENV" <<'PY'
import json, re, sys

state_path, draft_path, action, ngram_env = sys.argv[1:5]

def die(msg):
    sys.stderr.write("originality-check.sh: %s\n" % msg); sys.exit(1)

try:
    state = json.load(open(state_path))
except (ValueError, OSError) as e:
    die("invalid or unreadable state JSON: %s" % e)
try:
    draft = open(draft_path, encoding="utf-8").read()
except OSError as e:
    die("unreadable draft: %s" % e)
if not isinstance(state, dict):
    die("state root is not an object")

orig = state.get("originality")
if not isinstance(orig, dict):
    orig = {}

# --- normalization helpers -------------------------------------------------
# Lowercase, unify smart/straight quotes, collapse all whitespace to single spaces.
QUOTES = {"“": '"', "”": '"', "‘": "'", "’": "'", "«": '"', "»": '"'}
def unify_quotes(s):
    return "".join(QUOTES.get(ch, ch) for ch in s)

def norm(s):
    s = unify_quotes(s).lower()
    s = re.sub(r"\s+", " ", s)
    return s.strip()

WORD_RE = re.compile(r"[a-z0-9]+")
def words(s):
    return WORD_RE.findall(unify_quotes(s).lower())

# ==========================================================================
# SCAN — n-gram overlap detection aid
# ==========================================================================
if action == "scan":
    if ngram_env.strip() != "":
        try:
            N = int(ngram_env)
        except ValueError:
            die("AW_PLAGIARISM_NGRAM is not an integer: %r" % ngram_env)
    else:
        c = state.get("controls", {}) or {}
        try:
            N = int(c.get("plagiarism_ngram", 8))
        except (TypeError, ValueError):
            N = 8
    if N < 3:
        N = 3

    corpus = orig.get("corpus", []) or []
    corpus = [c for c in corpus if isinstance(c, dict) and c.get("text")]
    if not corpus:
        print(json.dumps({
            "detection_guarantee": "internal-only",
            "note": "state.originality.corpus is empty — no captured source text to compare "
                    "the draft against. This scan cannot detect copying; the model's own "
                    "source-comparison (Pass 2) is the only originality signal for this run.",
            "ngram": N,
            "overlaps": [],
        }, indent=2))
        sys.exit(0)

    # Build shingle -> source index from the corpus.
    shingles = {}
    for c in corpus:
        cw = words(c["text"])
        src = c.get("source") or "(unattributed excerpt)"
        for i in range(0, max(0, len(cw) - N + 1)):
            shingles[tuple(cw[i:i+N])] = src

    dw = words(draft)
    overlaps, i = [], 0
    while i <= len(dw) - N:
        key = tuple(dw[i:i+N])
        if key in shingles:
            src = shingles[key]
            j = i + N
            # extend the run word-by-word while it keeps matching the same source.
            while j < len(dw) and tuple(dw[j-N+1:j+1]) in shingles and shingles[tuple(dw[j-N+1:j+1])] == src:
                j += 1
            overlaps.append({"source": src, "word_len": j - i,
                             "overlap_text": " ".join(dw[i:j])})
            i = j
        else:
            i += 1

    print(json.dumps({
        "detection_guarantee": "source-comparison",
        "ngram": N,
        "overlaps": overlaps,
        "note": "%d span(s) of >= %d consecutive words in the draft match captured source "
                "text. Each is a candidate verbatim/near-verbatim copy for the model to "
                "quote-and-attribute or rewrite." % (len(overlaps), N),
    }, indent=2))
    sys.exit(0)

# ==========================================================================
# VERIFY — every blocking flag's remedy must be visible in the current draft
# ==========================================================================
draft_norm = norm(draft)

# Precompute normalized quoted spans in the draft ("..." only — an apostrophe is not a
# quote delimiter). Used to confirm a quote-and-attribute passage reads as a quotation.
quoted_spans = [norm(m) for m in re.findall(r'"([^"]{1,2000})"', unify_quotes(draft))]
def is_quoted(passage_norm):
    return any(passage_norm and passage_norm in span for span in quoted_spans)

ref_ids = set()
for r in (state.get("references", []) or []):
    if isinstance(r, dict) and r.get("id"):
        ref_ids.add(str(r["id"]))

flags = orig.get("flags", []) or []
if not isinstance(flags, list):
    die("state.originality.flags is not a list")

resolved, unresolved, advisories = [], [], []
for f in flags:
    if not isinstance(f, dict):
        continue
    sev = f.get("severity", "blocking")
    remedy = f.get("remedy")
    passage = f.get("passage", "") or ""
    pnorm = norm(passage)
    fid = f.get("id") or "(unlabelled)"

    ok, why = False, ""
    if remedy in ("remove", "rewrite"):
        if not pnorm:
            ok, why = False, ("no passage text recorded — cannot verify the copied text was "
                              "removed/rewritten (a blocking flag may not pass by omission)")
        else:
            present = pnorm in draft_norm
            ok = not present
            why = ("copied passage is gone from the draft" if ok
                   else "copied passage STILL appears verbatim in the draft")
    elif remedy in ("quote-and-attribute",):
        rid = f.get("ref_id")
        if not pnorm:
            ok, why = False, "no passage text recorded — cannot verify the quote landed"
        elif pnorm not in draft_norm:
            ok, why = False, "passage marked for quoting is not present in the draft"
        elif not is_quoted(pnorm):
            ok, why = False, "passage present but NOT enclosed in quotation marks"
        elif not (rid and str(rid) in ref_ids):
            ok, why = False, ("passage is quoted but NOT attributed — ref_id %r has no matching "
                              "entry in state.references[]" % rid)
        else:
            ok, why = True, ("passage now sits inside a quotation span and is attributed to "
                             "reference '%s'" % rid)
    elif remedy in ("attribute",):
        rid = f.get("ref_id")
        if rid and str(rid) in ref_ids:
            ok, why = True, ("idea attributed to reference '%s' (Pass 1 guarantees it is "
                             "cited in the body)" % rid)
        elif not rid:
            ok, why = False, "attribute remedy but no ref_id recorded"
        else:
            ok, why = False, "ref_id '%s' has no matching entry in state.references[]" % rid
    else:
        ok, why = False, "unknown or missing remedy: %r" % remedy

    rec = {"id": fid, "type": f.get("type"), "remedy": remedy,
           "source": f.get("matched_source"), "why": why}
    if sev != "blocking":
        advisories.append(rec)
    elif ok:
        resolved.append(rec)
    else:
        unresolved.append(rec)

print("originality-check: %d blocking flag(s) — %d resolved, %d UNRESOLVED; %d advisory."
      % (len(resolved) + len(unresolved), len(resolved), len(unresolved), len(advisories)))
for r in unresolved:
    print("  UNRESOLVED [%s] remedy=%s: %s [source=%r]"
          % (r["id"], r["remedy"], r["why"], r["source"]))
for r in resolved:
    print("  resolved   [%s] remedy=%s: %s" % (r["id"], r["remedy"], r["why"]))
for a in advisories:
    print("  advisory   [%s] remedy=%s: %s" % (a["id"], a["remedy"], a["why"]))

sys.exit(3 if unresolved else 0)
PY
