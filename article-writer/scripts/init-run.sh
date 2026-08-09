#!/usr/bin/env bash
#
# init-run.sh — deterministic run initialization for the `article-writer` plugin.
#
# Contract: docs/contracts.md §1 (run identity & folders), §2 (this
# interface), §4 (state.json schema), §5 (trigger.json schema).
# Requirements: docs/requirements.md §3, §2.1, §2.4.
#
# Usage:
#   init-run.sh <subject...>            # normal: slug dedup-check, then allocate + create
#   init-run.sh --force-new <subject...># skip dedup scan, allocate a fresh run
#   init-run.sh --reuse <run_id>        # resolve an existing run, no scan, no allocation
#
# Output (stdout, exactly one line on success):
#   RUN <run_id>                        # exit 0
#   DUPLICATE_MATCH <matched_run_id>    # exit 2 (nothing created)
# All diagnostics go to stderr. Exit codes: 0 success · 2 duplicate slug · 1 usage/other.
#
# Environment: bash 3.2 (macOS) — no associative arrays, no ${var,,}. No jq (uses
# python3). No network calls (hard security requirement, requirements §11).

set -euo pipefail

err() { printf '%s\n' "$*" >&2; }
die() { err "$@"; exit 1; }

usage() {
  err "usage: init-run.sh <subject...>"
  err "       init-run.sh --force-new <subject...>"
  err "       init-run.sh --reuse <run_id>"
}

# ---------------------------------------------------------------------------
# Slug derivation (contracts.md §1): lowercase -> spaces to '-' -> strip
# punctuation -> collapse repeated '-' -> trim leading/trailing '-' ->
# truncate to 40 chars -> re-trim any trailing '-'.
# ---------------------------------------------------------------------------
derive_slug() {
  local raw="$1" s
  s=$(printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | tr '[:space:]' '-' \
    | sed -e 's/[^a-z0-9-]//g' \
    | sed -e 's/--*/-/g' \
    | sed -e 's/^-*//' -e 's/-*$//')
  s=$(printf '%s' "$s" | cut -c1-40)
  s=$(printf '%s' "$s" | sed -e 's/-*$//')
  printf '%s' "$s"
}

# Extract the slug portion (everything after YYYYMMDD-NNNNN-) from a folder name.
name_slug() {
  printf '%s' "$1" | sed -n 's/^[0-9]\{8\}-[0-9]\{5\}-\(.*\)$/\1/p'
}

# Extract the 5-digit sequence from a folder name.
name_seq() {
  printf '%s' "$1" | sed -n 's/^[0-9]\{8\}-\([0-9]\{5\}\).*$/\1/p'
}

# ---------------------------------------------------------------------------
# Root directory resolution (contracts.md §1a; requirements §2.4 output_root).
#
# All three top-level folders (input/, interim/, output/) live under a "run
# root". By default that root is the current working directory (original
# behavior). If AW_OUTPUT_ROOT is set (from the output_root plugin control),
# it overrides the root — this lets runs persist in a durable location (e.g.
# a OneDrive-synced folder) instead of wherever Claude happened to be
# launched from, which may be an ephemeral session sandbox.
#
# The resolved root is ALWAYS an absolute path (so it stays valid even if a
# later session resumes this run from a different cwd), created if missing,
# and recorded in trigger.json / state.json ("paths.root") so every other
# script/skill can find the run without re-deriving AW_OUTPUT_ROOT itself.
# ---------------------------------------------------------------------------
resolve_root() {
  requested="${AW_OUTPUT_ROOT:-}"
  if [ -z "$requested" ]; then
    pwd
    return 0
  fi
  mkdir -p "$requested" 2>/dev/null || die "AW_OUTPUT_ROOT is not creatable as a directory: $requested"
  [ -d "$requested" ] || die "AW_OUTPUT_ROOT exists but is not a directory: $requested"
  (cd "$requested" && pwd)
}

ROOT_DIR="$(resolve_root)"
[ -n "$ROOT_DIR" ] || die "could not resolve a run root directory"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
MODE="normal"
if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

case "$1" in
  --force-new)
    MODE="force-new"
    shift
    [ "$#" -ge 1 ] || { err "--force-new requires a subject"; usage; exit 1; }
    ;;
  --reuse)
    MODE="reuse"
    shift
    [ "$#" -eq 1 ] || { err "--reuse requires exactly one <run_id>"; usage; exit 1; }
    ;;
  --*)
    err "unknown option: $1"
    usage
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# --reuse: resolve an existing run, no scan, no allocation, no creation.
# ---------------------------------------------------------------------------
if [ "$MODE" = "reuse" ]; then
  RUN_ID="$1"
  if [ -d "$ROOT_DIR/input/$RUN_ID" ] || [ -d "$ROOT_DIR/interim/$RUN_ID" ] || [ -d "$ROOT_DIR/output/$RUN_ID" ]; then
    printf 'RUN %s\n' "$RUN_ID"
    exit 0
  fi
  # Backward-compat: a run created before AW_OUTPUT_ROOT existed (or with it
  # unset this time) may live directly under the plain current working
  # directory instead of $ROOT_DIR. Only relevant when the two differ.
  if [ "$ROOT_DIR" != "$(pwd)" ]; then
    if [ -d "input/$RUN_ID" ] || [ -d "interim/$RUN_ID" ] || [ -d "output/$RUN_ID" ]; then
      printf 'RUN %s\n' "$RUN_ID"
      exit 0
    fi
  fi
  die "no existing run found for run_id: $RUN_ID (looked under $ROOT_DIR)"
