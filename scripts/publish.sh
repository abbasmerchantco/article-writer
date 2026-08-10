#!/usr/bin/env bash
#
# publish.sh — deterministic final assembly for article-writer.
#
# Takes the finished draft (agreed with the human through conversation - no gates, no
# caps) and writes the two files the human actually wants in the run folder:
#
#   <root>/<run_id>/scope.md     — a readable record of the brief (topic, audience,
#                                  intention, angle, points to cover)
#   <root>/<run_id>/article.md   — the final article, with YAML frontmatter matching
#                                  the site's expected shape (title/category/date/
#                                  excerpt/readTime/featured/coverImage/published/
#                                  layout/imageAlt/image), ready to drop into the site.
#
# The model decides title/excerpt/featured/cover-image (judgement) and writes them to
# <run_id>/.article-writer/frontmatter.json before calling this script; this script
# computes the mechanical fields (date, readTime, layout, category from the brief) and
# assembles both files deterministically, so formatting is consistent run to run.
#
# Usage:  publish.sh <run_id> <root_dir>
#
# No jq, no network, bash 3.2+.

set -euo pipefail
die() { echo "publish.sh: $1" >&2; exit "${2:-1}"; }

if command -v python3 >/dev/null 2>&1; then PY3=python3
elif command -v python >/dev/null 2>&1; then PY3=python
elif command -v py >/dev/null 2>&1; then PY3="py -3"
else die "no python3 interpreter found on PATH (tried python3, python, py -3)" 1
fi
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

[ "$#" -eq 2 ] || die "usage: publish.sh <run_id> <root_dir>" 1
RUN="$1"
ROOT_DIR="$2"
RUN_DIR="$ROOT_DIR/$RUN"
WORK_DIR="$RUN_DIR/.article-writer"
BRIEF="$WORK_DIR/brief.json"
DRAFT="$WORK_DIR/draft.md"
FRONTMATTER="$WORK_DIR/frontmatter.json"

[ -d "$RUN_DIR" ] || die "run folder not found: $RUN_DIR" 1
[ -f "$BRIEF" ]   || die "brief.json not found: $BRIEF" 1
[ -f "$DRAFT" ]   || die "draft.md not found: $DRAFT (nothing to publish yet)" 1

$PY3 - "$RUN" "$RUN_DIR" "$BRIEF" "$DRAFT" "$FRONTMATTER" <<'PY'
import json, math, os, re, sys, tempfile
from datetime import datetime, timezone

run, run_dir, brief_path, draft_path, fm_path = sys.argv[1:6]

def die(msg):
    sys.stderr.write("publish.sh: %s\n" % msg); sys.exit(1)

try:
    brief = json.load(open(brief_path, encoding="utf-8"))
except (ValueError, OSError) as e:
    die("invalid or unreadable brief.json: %s" % e)

try:
    body = open(draft_path, encoding="utf-8").read().strip() + "\n"
except OSError as e:
    die("unreadable draft.md: %s" % e)

frontmatter_in = {}
if os.path.isfile(fm_path):
    try:
        frontmatter_in = json.load(open(fm_path, encoding="utf-8")) or {}
    except (ValueError, OSError) as e:
        die("invalid frontmatter.json: %s" % e)

title = frontmatter_in.get("title") or brief.get("raw_topic") or "Untitled"
excerpt = frontmatter_in.get("excerpt") or ""
featured = bool(frontmatter_in.get("featured", False))
published = bool(frontmatter_in.get("published", False))
slug_for_placeholder = re.sub(r"[^a-z0-9-]", "", run.split("-", 2)[-1].lower()) or "image"
cover_image = frontmatter_in.get("coverImage") or ("/images/uploads/TODO-%s.jpg" % slug_for_placeholder)
image = frontmatter_in.get("image") or ("/images/uploads/TODO-%s.svg" % slug_for_placeholder)
image_alt = frontmatter_in.get("imageAlt") or "TODO: add alt text"
category = brief.get("post_category") or "uncategorized"
date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

