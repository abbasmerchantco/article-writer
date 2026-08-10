#!/usr/bin/env bash
# Phase 1 deterministic-core tests (task P1-T8).
# Exercises init-run.sh + gate-counter.sh against the contracts.md spine and the
# deterministic §10 acceptance criteria. Runs entirely in a throwaway workdir so the
# repo is never polluted. Verifies the init-run -> gate-counter INTEGRATION point.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$REPO/scripts/init-run.sh"
GATE="$REPO/scripts/gate-counter.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0; FAIL=0
ok()   { echo "  ok   - $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL - $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1 :: [$2]"; fi; }
jvalid(){ python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" 2>/dev/null; }

echo "== init-run.sh =="

# 1. First run today -> 00001
out1="$("$INIT" "Return to office economics" 2>/dev/null)"; rc=$?
run1="${out1#RUN }"
check "first run prints RUN and exits 0" "[ $rc -eq 0 ] && [ -n '$run1' ]"
check "first run sequence is 00001" "printf '%s' '$run1' | grep -q -- '-00001-'"
check "input/interim/output triplet created" "[ -d input/$run1 ] && [ -d interim/$run1 ] && [ -d output/$run1 ]"
check "trigger.json is valid JSON" "jvalid input/$run1/trigger.json"
check "state.json is valid JSON" "jvalid interim/$run1/state.json"
check "state status is awaiting-scope" "python3 -c \"import json;print(json.load(open('interim/$run1/state.json'))['status'])\" | grep -q awaiting-scope"
check "raw_subject preserved verbatim in trigger" "python3 -c \"import json;print(json.load(open('input/$run1/trigger.json'))['raw_subject'])\" | grep -q 'Return to office economics'"

# post_category / research_mode / rigor_tier (requirements §2.4, §4 Step 1/2) - blank/
# "deep" until Step 1 resolves them; adversarial_cap default softened 5 -> 3.
check "default post_category is blank" "[ \"\$(python3 -c \"import json;print(repr(json.load(open('interim/$run1/state.json'))['controls']['post_category']))\")\" = \"''\" ]"
check "default research_mode is deep" "[ \"\$(python3 -c \"import json;print(json.load(open('interim/$run1/state.json'))['controls']['research_mode'])\")\" = 'deep' ]"
check "default rigor_tier is null (unset until Step 1)" "python3 -c \"import json;assert json.load(open('interim/$run1/state.json'))['controls']['rigor_tier'] is None\""
check "default adversarial_cap is now 3 (softened from 5)" "[ \"\$(python3 -c \"import json;print(json.load(open('interim/$run1/state.json'))['controls']['adversarial_cap'])\")\" = '3' ]"

# AW_POST_CATEGORY / AW_RESEARCH_MODE env overrides reach state.controls, same pattern
# as every other AW_* control.
outc2="$(AW_POST_CATEGORY=musings AW_RESEARCH_MODE=none "$INIT" --force-new "A musing about slow mornings" 2>/dev/null)"
runc2="${outc2#RUN }"
check "AW_POST_CATEGORY reaches state.controls.post_category" "[ \"\$(python3 -c \"import json;print(json.load(open('interim/$runc2/state.json'))['controls']['post_category'])\")\" = 'musings' ]"
check "AW_RESEARCH_MODE reaches state.controls.research_mode" "[ \"\$(python3 -c \"import json;print(json.load(open('interim/$runc2/state.json'))['controls']['research_mode'])\")\" = 'none' ]"

# 2. Second run (force-new) -> 00002
out2="$("$INIT" --force-new "A totally different subject about bees" 2>/dev/null)"
run2="${out2#RUN }"
check "second run sequence is 00002" "printf '%s' '$run2' | grep -q -- '-00002-'"

# 3. Slug collision -> DUPLICATE_MATCH, exit 2, nothing created
before="$(ls input | wc -l | tr -d ' ')"
dup_out="$("$INIT" "return-to-office ECONOMICS!!!" 2>/dev/null)"; dup_rc=$?
after="$(ls input | wc -l | tr -d ' ')"
check "slug collision exits 2" "[ $dup_rc -eq 2 ]"
check "slug collision prints DUPLICATE_MATCH" "printf '%s' '$dup_out' | grep -q '^DUPLICATE_MATCH '"
check "slug collision creates nothing" "[ '$before' = '$after' ]"

# 4. Per-day reset: seed a prior-date run, confirm today still allocates fresh
mkdir -p input/20200101-00042-old interim/20200101-00042-old output/20200101-00042-old
out3="$("$INIT" --force-new "Yet another distinct topic on tides" 2>/dev/null)"
run3="${out3#RUN }"
today="$(date +%Y%m%d)"
check "per-day sequence ignores other dates (today not reset by 2020 folder)" "printf '%s' '$run3' | grep -q '^${today}-000'"

# 5. Leading-zero chronological sort intact
sorted="$(ls input | sort)"
check "folders sort chronologically with leading zeros" "printf '%s' \"\$sorted\" | head -1 | grep -q '^20200101-'"

echo "== gate-counter.sh (integration: real state.json from init-run) =="
STATE="interim/$run1/state.json"

# 6. state.controls.per_gate_cap resolved from init-run's (softened) default is 2
check "init-run's default per_gate_cap is now 2 (softened from 3, requirements §2.4)" \
  "[ \"\$(python3 -c \"import json;print(json.load(open('$STATE'))['controls']['per_gate_cap'])\")\" = '2' ]"

# 7. step-5 fail x3 with an explicit cap=3 override -> RETRY, RETRY, ESCALATE step-3
# (exercised at cap 3 explicitly, decoupled from whatever the shipped default is)
r1="$(AW_PER_GATE_CAP=3 "$GATE" "$STATE" step-5 fail 2>/dev/null)"
r2="$(AW_PER_GATE_CAP=3 "$GATE" "$STATE" step-5 fail 2>/dev/null)"
r3="$(AW_PER_GATE_CAP=3 "$GATE" "$STATE" step-5 fail 2>/dev/null)"; rc3=$?
check "step-5 fail #1 -> RETRY 1" "[ '$r1' = 'RETRY 1' ]"
check "step-5 fail #2 -> RETRY 2" "[ '$r2' = 'RETRY 2' ]"
check "step-5 fail #3 -> ESCALATE step-3" "[ '$r3' = 'ESCALATE step-3' ]"
check "escalation exits 3" "[ $rc3 -eq 3 ]"
check "state.json still valid after mutations" "jvalid '$STATE'"
check "step-5 counter reset to 0 after escalation" "[ \"\$($GATE '$STATE' step-5 get 2>/dev/null)\" = '0' ]"
check "escalation_history recorded one entry" "python3 -c \"import json;print(len(json.load(open('$STATE'))['escalation_history']))\" | grep -q '^1$'"

# 8. pass resets counter
"$GATE" "$STATE" step-2 fail >/dev/null 2>&1
p="$("$GATE" "$STATE" step-2 pass 2>/dev/null)"
check "pass prints PASS and resets" "[ '$p' = 'PASS' ] && [ \"\$($GATE '$STATE' step-2 get 2>/dev/null)\" = '0' ]"

# 9. step-1 escalates to HALT-HUMAN at cap (explicit cap=3 override, decoupled from
#    whichever default per_gate_cap ships)
AW_PER_GATE_CAP=3 "$GATE" "$STATE" step-1 fail >/dev/null 2>&1
AW_PER_GATE_CAP=3 "$GATE" "$STATE" step-1 fail >/dev/null 2>&1
h="$(AW_PER_GATE_CAP=3 "$GATE" "$STATE" step-1 fail 2>/dev/null)"
check "step-1 at cap -> ESCALATE HALT-HUMAN" "[ '$h' = 'ESCALATE HALT-HUMAN' ]"

# 10. AW_PER_GATE_CAP override -> immediate escalate
e="$(AW_PER_GATE_CAP=1 "$GATE" "$STATE" step-4 fail 2>/dev/null)"
check "AW_PER_GATE_CAP=1 escalates step-4 immediately to step-3" "[ '$e' = 'ESCALATE step-3' ]"

# 11. invalid usage guards
"$GATE" "$STATE" step-9 fail >/dev/null 2>&1; check "unknown gate exits 1" "[ \$? -eq 1 ]"
"$GATE" "$STATE" step-5 frobnicate >/dev/null 2>&1; check "unknown action exits 1" "[ \$? -eq 1 ]"
"$GATE" /nonexistent/state.json step-1 get >/dev/null 2>&1; check "missing state file exits 1" "[ \$? -eq 1 ]"

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
