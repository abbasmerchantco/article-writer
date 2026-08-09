#!/usr/bin/env bash
# Originality gate tests (Step 5, Pass 2): originality-check.sh scan + verify. Confirms the
# deterministic overlap scan detects captured-source copying and honestly reports an empty
# corpus, and that verify only clears a blocking flag when its ethical remedy actually
# landed in the draft. Throwaway workdir seeded by the real init-run.sh.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$REPO/scripts/init-run.sh"
OC="$REPO/scripts/originality-check.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0; FAIL=0
check(){ if eval "$2"; then echo "  ok   - $1"; PASS=$((PASS+1)); else echo "  FAIL - $1 :: [$2]"; FAIL=$((FAIL+1)); fi; }

run="$("$INIT" "Originality gate subject" 2>/dev/null)"; run="${run#RUN }"
STATE="interim/$run/state.json"
DRAFT="interim/$run/draft.md"

# Helpers: set draft text; set the originality block (corpus+flags); set references[].
setdraft(){ printf '%s' "$1" > "$DRAFT"; }
setorig(){ python3 -c "import json,sys;p='$STATE';d=json.load(open(p));d['originality']=json.loads(sys.argv[1]);json.dump(d,open(p,'w'))" "$1"; }
setrefs(){ python3 -c "import json,sys;p='$STATE';d=json.load(open(p));d['references']=json.loads(sys.argv[1]);json.dump(d,open(p,'w'))" "$1"; }

echo "== originality-check.sh scan =="
# 1. verbatim copy of a captured excerpt -> overlap detected (>= 8 words)
setdraft 'Intro. The quick brown fox jumps over the lazy sleeping dog today. Outro.'
setorig '{"checked":true,"detection_guarantee":"source-comparison","corpus":[{"source":"Src A","text":"The quick brown fox jumps over the lazy sleeping dog today."}],"flags":[]}'
scan="$("$OC" "$STATE" "$DRAFT" scan 2>/dev/null)"
check "scan reports source-comparison guarantee" "printf '%s' \"\$scan\" | grep -q 'source-comparison'"
check "scan detects the copied span" "printf '%s' \"\$scan\" | grep -q 'quick brown fox jumps over the lazy sleeping dog'"

# 2. empty corpus -> internal-only, no false clean
setorig '{"checked":true,"detection_guarantee":"internal-only","corpus":[],"flags":[]}'
scan2="$("$OC" "$STATE" "$DRAFT" scan 2>/dev/null)"
check "empty corpus -> internal-only" "printf '%s' \"\$scan2\" | grep -q 'internal-only'"
check "empty corpus -> zero overlaps" "printf '%s' \"\$scan2\" | grep -q '\"overlaps\": \\[\\]'"

echo "== originality-check.sh verify =="
# 3. blocking rewrite flag, copied passage STILL present -> UNRESOLVED (exit 3)
setdraft 'The mitochondria is the powerhouse of the cell, as many textbooks note.'
setorig '{"checked":true,"detection_guarantee":"source-comparison","corpus":[],"flags":[{"id":"o1","passage":"the mitochondria is the powerhouse of the cell","type":"verbatim-copy","matched_source":"Src","similarity":"high","severity":"blocking","remedy":"rewrite","ref_id":null}]}'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; rc=$?
check "unfixed rewrite -> exit 3" "[ $rc -eq 3 ]"

# 4. same flag, passage genuinely rewritten out -> resolved (exit 0)
setdraft 'Cells generate most of their energy in specialized internal structures.'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; rc=$?
check "rewritten-out -> exit 0" "[ $rc -eq 0 ]"

# 4b. blocking rewrite flag with EMPTY passage -> UNRESOLVED (regression: was fail-open).
setorig '{"checked":true,"detection_guarantee":"source-comparison","corpus":[],"flags":[{"id":"oE","passage":"","type":"verbatim-copy","matched_source":"Src","similarity":"high","severity":"blocking","remedy":"rewrite","ref_id":null}]}'
setdraft 'Any text at all, unrelated to the missing passage.'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; check "empty-passage blocking rewrite -> exit 3" "[ \$? -eq 3 ]"

