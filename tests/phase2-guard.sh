#!/usr/bin/env bash
# Phase 2 guard tests (task P2-T5). Proves the PreToolUse backstop deterministically
# blocks the one irreversible action — emitting a deliverable to output/<run>/ before the
# pipeline legitimately reached the publish stage — regardless of model intent. Runs in a
# throwaway workdir seeded by the real init-run.sh, so it exercises real state.json.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$REPO/scripts/init-run.sh"
GATE="$REPO/scripts/gate-counter.sh"
GUARD="$REPO/scripts/gate-guard.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0; FAIL=0
check(){ if eval "$2"; then echo "  ok   - $1"; PASS=$((PASS+1)); else echo "  FAIL - $1 :: [$2]"; FAIL=$((FAIL+1)); fi; }

run="$("$INIT" "Guard test subject" 2>/dev/null)"; run="${run#RUN }"
STATE="interim/$run/state.json"

# Helper: send a synthetic PreToolUse event to the guard, return permissionDecision.
decision(){ # $1 = tool, $2 = file_path
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" \
    | "$GUARD" 2>/dev/null \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['hookSpecificOutput']['permissionDecision'])"
}
setstatus(){ python3 -c "import json,sys;p='$STATE';d=json.load(open(p));d['status']=sys.argv[1];json.dump(d,open(p,'w'))" "$1"; }

# 1. Fresh run is at awaiting-scope -> writing a deliverable is DENIED
check "deliverable write denied at awaiting-scope" "[ \"\$(decision Write $WORK/output/$run/article.md)\" = deny ]"

# 2. Mid-pipeline (step-5) -> still denied
setstatus step-5
check "deliverable write denied mid-pipeline (step-5)" "[ \"\$(decision Write $WORK/output/$run/article.md)\" = deny ]"

# 3. At step-8 (review reached) -> allowed
setstatus step-8
check "deliverable write allowed at step-8" "[ \"\$(decision Write $WORK/output/$run/article.md)\" = allow ]"

# 4. published -> allowed
setstatus published
check "deliverable write allowed at published" "[ \"\$(decision Edit $WORK/output/$run/manifest.json)\" = allow ]"

# 5. Writes OUTSIDE output/ are never guarded (interim scratch is fine any time)
setstatus step-2
check "interim write always allowed" "[ \"\$(decision Write $WORK/interim/$run/notes.md)\" = allow ]"
check "non-file tool (Bash) irrelevant -> allow" "[ \"\$(printf '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}' | $GUARD 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)[\"hookSpecificOutput\"][\"permissionDecision\"])')\" = allow ]"

# 6. Deliverable write for a run with NO state -> fail safe (deny)
check "output write with no state fails safe (deny)" "[ \"\$(decision Write $WORK/output/20200101-00099-ghost/x.md)\" = deny ]"

# 7. Over the adversarial cap -> denied even at a publishable status
setstatus step-8
python3 -c "import json;p='$STATE';d=json.load(open(p));d['adversarial']['rounds']=6;d['controls']['adversarial_cap']=5;json.dump(d,open(p,'w'))"
check "write denied when adversarial rounds exceed cap" "[ \"\$(decision Write $WORK/output/$run/article.md)\" = deny ]"

# 8. Relative-path form is matched too
setstatus published
python3 -c "import json;p='$STATE';d=json.load(open(p));d['adversarial']['rounds']=0;json.dump(d,open(p,'w'))"
check "relative output path matched and allowed at published" "[ \"\$(decision Write output/$run/article.md)\" = allow ]"

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
