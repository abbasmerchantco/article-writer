#!/usr/bin/env bash
# Phase 7 tests: output_root / AW_OUTPUT_ROOT (requirements §2.4/§3.1a; CHANGELOG 0.4.0).
# Verifies init-run.sh resolves a custom run root (creating it, recording paths.root
# absolutely, scoping dedup/sequence to it, honoring backward-compat cwd fallback) and
# that make-manifest.sh's new optional [root_dir] argument emits deliverables under the
# right root. Throwaway workdir; never touches the repo.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$REPO/scripts/init-run.sh"
MAN="$REPO/scripts/make-manifest.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0; FAIL=0
check(){ if eval "$2"; then echo "  ok   - $1"; PASS=$((PASS+1)); else echo "  FAIL - $1 :: [$2]"; FAIL=$((FAIL+1)); fi; }
jget(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split('.'):
    d=d[k]
print(d)" "$1" "$2"; }

echo "== init-run.sh: default (no AW_OUTPUT_ROOT) unchanged =="
out0="$("$INIT" "Default root behavior" 2>/dev/null)"; run0="${out0#RUN }"
check "default run created under cwd" "[ -d input/$run0 ] && [ -d interim/$run0 ] && [ -d output/$run0 ]"
check "default paths.root == cwd" "[ \"\$(jget interim/$run0/state.json paths.root)\" = '$WORK' ]"
check "default controls.output_root == cwd" "[ \"\$(jget interim/$run0/state.json controls.output_root)\" = '$WORK' ]"
check "trigger.json also carries paths.root" "[ \"\$(jget input/$run0/trigger.json paths.root)\" = '$WORK' ]"
check "state.json has a references[] field at init" "[ \"\$(jget interim/$run0/state.json references)\" = '[]' ]"

echo "== init-run.sh: custom AW_OUTPUT_ROOT =="
CUSTOM="$WORK/custom-root"
out1="$(AW_OUTPUT_ROOT="$CUSTOM" "$INIT" "Custom root behavior" 2>/dev/null)"; run1="${out1#RUN }"
check "custom-root run created under CUSTOM, not cwd" "[ -d '$CUSTOM/input/$run1' ] && [ ! -d 'input/$run1' ]"
check "custom-root paths.root resolves to CUSTOM (absolute)" "[ \"\$(jget "$CUSTOM/interim/$run1/state.json" paths.root)\" = '$CUSTOM' ]"
check "CUSTOM directory was auto-created" "[ -d '$CUSTOM' ]"

echo "== init-run.sh: slug dedup is scoped correctly, sequence is independent per root =="
dup="$(AW_OUTPUT_ROOT="$CUSTOM" "$INIT" "Custom root behavior" 2>/dev/null)"; dup_rc=$?
check "re-running same subject under same custom root -> DUPLICATE_MATCH" "[ $dup_rc -eq 2 ] && printf '%s' '$dup' | grep -q '^DUPLICATE_MATCH '"
out2="$(AW_OUTPUT_ROOT="$CUSTOM" "$INIT" "A second distinct custom-root subject" 2>/dev/null)"; run2="${out2#RUN }"
check "custom root has its own independent 00001/00002 sequence" "printf '%s' '$run1' | grep -q -- '-00001-' && printf '%s' '$run2' | grep -q -- '-00002-'"
check "plain cwd sequence unaffected by custom-root runs (still 00002 next)" "printf '%s' \"\$($INIT --force-new 'Yet another plain cwd subject' 2>/dev/null)\" | grep -q -- '-00002-'"

echo "== init-run.sh: --reuse works against a custom root =="
reuse="$(AW_OUTPUT_ROOT="$CUSTOM" "$INIT" --reuse "$run1" 2>/dev/null)"
check "--reuse finds the run under its custom root" "[ \"\$reuse\" = 'RUN $run1' ]"

echo "== init-run.sh: backward compatibility (legacy cwd run still found once a root is set) =="
legacy_out="$("$INIT" "A legacy subject with no root" 2>/dev/null)"; legacy_run="${legacy_out#RUN }"
legacy_dup="$(AW_OUTPUT_ROOT="$CUSTOM" "$INIT" "A legacy subject with no root" 2>/dev/null)"; legacy_rc=$?
check "legacy plain-cwd run still detected as duplicate when a custom root is later set" "[ $legacy_rc -eq 2 ] && printf '%s' '$legacy_dup' | grep -q '^DUPLICATE_MATCH '"
legacy_reuse="$(AW_OUTPUT_ROOT="$CUSTOM" "$INIT" --reuse "$legacy_run" 2>/dev/null)"
check "--reuse falls back to plain cwd for a legacy run when custom root doesn't have it" "[ \"\$legacy_reuse\" = 'RUN $legacy_run' ]"

echo "== make-manifest.sh: [root_dir] argument =="
STATE="$CUSTOM/interim/$run1/state.json"
printf '# Draft\nBody.\n' > "$CUSTOM/interim/$run1/draft.md"
python3 -c "
import json
p='$STATE'
d=json.load(open(p))
d['status']='step-8'
d['research']={'claims':[{'claim':'c','source':'Nature 2021','tier':'peer-reviewed','independent':True}]}
d['adversarial']={'rounds':1,'ledger':[{'verdict':'verified','load_bearing':True}],'verification_guarantee':'external-truth'}
json.dump(d,open(p,'w'))
"
mout="$("$MAN" "$run1" "$CUSTOM" 2>/dev/null)"; mrc=$?
check "make-manifest.sh with explicit root_dir succeeds" "[ $mrc -eq 0 ] && printf '%s' '$mout' | grep -q '^MANIFEST '"
check "deliverables land under CUSTOM/output/<run>, not plain cwd" "[ -f '$CUSTOM/output/$run1/article.md' ] && [ ! -f 'output/$run1/article.md' ]"
check "manifest.json valid under custom root" "[ \"\$(jget "$CUSTOM/output/$run1/manifest.json" run_id)\" = '$run1' ]"

echo "== make-manifest.sh: omitted root_dir still defaults to cwd (backward compat) =="
STATE0="interim/$run0/state.json"
printf '# Draft\nBody.\n' > "interim/$run0/draft.md"
python3 -c "
import json
p='$STATE0'
d=json.load(open(p))
d['status']='step-8'
d['research']={'claims':[]}
d['adversarial']={'rounds':1,'ledger':[],'verification_guarantee':'external-truth'}
json.dump(d,open(p,'w'))
"
"$MAN" "$run0" >/dev/null 2>&1
check "omitted root_dir defaults to cwd (article.md lands in plain output/)" "[ -f output/$run0/article.md ]"

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