fi

# ---------------------------------------------------------------------------
# Normal / force-new: derive slug from the subject (all remaining args).
# The raw subject is preserved verbatim; only the label is slugified.
# ---------------------------------------------------------------------------
RAW_SUBJECT="$*"
SLUG=$(derive_slug "$RAW_SUBJECT")
[ -n "$SLUG" ] || die "subject produced an empty slug; provide a subject with alphanumeric content"

# ---------------------------------------------------------------------------
# Slug dedup scan (contracts.md §2.1): scan ALL runs across ALL dates in all
# three top-level folders for a slug match. On match, create nothing and exit 2.
# --force-new skips this scan.
# ---------------------------------------------------------------------------
if [ "$MODE" != "force-new" ]; then
  # Scan $ROOT_DIR, and — if it differs from the plain cwd (custom
  # AW_OUTPUT_ROOT in effect) — also scan the cwd, so a run created before
  # output_root was set (or in a session without it) still counts as a match.
  for scan_base in "$ROOT_DIR" "$(pwd)"; do
    for base in input interim output; do
      [ -d "$scan_base/$base" ] || continue
      for d in "$scan_base/$base"/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        existing=$(name_slug "$name")
        if [ -n "$existing" ] && [ "$existing" = "$SLUG" ]; then
          printf 'DUPLICATE_MATCH %s\n' "$name"
          exit 2
        fi
      done
    done
    [ "$ROOT_DIR" != "$(pwd)" ] || break
  done
fi

