#!/usr/bin/env bash
# gate-guard.sh — deterministic PreToolUse backstop (task P2-T5).
#
# The load-bearing enforcement point. Claude Code hooks fire on TOOL-USE events, not on
# abstract "workflow iterations", so this guard enforces the bounds at the place that
# actually matters and is irreversible: emitting deliverables into output/<run>/.
#
# It DENIES a Write/Edit into any output/<run>/ path unless that run's state.json shows
# the pipeline legitimately reached the publish stage (status in step-8 | published), and
# DENIES writes once the adversarial round ceiling has been exceeded. Because the number
# and status live in files the model does not author (init-run.sh / gate-counter.sh own
# them), the bound cannot be talked around by model free-text.
#
# Reads the PreToolUse hook JSON on stdin; emits a PreToolUse permission decision as JSON
# on stdout and exits 0 (allow-by-default for anything unrelated). No jq, no network.
set -uo pipefail

INPUT="$(cat)"

python3 - "$INPUT" <<'PY'
import json, os, re, sys

raw = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    ev = json.loads(raw) if raw.strip() else {}
except Exception:
    ev = {}

tool = ev.get("tool_name") or ev.get("toolName") or ""
ti = ev.get("tool_input") or ev.get("toolInput") or {}
fp = ti.get("file_path") or ti.get("path") or ""

ALLOW = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
    }
}

def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)

def allow():
    print(json.dumps(ALLOW)); sys.exit(0)

# Only Write/Edit-family file mutations are in scope.
if tool not in ("Write", "Edit", "MultiEdit", "NotebookEdit") or not fp:
    allow()

# Is the target inside an output/<run>/ folder? Match absolute or relative paths.
m = re.search(r"(^|.*/)output/([^/]+)/", fp.replace("\\", "/"))
if not m:
    allow()  # not a deliverable write — nothing to guard

base = m.group(1)          # everything up to (and including trailing slash) before "output/"
run = m.group(2)
state_path = os.path.join(base, "interim", run, "state.json")

# If we cannot find the run's state, fail SAFE (deny) — a deliverable write with no
# matching run state is exactly the illegitimate case this guard exists to stop.
if not os.path.isfile(state_path):
    deny(f"No state.json for run '{run}' at {state_path}; refusing to write a deliverable "
         f"for a run with no tracked state.")

try:
    st = json.load(open(state_path))
except Exception as e:
    deny(f"state.json for run '{run}' is unreadable ({e}); refusing deliverable write.")

status = st.get("status", "")
PUBLISHABLE = {"step-8", "published"}
if status not in PUBLISHABLE:
    deny(f"Run '{run}' is at status '{status}', not a publish stage. Deliverables may only "
         f"be written once the pipeline reaches Step 8 / published. Complete the gated "
         f"workflow first — this write is blocked to prevent premature/early emission.")

# Adversarial round ceiling (defensive; full Step 8 logic lands in Phase 4).
adv = st.get("adversarial", {}) or {}
rounds = adv.get("rounds", 0)
cap = None
env_cap = os.environ.get("AW_ADVERSARIAL_CAP")
if env_cap and env_cap.isdigit():
    cap = int(env_cap)
else:
    cap = (st.get("controls", {}) or {}).get("adversarial_cap", 5)
if isinstance(rounds, int) and isinstance(cap, int) and rounds > cap:
    deny(f"Run '{run}' has {rounds} adversarial rounds, exceeding the cap of {cap}. "
         f"Blocked from writing further deliverables past the review ceiling.")

allow()
PY