# 5. quote-and-attribute: must be BOTH quoted AND attributed (ref_id present in references[]).
setorig '{"checked":true,"detection_guarantee":"source-comparison","corpus":[],"flags":[{"id":"o2","passage":"a rising tide lifts all boats","type":"unattributed-quote","matched_source":"Src","similarity":"high","severity":"blocking","remedy":"quote-and-attribute","ref_id":"refK"}]}'
setrefs '[{"id":"refK","title":"Some Speech","year":"1963"}]'
setdraft 'He argued that a rising tide lifts all boats in the economy.'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; check "quote present but unquoted -> exit 3" "[ \$? -eq 3 ]"
setdraft 'He argued that "a rising tide lifts all boats" in the economy (Kennedy, 1963).'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; check "quoted + attributed -> exit 0" "[ \$? -eq 0 ]"
setrefs '[]'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; check "quoted but unattributed (ref removed) -> exit 3" "[ \$? -eq 3 ]"

# 6. attribute (reworded idea): needs a ref_id that exists in references[]
setorig '{"checked":true,"detection_guarantee":"source-comparison","corpus":[],"flags":[{"id":"o3","passage":"the original framing text","type":"uncredited-idea","matched_source":"Src","similarity":"medium","severity":"blocking","remedy":"attribute","ref_id":"ref9"}]}'
setrefs '[]'
setdraft 'A reworded version of the borrowed idea appears here.'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; check "attribute w/ missing ref -> exit 3" "[ \$? -eq 3 ]"
setrefs '[{"id":"ref9","title":"Some Source","year":"2020"}]'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; check "attribute w/ real ref -> exit 0" "[ \$? -eq 0 ]"

# 7. advisory flag never fails the gate even if its passage lingers
setorig '{"checked":true,"detection_guarantee":"source-comparison","corpus":[],"flags":[{"id":"o4","passage":"in this day and age","type":"close-paraphrase","matched_source":null,"similarity":"low","severity":"advisory","remedy":"rewrite","ref_id":null}]}'
setdraft 'In this day and age the common phrase persists.'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; check "advisory flag never fails -> exit 0" "[ \$? -eq 0 ]"

# 8. mixed: one resolved + one unresolved blocking -> exit 3 (any unresolved fails)
setorig '{"checked":true,"detection_guarantee":"source-comparison","corpus":[],"flags":[{"id":"a","passage":"gone text","severity":"blocking","remedy":"remove","ref_id":null},{"id":"b","passage":"lingering copied text","severity":"blocking","remedy":"remove","ref_id":null}]}'
setdraft 'Only the lingering copied text remains here.'
"$OC" "$STATE" "$DRAFT" verify >/dev/null 2>&1; check "any unresolved blocking -> exit 3" "[ \$? -eq 3 ]"

echo "== init-run seeds originality block =="
# Fresh run so the seed is untouched by the mutations above.
run2="$("$INIT" "Second originality seed subject" 2>/dev/null)"; run2="${run2#RUN }"; S2="interim/$run2/state.json"
check "fresh state has originality.checked=false" "[ \"\$(python3 -c \"import json;print(json.load(open('$S2'))['originality'].get('checked'))\" 2>/dev/null)\" = 'False' ]"
check "fresh state has empty originality.flags" "[ \"\$(python3 -c \"import json;print(len(json.load(open('$S2'))['originality'].get('flags',[])))\" 2>/dev/null)\" = 0 ]"
check "fresh state has plagiarism_ngram control = 8" "[ \"\$(python3 -c \"import json;print(json.load(open('$S2'))['controls'].get('plagiarism_ngram'))\" 2>/dev/null)\" = 8 ]"

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