# ---------------------------------------------------------------------------
# Sequence allocation (contracts.md §1): scan folders sharing today's YYYYMMDD
# prefix across all three top-level folders, take max NNNNN, increment.
# Scoped per day, resets to 00001 each new date.
# ---------------------------------------------------------------------------
# Sequence is scoped to where the run will actually be created ($ROOT_DIR) —
# a custom output_root starts its own 00001 sequence, independent of any
# legacy runs left behind under a plain cwd.
DATE=$(date +%Y%m%d)
max=0
for base in input interim output; do
  [ -d "$ROOT_DIR/$base" ] || continue
  for d in "$ROOT_DIR/$base"/${DATE}-*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    seq_part=$(name_seq "$name")
    [ -n "$seq_part" ] || continue
    # 10# forces base-10 so leading zeros are not read as octal.
    n=$((10#$seq_part))
    if [ "$n" -gt "$max" ]; then max="$n"; fi
  done
done
next=$((max + 1))
SEQ=$(printf '%05d' "$next")

RUN_ID="${DATE}-${SEQ}-${SLUG}"

# ---------------------------------------------------------------------------
# Create the folder triplet under the resolved root (requirements §2.4
# output_root; defaults to the current working directory, unchanged from
# original behavior).
# ---------------------------------------------------------------------------
mkdir -p "$ROOT_DIR/input/$RUN_ID" \
         "$ROOT_DIR/interim/$RUN_ID" \
         "$ROOT_DIR/output/$RUN_ID"

TRIGGER_PATH="$ROOT_DIR/input/$RUN_ID/trigger.json"
STATE_PATH="$ROOT_DIR/interim/$RUN_ID/state.json"

# ---------------------------------------------------------------------------
# Resolve controls from AW_* env vars, falling back to the §4 defaults.
# ---------------------------------------------------------------------------
AUDIENCE="${AW_AUDIENCE:-general informed reader}"
ANGLE="${AW_ANGLE:-auto}"
LENGTH="${AW_LENGTH:-medium}"
TONE="${AW_TONE:-neutral, plain}"
SOURCE_POLICY="${AW_SOURCE_POLICY:-default}"
SOURCE_QUALITY_THRESHOLD="${AW_SOURCE_QUALITY_THRESHOLD:-peer-reviewed / reputable only}"
PER_GATE_CAP="${AW_PER_GATE_CAP:-3}"
ADVERSARIAL_CAP="${AW_ADVERSARIAL_CAP:-5}"
ADVERSARIAL_MIN="${AW_ADVERSARIAL_MIN:-1}"
ESCALATION_ROUTING="${AW_ESCALATION_ROUTING:-default}"
PLAGIARISM_NGRAM="${AW_PLAGIARISM_NGRAM:-8}"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---------------------------------------------------------------------------
# Write trigger.json (§5) and state.json (§4) via python3. Values are passed
# through the environment (no shell interpolation into the JSON), and each file
# is written atomically (temp file + os.replace).
# ---------------------------------------------------------------------------
export AW_RUN_ID="$RUN_ID" AW_DATE="$DATE" AW_SEQ="$SEQ" AW_SLUG="$SLUG" \
  AW_RAW_SUBJECT="$RAW_SUBJECT" AW_TIMESTAMP="$TIMESTAMP" \
  AW_TRIGGER_PATH="$TRIGGER_PATH" AW_STATE_PATH="$STATE_PATH" AW_ROOT_DIR="$ROOT_DIR" \
  AW_C_AUDIENCE="$AUDIENCE" AW_C_ANGLE="$ANGLE" AW_C_LENGTH="$LENGTH" \
  AW_C_TONE="$TONE" AW_C_SOURCE_POLICY="$SOURCE_POLICY" \
  AW_C_SOURCE_QUALITY_THRESHOLD="$SOURCE_QUALITY_THRESHOLD" \
  AW_C_PER_GATE_CAP="$PER_GATE_CAP" AW_C_ADVERSARIAL_CAP="$ADVERSARIAL_CAP" \
  AW_C_ADVERSARIAL_MIN="$ADVERSARIAL_MIN" AW_C_ESCALATION_ROUTING="$ESCALATION_ROUTING" \
  AW_C_PLAGIARISM_NGRAM="$PLAGIARISM_NGRAM"

python3 - <<'PY'
import json, os, sys, tempfile

def as_int(name):
    v = os.environ[name]
    try:
        return int(str(v).strip())
    except (ValueError, TypeError):
        sys.stderr.write("control %s must be an integer, got: %r\n" % (name, v))
        sys.exit(1)

root_dir = os.environ["AW_ROOT_DIR"]

controls = {
    "output_root": root_dir,
    "audience": os.environ["AW_C_AUDIENCE"],
    "angle": os.environ["AW_C_ANGLE"],
    "length": os.environ["AW_C_LENGTH"],
    "tone": os.environ["AW_C_TONE"],
    "source_policy": os.environ["AW_C_SOURCE_POLICY"],
    "source_quality_threshold": os.environ["AW_C_SOURCE_QUALITY_THRESHOLD"],
    "per_gate_cap": as_int("AW_C_PER_GATE_CAP"),
    "adversarial_cap": as_int("AW_C_ADVERSARIAL_CAP"),
    "adversarial_min": as_int("AW_C_ADVERSARIAL_MIN"),
    "escalation_routing": os.environ["AW_C_ESCALATION_ROUTING"],
    "plagiarism_ngram": as_int("AW_C_PLAGIARISM_NGRAM"),
}

run_id = os.environ["AW_RUN_ID"]
ts = os.environ["AW_TIMESTAMP"]
raw_subject = os.environ["AW_RAW_SUBJECT"]
slug = os.environ["AW_SLUG"]

# paths.root is the canonical, absolute base for this run's input/interim/
# output folders (requirements §2.4 output_root; contracts.md §1a). Every
# script/skill downstream should resolve run paths as f"{paths.root}/input/
# {run_id}/..." etc. instead of assuming the current working directory —
# this is what makes a run resumable in a later session even if that
# session's cwd differs from the one that created the run.
trigger = {
    "run_id": run_id,
    "raw_subject": raw_subject,
    "slug": slug,
    "timestamp": ts,
    "controls": controls,
    "paths": {"root": root_dir},
}

state = {
    "schema_version": 1,
    "run_id": run_id,
    "date": os.environ["AW_DATE"],
    "sequence": os.environ["AW_SEQ"],
    "slug": slug,
    "raw_subject": raw_subject,
    "created_at": ts,
    "updated_at": ts,
    "status": "awaiting-scope",
    "scope": {
        "template_completed": False,
        "missing_mandatory": ["audience", "purpose"],
        "reconciled": None,
    },
    "controls": controls,
    "paths": {"root": root_dir},
    "current_step": 0,
    "hypothesis": {"text": None, "hardened_to_thesis": False},
    "research": {"claims": [], "open_questions": []},
    "references": [],
    "placeholders": [],
    "gates": {
        "step-1": {"fails": 0},
        "step-2": {"fails": 0},
        "step-3": {"fails": 0},
        "step-4": {"fails": 0},
        "step-5": {"fails": 0},
        "step-6": {"fails": 0},
        "step-7": {"fails": 0},
    },
    "escalation_history": [],
    "originality": {
        "checked": False,
        "detection_guarantee": None,
        "corpus": [],
        "flags": [],
    },
    "adversarial": {"rounds": 0, "ledger": []},
}

def write_atomic(path, obj):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

write_atomic(os.environ["AW_TRIGGER_PATH"], trigger)
write_atomic(os.environ["AW_STATE_PATH"], state)
PY

# ---------------------------------------------------------------------------
# Success.
# ---------------------------------------------------------------------------
printf 'RUN %s\n' "$RUN_ID"
exit 0
