#!/usr/bin/env bash
# Referencing + docx tests (feature: citations & Word output).
# Covers format-references.sh (styles + none), to-docx.sh (valid .docx), and
# make-manifest.sh emitting article.docx + references.md honoring controls.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$REPO/scripts/init-run.sh"; FR="$REPO/scripts/format-references.sh"
TD="$REPO/scripts/to-docx.sh"; MAN="$REPO/scripts/make-manifest.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT; cd "$WORK"
PASS=0; FAIL=0
ck(){ if eval "$2"; then echo "  ok   - $1"; PASS=$((PASS+1)); else echo "  FAIL - $1 :: [$2]"; FAIL=$((FAIL+1)); fi; }

run="$("$INIT" "refs and docx" 2>/dev/null)"; run="${run#RUN }"; S="interim/$run/state.json"
python3 - "$S" <<'PY'
import json,sys
p=sys.argv[1];d=json.load(open(p))
d["references"]=[
 {"id":"yasuoka2011","authors":["Yasuoka, K.","Yasuoka, M."],"year":"2011","title":"On the prehistory of QWERTY","container":"ZINBUN","url":"https://doi.org/x"},
 {"id":"smith2013","authors":["Smithsonian Magazine"],"year":"2013","title":"The QWERTY keyboard will never die","container":"Smithsonian","url":"https://s.mag/x"}]
json.dump(d,open(p,'w'),indent=2)
PY

echo "== format-references.sh =="
ck "apa map -> author-date in-text" "AW_CITATION_STYLE=apa $FR $S map | grep -q '(Yasuoka & Yasuoka, 2011)'"
ck "ieee map -> numeric in-text" "AW_CITATION_STYLE=ieee $FR $S map | grep -q '\\[1\\]'"
ck "apa bibliography heading = References" "AW_CITATION_STYLE=apa $FR $S bibliography | grep -q '## References'"
ck "mla bibliography heading = Works Cited" "AW_CITATION_STYLE=mla $FR $S bibliography | grep -q '## Works Cited'"
ck "chicago-notes heading = Bibliography" "AW_CITATION_STYLE=chicago-notes $FR $S bibliography | grep -q '## Bibliography'"
ck "vancouver bibliography is numbered" "AW_CITATION_STYLE=vancouver $FR $S bibliography | grep -qE '^1\\. '"
ck "none -> empty map" "[ \"\$(AW_CITATION_STYLE=none $FR $S map | tr -d '[:space:]')\" = '{}' ]"
ck "no double-period in chicago author string" "! AW_CITATION_STYLE=chicago-author-date $FR $S bibliography | grep -q 'M\\.\\.'"

echo "== to-docx.sh =="
printf '# Title\n\nBody **bold** *italic* (Yasuoka & Yasuoka, 2011).\n\n## References\n\n- x\n' > a.md
ck "to-docx produces a file" "$TD a.md a.docx >/dev/null 2>&1 && [ -f a.docx ]"
ck "output is a real Word docx (zip/OOXML)" "python3 -c \"from docx import Document; Document('a.docx')\" 2>/dev/null"
ck "docx preserves headings" "python3 -c \"from docx import Document;print([p.text for p in Document('a.docx').paragraphs])\" | grep -q References"

echo "== make-manifest.sh docx + references emission =="
printf '# A\n\nClaim (Yasuoka & Yasuoka, 2011).\n\n## References\n\n- Yasuoka...\n' > "interim/$run/draft.md"
python3 -c "import json;p='$S';d=json.load(open(p));d['status']='step-8';d['controls']['citation_style']='apa';d['controls']['output_format']='docx';d['adversarial']={'rounds':1,'ledger':[{'verdict':'verified'}],'verification_guarantee':'external-truth'};json.dump(d,open(p,'w'))"
"$MAN" "$run" >/dev/null 2>&1
ck "article.docx emitted" "[ -f output/$run/article.docx ]"
ck "article.md kept as source" "[ -f output/$run/article.md ]"
ck "references.md emitted (formatted bibliography)" "[ -f output/$run/references.md ] && grep -q '## References' output/$run/references.md"
ck "manifest records citation_style + output_format" "python3 -c \"import json;m=json.load(open('output/$run/manifest.json'));assert m['citation_style']=='apa' and m['output_format']=='docx' and m['reference_count']==2\""

echo "== output_format=md skips docx; style=none skips references.md =="
run2="$("$INIT" --force-new "md only no refs" 2>/dev/null)"; run2="${run2#RUN }"; S2="interim/$run2/state.json"
printf '# B\n\nNo cites here.\n' > "interim/$run2/draft.md"
python3 -c "import json;p='$S2';d=json.load(open(p));d['status']='step-8';d['controls']['citation_style']='none';d['controls']['output_format']='md';d['adversarial']={'rounds':1,'ledger':[],'verification_guarantee':'external-truth'};json.dump(d,open(p,'w'))"
"$MAN" "$run2" >/dev/null 2>&1
ck "output_format=md -> no article.docx" "[ ! -f output/$run2/article.docx ] && [ -f output/$run2/article.md ]"
ck "citation_style=none -> no references.md" "[ ! -f output/$run2/references.md ]"

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
