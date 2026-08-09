#!/usr/bin/env bash
#
# format-references.sh — deterministic citation formatter (feature: referencing).
#
# Renders the run's structured references[] into a chosen citation style, so formatting is
# CONSISTENT and not re-invented by the model each time. The research step gathers the
# structured bibliographic fields (judgement); this script renders them (deterministic).
#
# Usage:
#   format-references.sh <state_path> bibliography   # print the formatted reference list (markdown)
#   format-references.sh <state_path> map            # print JSON { ref_id: "in-text citation" }
#
# Style comes from state.controls.citation_style (or AW_CITATION_STYLE env override).
# Supported: apa | mla | chicago-author-date | chicago-notes | harvard | ieee | vancouver | none
# No jq, no network, bash 3.2 (macOS). Approximates the major conventions faithfully; it is a
# consistent renderer, not a full CSL processor.

set -euo pipefail
die() { echo "format-references.sh: $1" >&2; exit "${2:-1}"; }
[ "$#" -eq 2 ] || die "usage: format-references.sh <state_path> bibliography|map" 1
[ -f "$1" ] || die "state file not found: $1" 1
case "$2" in bibliography|map) ;; *) die "mode must be 'bibliography' or 'map'" 1 ;; esac

STYLE_ENV="${AW_CITATION_STYLE:-}"

python3 - "$1" "$2" "$STYLE_ENV" <<'PY'
import json, sys

state_path, mode, style_env = sys.argv[1:4]
state = json.load(open(state_path))
refs = state.get("references", []) or []
style = (style_env.strip()
         or (state.get("controls", {}) or {}).get("citation_style", "apa")).strip().lower()

# Normalise a few aliases.
ALIASES = {"apa7": "apa", "apa-7": "apa", "mla9": "mla", "chicago": "chicago-author-date",
           "author-date": "chicago-author-date", "notes": "chicago-notes"}
style = ALIASES.get(style, style)

def parse_author(a):
    a = (a or "").strip()
    if "," in a:
        last, rest = a.split(",", 1)
        return last.strip(), rest.strip()
    return a, ""            # organisation / single-token name

def last_names(authors):
    return [parse_author(a)[0] for a in authors if a and a.strip()]

def intext(ref, number=None):
    """In-text citation for one reference in the active style."""
    ls = last_names(ref.get("authors", []))
    yr = str(ref.get("year", "n.d.")).strip() or "n.d."
    if style in ("ieee", "vancouver"):
        return "[%s]" % number if number is not None else "[?]"
    if not ls:
        # fall back to title if no authors
        t = ref.get("title", "Untitled")
        short = t if len(t) < 40 else t[:37] + "…"
        return "(%s, %s)" % (short, yr) if style in ("apa", "harvard", "chicago-author-date") else "(%s)" % short
    if len(ls) == 1:
        who = ls[0]
    elif len(ls) == 2:
        joiner = " & " if style in ("apa", "harvard") else " and "
        who = joiner.join(ls)
    else:
        who = "%s et al." % ls[0]
    if style == "mla":
        return "(%s)" % who
    if style == "chicago-author-date":
        return "(%s %s)" % (who, yr)
    # apa, harvard, chicago-notes fallback
    return "(%s, %s)" % (who, yr)

def authors_bib(authors):
    """Author string for the bibliography, style-dependent."""
    parsed = [parse_author(a) for a in authors if a and a.strip()]
    if not parsed:
        return ""
    def apa(p):   # Last, F. M.
        return ("%s, %s" % (p[0], p[1])).strip().rstrip(",")
    if style in ("apa", "harvard", "chicago-author-date", "chicago-notes"):
        items = [apa(p) for p in parsed]
        if len(items) == 1:
            return items[0]
        return ", ".join(items[:-1]) + ", & " + items[-1] if style in ("apa", "harvard") \
               else ", ".join(items[:-1]) + ", and " + items[-1]
    if style == "mla":
        # First author "Last, First", rest "First Last"
        out = [", ".join(x for x in parsed[0] if x)]
        for p in parsed[1:]:
            out.append(("%s %s" % (p[1], p[0])).strip())
        if len(out) == 1:
            return out[0]
        return ", ".join(out[:-1]) + ", and " + out[-1]
    if style in ("ieee", "vancouver"):
        # Initials first: F. M. Last
        def il(p): return ("%s %s" % (p[1], p[0])).strip()
        return ", ".join(il(p) for p in parsed)
    return ", ".join(apa(p) for p in parsed)

def entry(ref, number=None):
    a = authors_bib(ref.get("authors", []))
    yr = str(ref.get("year", "n.d.")).strip() or "n.d."
    title = (ref.get("title") or "Untitled").strip()
    cont = (ref.get("container") or "").strip()
    pub = (ref.get("publisher") or "").strip()
    url = (ref.get("url") or "").strip()
    def j(*parts): return " ".join(p for p in parts if p)
    def dot(s): return s if s.endswith(".") else s + "."   # avoid doubling a trailing period
    if style == "apa":
        s = j(("%s" % a) + ("" if not a else ""), "(%s)." % yr, "%s." % title)
        if cont: s = j(s, "*%s*." % cont)
        if pub and pub != cont: s = j(s, "%s." % pub)
        if url: s = j(s, url)
        return s
    if style == "harvard":
        s = j("%s" % a, "%s." % yr, "*%s*." % title)
        if cont: s = j(s, "%s." % cont)
        if pub and pub != cont: s = j(s, "%s." % pub)
        if url: s = j(s, "Available at: %s" % url)
        return s
    if style == "mla":
        s = j(dot(a) if a else "", "*%s*." % title)
        if cont: s = j(s, "%s," % cont)
        if pub and pub != cont: s = j(s, "%s," % pub)
        s = j(s, "%s." % yr)
        if url: s = j(s, url + ".")
        return s
    if style in ("chicago-author-date", "chicago-notes"):
        s = j(dot(a) if a else "", "%s." % yr, "\"%s.\"" % title)
        if cont: s = j(s, "*%s*." % cont)
        if pub and pub != cont: s = j(s, "%s." % pub)
        if url: s = j(s, url + ".")
        return s
    if style in ("ieee", "vancouver"):
        num = ("[%s] " % number) if (style == "ieee" and number) else \
              ("%s. " % number if (style == "vancouver" and number) else "")
        s = num + j(("%s," % a) if a else "", "\"%s,\"" % title)
        if cont: s = j(s, "*%s*," % cont)
        if pub and pub != cont: s = j(s, "%s," % pub)
        s = j(s, "%s." % yr)
        if url: s = j(s, url)
        return s
    # default -> apa-like
    return j(a, "(%s)." % yr, "%s." % title, cont, url)

HEADINGS = {"mla": "Works Cited", "chicago-notes": "Bibliography"}
heading = HEADINGS.get(style, "References")

if style == "none":
    if mode == "map":
        print("{}")
    else:
        print("")  # no references section
    sys.exit(0)

if mode == "map":
    m = {}
    for i, r in enumerate(refs, 1):
        rid = r.get("id") or ("ref%d" % i)
        m[rid] = intext(r, number=i)
    print(json.dumps(m, indent=2))
    sys.exit(0)

# bibliography
numbered = style in ("ieee", "vancouver")
ordered = refs if numbered else sorted(
    refs, key=lambda r: (last_names(r.get("authors", [])) or [r.get("title", "")])[0].lower())
lines = ["## %s" % heading, ""]
for i, r in enumerate(ordered, 1):
    e = entry(r, number=i)
    lines.append(e if numbered else "- %s" % e)
print("\n".join(lines) + "\n")
PY
