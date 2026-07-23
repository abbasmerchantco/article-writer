#!/usr/bin/env bash
# Phase 4 deterministic tests (P4-T2/P4-T3): review-loop routing/cap/min, manifest
# emission + self-guard, and the cumulative per-gate attempts counter. Throwaway workdir
# seeded by the real init-run.sh.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$REPO/scripts/init-run.sh"
GATE="$REPO/scripts/gate-counter.sh"
LOOP="$REPO/scripts/review-loop.sh"
MAN="$REPO/scripts/make-manifest.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0; FAIL=0
check(){ if eval "$2"; then echo "  ok   - $1"; PASS=$((PASS+1)); else echo "  FAIL - $1 :: [$2]"; FAIL=$((FAIL+1)); fi; }

run="$("$INIT" "Phase four review subject" 2>/dev/null)"; run="${run#RUN }"
STATE="interim/$run/state.json"
setstatus(){ python3 -c "import json,sys;p='$STATE';d=json.load(open(p));d['status']=sys.argv[1];json.dump(d,open(p,'w'))" "$1"; }
mkledger(){ printf '%s' "$1" > ledger.json; }
setrounds(){ python3 -c "import json;p='$STATE';d=json.load(open(p));d['adversarial']['rounds']=$1;json.dump(d,open(p,'w'))"; }

echo "== review-loop.sh =="
# 1. Clean ledger, min 1 satisfied -> STOP-CLEAN
setrounds 0
mkledger '{"verification_guarantee":"external-truth","ledger":[{"claim":"x","verdict":"verified","load_bearing":true}]}'
out="$("$LOOP" "$STATE" ledger.json 2>/dev/null)"
check "clean ledger -> STOP-CLEAN" "[ '$out' = 'STOP-CLEAN' ]"
check "round incremented to 1" "[ \"\$(python3 -c \"import json;print(json.load(open('$STATE'))['adversarial']['rounds'])\")\" = 1 ]"

# 2. min floor: clean but AW_ADVERSARIAL_MIN=2 at round1 -> ROUTE re-review
setrounds 0
o2="$(AW_ADVERSARIAL_MIN=2 "$LOOP" "$STATE" ledger.json 2>/dev/null)"
check "clean but under min -> ROUTE re-review" "[ '$o2' = 'ROUTE re-review' ]"

# 3. unsupported -> ROUTE step-2
setrounds 0
mkledger '{"verification_guarantee":"external-truth","ledger":[{"claim":"x","verdict":"unsupported","load_bearing":false}]}'
check "unsupported -> ROUTE step-2" "[ \"\$($LOOP $STATE ledger.json 2>/dev/null)\" = 'ROUTE step-2' ]"

# 4. peripheral wrong -> ROUTE step-5
setrounds 0
mkledger '{"verification_guarantee":"external-truth","ledger":[{"claim":"x","verdict":"wrong","load_bearing":false}]}'
check "peripheral wrong -> ROUTE step-5" "[ \"\$($LOOP $STATE ledger.json 2>/dev/null)\" = 'ROUTE step-5' ]"

# 5. load-bearing wrong early -> ROUTE step-3
setrounds 0
mkledger '{"verification_guarantee":"external-truth","ledger":[{"claim":"x","verdict":"misrepresented","load_bearing":true}]}'
check "load-bearing wrong early -> ROUTE step-3" "[ \"\$($LOOP $STATE ledger.json 2>/dev/null)\" = 'ROUTE step-3' ]"

# 6. load-bearing wrong PERSISTED (round>=midpoint of cap 5 =3) -> ROUTE step-1
setrounds 2
check "load-bearing wrong persisted -> ROUTE step-1" "[ \"\$($LOOP $STATE ledger.json 2>/dev/null)\" = 'ROUTE step-1' ]"

# 7. cap reached with problems -> CAP-REACHED, exit 3, rounds never exceed cap
setrounds 4
o7="$("$LOOP" "$STATE" ledger.json 2>/dev/null)"; rc=$?
check "cap reached -> CAP-REACHED 1" "[ '$o7' = 'CAP-REACHED 1' ]"
check "cap-reached exits 3" "[ $rc -eq 3 ]"
check "rounds hard-capped at 5" "[ \"\$(python3 -c \"import json;print(json.load(open('$STATE'))['adversarial']['rounds'])\")\" = 5 ]"

# 8. verification guarantee downgraded honestly when missing/invalid
setrounds 0
mkledger '{"ledger":[{"claim":"x","verdict":"verified","load_bearing":false}]}'
"$LOOP" "$STATE" ledger.json >/dev/null 2>&1
check "missing guarantee -> internal-consistency-only" "[ \"\$(python3 -c \"import json;print(json.load(open('$STATE'))['adversarial']['verification_guarantee'])\")\" = 'internal-consistency-only' ]"

echo "== gate-counter cumulative attempts =="
setstatus awaiting-scope
"$GATE" "$STATE" step-3 fail >/dev/null 2>&1   # attempts 1, fails 1
"$GATE" "$STATE" step-3 pass >/dev/null 2>&1   # fails reset 0, attempts stays 1
"$GATE" "$STATE" step-3 fail >/dev/null 2>&1   # attempts 2
check "attempts is cumulative across pass (=2)" "[ \"\$(python3 -c \"import json;print(json.load(open('$STATE'))['gates']['step-3'].get('attempts'))\")\" = 2 ]"
check "fails reset by pass (=1 after last fail)" "[ \"\$($GATE $STATE step-3 get 2>/dev/null)\" = 1 ]"

echo "== make-manifest.sh =="
# self-guard: refuse before publish stage
setstatus step-5
"$MAN" "$run" >/dev/null 2>&1; check "manifest refuses before publish stage (exit 2)" "[ \$? -eq 2 ]"
check "no manifest written pre-publish" "[ ! -f output/$run/manifest.json ]"

# emit at step-8
printf '# Draft\nBody.\n' > "interim/$run/draft.md"
python3 -c "import json;p='$STATE';d=json.load(open(p));d['research']={'claims':[{'claim':'c','source':'Nature 2021','tier':'peer-reviewed','independent':True}]};d['adversarial']={'rounds':2,'ledger':[{'verdict':'verified','load_bearing':True}],'verification_guarantee':'external-truth'};json.dump(d,open(p,'w'))"
setstatus step-8
mout="$("$MAN" "$run" 2>/dev/null)"
check "manifest emits at step-8" "printf '%s' '$mout' | grep -q '^MANIFEST '"
check "article.md written" "[ -f output/$run/article.md ]"
check "sources.md written with tier" "grep -q 'peer-reviewed' output/$run/sources.md"
check "manifest.json valid + verdict clean" "[ \"\$(python3 -c \"import json;print(json.load(open('output/$run/manifest.json'))['final_verdict'])\")\" = 'clean-review' ]"
check "manifest states external-truth guarantee" "grep -q 'external truth' output/$run/manifest.md"

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