# readTime: whole minutes at ~225 wpm, minimum 1, as a quoted string (matches the site's
# sample post: readTime: "1").
words = len(re.findall(r"\S+", body))
read_minutes = max(1, math.ceil(words / 225.0))

LAYOUT = "layouts/post.njk"

# --- YAML scalar rendering -------------------------------------------------
# Deliberately hand-rolled (no PyYAML dependency). Plain (unquoted) scalars for simple
# values; double-quoted + escaped for anything that would break a plain scalar.
# `excerpt` gets the same folded/wrapped plain-scalar style the site's own sample post
# uses (first line "key: ...", continuation lines indented 2 spaces) when it is safe to
# render unquoted; otherwise it falls back to a single-line quoted string.

SPECIAL_LEAD = set('!&*-?|>%@`"\'#[]{},:')

def looks_numeric(s):
    try:
        float(s)
        return True
    except ValueError:
        return False

def needs_quoting(s):
    if s == "" or s.strip() != s:
        return True
    if s[0] in SPECIAL_LEAD:
        return True
    if ": " in s or s.endswith(":") or " #" in s:
        return True
    if s.lower() in ("true", "false", "null", "~", "yes", "no"):
        return True
    if looks_numeric(s):
        return True
    return False

def dquote(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')

def plain_or_quoted_line(key, value):
    s = str(value)
    if needs_quoting(s):
        return "%s: %s" % (key, dquote(s))
    return "%s: %s" % (key, s)

def wrap_words(text, width=74):
    words_ = text.split()
    lines, cur = [], ""
    for w in words_:
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w) if cur else w
    if cur:
        lines.append(cur)
    return lines

def excerpt_block(key, value):
    s = str(value or "")
    if not s:
        return "%s: \"\"" % key
    if needs_quoting(s):
        # Fall back to a single quoted line rather than risk an unsafe folded scalar.
        return "%s: %s" % (key, dquote(s))
    lines = wrap_words(s)
    if len(lines) == 1:
        return "%s: %s" % (key, lines[0])
    out = ["%s: %s" % (key, lines[0])]
    out += ["  %s" % ln for ln in lines[1:]]
    return "\n".join(out)

def bool_line(key, value):
    return "%s: %s" % (key, "true" if value else "false")

fm_lines = [
    "---",
    plain_or_quoted_line("title", title),
    plain_or_quoted_line("category", category),
    plain_or_quoted_line("date", date_str),
    excerpt_block("excerpt", excerpt),
    'readTime: "%d"' % read_minutes,
    bool_line("featured", featured),
    plain_or_quoted_line("coverImage", cover_image),
    bool_line("published", published),
    plain_or_quoted_line("layout", LAYOUT),
    plain_or_quoted_line("imageAlt", image_alt),
    plain_or_quoted_line("image", image),
    "---",
    "",
]

article_path = os.path.join(run_dir, "article.md")
with open(article_path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(fm_lines))
    f.write(body)

# --- scope.md: a readable record of the brief, refreshed at publish time ---
def line_or_default(label, value, default="(not specified)"):
    return "**%s:** %s" % (label, value if value else default)

scope_lines = [
    "# Scope — %s" % run,
    "",
    line_or_default("Topic", brief.get("raw_topic")),
    line_or_default("Audience", brief.get("audience")),
    line_or_default("Intention", brief.get("intention")),
    line_or_default("Angle", brief.get("angle")),
    line_or_default("Points to cover", brief.get("points_to_cover")),
    line_or_default("Post category", brief.get("post_category")),
    line_or_default("Tone", brief.get("tone")),
    line_or_default("Length", brief.get("length")),
    "",
    "**Created:** %s  " % brief.get("created_at", ""),
    "**Published:** %s" % date_str,
]
with open(os.path.join(run_dir, "scope.md"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(scope_lines) + "\n")

# --- mark the brief published ---
brief["status"] = "published"
brief["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
d = os.path.dirname(os.path.abspath(brief_path))
fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-", suffix=".json")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(brief, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, brief_path)

print("PUBLISHED %s -> %s" % (run, article_path))
PY
