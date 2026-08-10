#!/usr/bin/env bash
#
# to-docx.sh — deterministic Markdown → .docx converter (feature: docx output).
#
# Usage:  to-docx.sh <input.md> <output.docx>
#
# Strategy (best available wins; all are LOCAL, no network — requirements §11):
#   1. pandoc            — highest fidelity Markdown → docx.
#   2. python-docx       — pure-Python fallback (headings, paragraphs, bold/italic, lists).
#   3. hard error        — if neither is available, exit 1 so the caller can keep the .md.
#
# Exit 0 on success (prints "DOCX <path> via <engine>"), 1 on failure.

set -euo pipefail
die() { echo "to-docx.sh: $1" >&2; exit "${2:-1}"; }
[ "$#" -eq 2 ] || die "usage: to-docx.sh <input.md> <output.docx>" 1
IN="$1"; OUT="$2"
[ -f "$IN" ] || die "input not found: $IN" 1

# Resolve a python3 interpreter (Windows may only expose python.exe/py.exe, not a
# python3 alias) for the fallback path below, and force UTF-8 I/O so non-ASCII
# characters in the article survive the conversion.
if command -v python3 >/dev/null 2>&1; then PY3=python3
elif command -v python >/dev/null 2>&1; then PY3=python
elif command -v py >/dev/null 2>&1; then PY3="py -3"
else PY3=""
fi
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

# 1. pandoc
if command -v pandoc >/dev/null 2>&1; then
  if pandoc "$IN" -f markdown -t docx -o "$OUT" 2>/dev/null; then
    echo "DOCX $OUT via pandoc"; exit 0
  fi
fi

# 2. python-docx fallback (minimal but correct Markdown subset)
if [ -n "$PY3" ] && $PY3 -c "import docx" >/dev/null 2>&1; then
  $PY3 - "$IN" "$OUT" <<'PY'
import re, sys
from docx import Document

src, out = sys.argv[1], sys.argv[2]
doc = Document()

def add_runs(paragraph, text):
    # Split on **bold** and *italic* / _italic_ while keeping delimiters.
    tokens = re.split(r"(\*\*.+?\*\*|\*.+?\*|_.+?_)", text)
    for tok in tokens:
        if not tok:
            continue
        if tok.startswith("**") and tok.endswith("**"):
            paragraph.add_run(tok[2:-2]).bold = True
        elif (tok.startswith("*") and tok.endswith("*")) or (tok.startswith("_") and tok.endswith("_")):
            paragraph.add_run(tok[1:-1]).italic = True
        else:
            paragraph.add_run(tok)

lines = open(src, encoding="utf-8").read().splitlines()
for raw in lines:
    line = raw.rstrip()
    if not line.strip():
        continue
    m = re.match(r"^(#{1,6})\s+(.*)$", line)
    if m:
        doc.add_heading(m.group(2).strip(), level=min(len(m.group(1)), 6))
        continue
    m = re.match(r"^\s*[-*+]\s+(.*)$", line)
    if m:
        p = doc.add_paragraph(style="List Bullet")
        add_runs(p, m.group(1))
        continue
    m = re.match(r"^\s*\d+[.)]\s+(.*)$", line)
    if m:
        p = doc.add_paragraph(style="List Number")
        add_runs(p, m.group(1))
        continue
    p = doc.add_paragraph()
    add_runs(p, line)

doc.save(out)
print("DOCX %s via python-docx" % out)
PY
  exit 0
fi

die "no docx engine available (need pandoc or python-docx). Keeping Markdown." 1
