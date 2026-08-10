#!/usr/bin/env bash
#
# init-run.sh — allocate one flat run folder for article-writer.
#
# No gates, no caps, no controls machinery. One folder per run, directly under the
# resolved root: <root>/<run_id>/, plus a small internal <run_id>/.article-writer/
# subfolder for the brief + in-progress draft. Everything else (per-gate caps,
# adversarial review, citation styles, source-tiering) has been removed — see
# CHANGELOG.md. The run folder is what the human sees; .article-writer/ is bookkeeping.
#
# Usage:
#   init-run.sh <topic...>              # normal: dedup-check, then allocate + create
#   init-run.sh --force-new <topic...>  # skip dedup, allocate a fresh run
#   init-run.sh --reuse <run_id>        # resolve an existing run, no allocation
#
# Output (stdout, exactly one line on success):
#   RUN <run_id>                        # exit 0
#   DUPLICATE_MATCH <matched_run_id>    # exit 2 (nothing created)
# All diagnostics go to stderr. Exit codes: 0 success · 2 duplicate slug · 1 usage/other.
#
# Brief fields (audience/intention/angle/points/post_category) come from AW_* env vars,
# set by the caller (commands/write-article.md), and are written into
# <run_id>/.article-writer/brief.json alongside the raw topic. All are free text; none
# are enforced or validated beyond "recorded as given."
#
# Environment: bash 3.2+ (macOS/Windows git-bash). No jq (uses python3). No network.

set -euo pipefail

err() { printf '%s\n' "$*" >&2; }
die() { err "$@"; exit 1; }

# Resolve a python3 interpreter (some Windows installs only expose python.exe/py.exe on
# PATH, not a python3 alias) and force UTF-8 I/O so non-ASCII characters survive writes.
if command -v python3 >/dev/null 2>&1; then PY3=python3
elif command -v python >/dev/null 2>&1; then PY3=python
elif command -v py >/dev/null 2>&1; then PY3="py -3"
else die "no python3 interpreter found on PATH (tried python3, python, py -3)"
fi
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

usage() {
  err "usage: init-run.sh <topic...>"
  err "       init-run.sh --force-new <topic...>"
  err "       init-run.sh --reuse <run_id>"
}

# ---------------------------------------------------------------------------
# Slug derivation: lowercase -> spaces to '-' -> strip punctuation -> collapse
# repeated '-' -> trim leading/trailing '-' -> truncate to 40 chars -> re-trim.
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

name_slug() { printf '%s' "$1" | sed -n 's/^[0-9]\{8\}-[0-9]\{5\}-\(.*\)$/\1/p'; }
name_seq()  { printf '%s' "$1" | sed -n 's/^[0-9]\{8\}-\([0-9]\{5\}\).*$/\1/p'; }

# ---------------------------------------------------------------------------
# Root directory resolution (unchanged mechanism from earlier versions): AW_OUTPUT_ROOT
# overrides the current working directory. Always resolved to an absolute path.
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
    [ "$#" -ge 1 ] || { err "--force-new requires a topic"; usage; exit 1; }
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
  if [ -d "$ROOT_DIR/$RUN_ID" ]; then
    printf 'RUN %s\n' "$RUN_ID"
    exit 0
  fi
  die "no existing run found for run_id: $RUN_ID (looked under $ROOT_DIR)"
fi

# ---------------------------------------------------------------------------
# Normal / force-new: derive slug from the topic (all remaining args).
# ---------------------------------------------------------------------------
RAW_TOPIC="$*"
SLUG=$(derive_slug "$RAW_TOPIC")
[ -n "$SLUG" ] || die "topic produced an empty slug; provide a topic with alphanumeric content"

# ---------------------------------------------------------------------------
# Slug dedup scan: scan every run folder directly under root, across all dates, for
# a slug match. On match, create nothing and exit 2. --force-new skips this scan.
# ---------------------------------------------------------------------------
if [ "$MODE" != "force-new" ] && [ -d "$ROOT_DIR" ]; then
  for d in "$ROOT_DIR"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    existing=$(name_slug "$name")
    if [ -n "$existing" ] && [ "$existing" = "$SLUG" ]; then
      printf 'DUPLICATE_MATCH %s\n' "$name"
      exit 2
    fi
  done
fi

# ---------------------------------------------------------------------------
# Sequence allocation: scan run folders sharing today's YYYYMMDD prefix directly
# under root, take max NNNNN, increment. Scoped per day, resets to 00001 daily.
# ---------------------------------------------------------------------------
DATE=$(date +%Y%m%d)
max=0
if [ -d "$ROOT_DIR" ]; then
  for d in "$ROOT_DIR"/${DATE}-*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    seq_part=$(name_seq "$name")
    [ -n "$seq_part" ] || continue
    n=$((10#$seq_part))
    if [ "$n" -gt "$max" ]; then max="$n"; fi
  done
fi
next=$((max + 1))
SEQ=$(printf '%05d' "$next")

RUN_ID="${DATE}-${SEQ}-${SLUG}"

# ---------------------------------------------------------------------------
# Create ONE folder for this run, plus its small internal bookkeeping subfolder.
# ---------------------------------------------------------------------------
mkdir -p "$ROOT_DIR/$RUN_ID/.article-writer"

BRIEF_PATH="$ROOT_DIR/$RUN_ID/.article-writer/brief.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

export AW_RUN_ID="$RUN_ID" AW_DATE="$DATE" AW_SEQ="$SEQ" AW_SLUG="$SLUG" \
  AW_RAW_TOPIC="$RAW_TOPIC" AW_TIMESTAMP="$TIMESTAMP" AW_BRIEF_PATH="$BRIEF_PATH" \
  AW_ROOT_DIR="$ROOT_DIR" \
  AW_B_AUDIENCE="${AW_AUDIENCE:-}" AW_B_INTENTION="${AW_INTENTION:-}" \
  AW_B_ANGLE="${AW_ANGLE:-}" AW_B_POINTS="${AW_POINTS:-}" \
  AW_B_POST_CATEGORY="${AW_POST_CATEGORY:-}" AW_B_TONE="${AW_TONE:-}" \
  AW_B_LENGTH="${AW_LENGTH:-}"

$PY3 - <<'PY'
import json, os, tempfile

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

brief = {
    "run_id": os.environ["AW_RUN_ID"],
    "root": os.environ["AW_ROOT_DIR"],
    "raw_topic": os.environ["AW_RAW_TOPIC"],
    "created_at": os.environ["AW_TIMESTAMP"],
    "updated_at": os.environ["AW_TIMESTAMP"],
    "status": "drafting",
    "audience": os.environ["AW_B_AUDIENCE"] or None,
    "intention": os.environ["AW_B_INTENTION"] or None,
    "angle": os.environ["AW_B_ANGLE"] or None,
    "points_to_cover": os.environ["AW_B_POINTS"] or None,
    "post_category": os.environ["AW_B_POST_CATEGORY"] or None,
    "tone": os.environ["AW_B_TONE"] or None,
    "length": os.environ["AW_B_LENGTH"] or None,
}
write_atomic(os.environ["AW_BRIEF_PATH"], brief)
PY

printf 'RUN %s\n' "$RUN_ID"
exit 0
