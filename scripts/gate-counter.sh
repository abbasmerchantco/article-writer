#!/usr/bin/env bash
#
# gate-counter.sh — deterministic per-gate counter and cap enforcer.
#
# SOLE mutator of per-gate fail counters in state.json (requirements §5.3, §8, §10;
# contracts.md §3). No model free-text ever writes these fields.
#
# Usage:
#   gate-counter.sh <state_path> <gate> get     # print current fail count, exit 0
#   gate-counter.sh <state_path> <gate> pass    # reset counter to 0, print PASS, exit 0
#   gate-counter.sh <state_path> <gate> fail    # increment; enforce cap
#
#   <gate> ∈ step-1 … step-7  (Step 8 uses the adversarial loop, not this counter).
#
# `fail` semantics (cap enforcement, contracts.md §3 / requirements §5.1):
#   - increment the gate's fail counter, then compare against the cap
#     (AW_PER_GATE_CAP env, else state.controls.per_gate_cap, else 3).
#   - count < cap  -> print "RETRY <count>", exit 0.
#   - count >= cap -> print "ESCALATE <target>" (routing table below),
#                     append {gate,target,at} to state.escalation_history,
#                     reset the gate counter to 0 (escalation restarts the upstream
#                     budget), exit 3.
#
# Escalation routing table (contracts.md §3 / requirements §5.1):
#   step-1 -> HALT-HUMAN   step-2 -> step-1   step-3 -> step-2   step-4 -> step-3
#   step-5 -> step-3       step-6 -> step-5   step-7 -> step-5
#
# All mutations write state.json atomically (temp file + mv) and bump updated_at
# (ISO-8601 UTC). Self-contained; no network calls (requirements §11). Uses python3
# for all JSON handling (no jq dependency). Targets bash 3.2 (macOS).

set -euo pipefail

usage() {
  echo "usage: gate-counter.sh <state_path> <gate> get|pass|fail" >&2
  echo "  <gate> in step-1 .. step-7" >&2
}

die() {
  echo "gate-counter.sh: $1" >&2
  exit "${2:-1}"
}

# Resolve a python3 interpreter (Windows may only expose python.exe/py.exe, not a
# python3 alias) and force UTF-8 I/O so non-ASCII characters in state.json survive
# read/write round-trips instead of being mangled by the system locale codepage.
if command -v python3 >/dev/null 2>&1; then PY3=python3
elif command -v python >/dev/null 2>&1; then PY3=python
elif command -v py >/dev/null 2>&1; then PY3="py -3"
else die "no python3 interpreter found on PATH (tried python3, python, py -3)" 1
fi
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

if [ "$#" -ne 3 ]; then
  usage
  exit 1
fi

STATE_PATH="$1"
GATE="$2"
ACTION="$3"

# Validate gate token.
case "$GATE" in
  step-1|step-2|step-3|step-4|step-5|step-6|step-7) ;;
  *) die "unknown gate '$GATE' (expected step-1 .. step-7)" 1 ;;
esac

# Validate action.
case "$ACTION" in
  get|pass|fail) ;;
  *) die "unknown action '$ACTION' (expected get|pass|fail)" 1 ;;
esac

# Validate state file exists and is a readable regular file.
if [ ! -f "$STATE_PATH" ]; then
  die "state file not found: $STATE_PATH" 1
fi

# AW_PER_GATE_CAP is optional; pass through empty when unset (bash 3.2-safe).
CAP_ENV="${AW_PER_GATE_CAP:-}"

# All read/modify/write logic runs in python3. It prints one result line to stdout
# and uses its exit code to signal outcome:
#   exit 0  -> normal (get/pass/RETRY)
#   exit 3  -> escalation
#   exit 1  -> invalid state JSON / other python-side error
$PY3 - "$STATE_PATH" "$GATE" "$ACTION" "$CAP_ENV" <<'PY'
import json, os, sys, tempfile
from datetime import datetime, timezone

state_path, gate, action, cap_env = sys.argv[1:5]

ROUTING = {
    "step-1": "HALT-HUMAN",
    "step-2": "step-1",
    "step-3": "step-2",
    "step-4": "step-3",
    "step-5": "step-3",
    "step-6": "step-5",
    "step-7": "step-5",
}

def fail(msg):
    sys.stderr.write("gate-counter.sh: %s\n" % msg)
    sys.exit(1)

# --- Load state -----------------------------------------------------------
try:
    with open(state_path, "r") as f:
        state = json.load(f)
except (ValueError, OSError) as e:
    fail("invalid or unreadable state JSON: %s" % e)

if not isinstance(state, dict):
    fail("state root is not a JSON object")

gates = state.get("gates")
if not isinstance(gates, dict):
    fail("state.gates missing or not an object")

entry = gates.get(gate)
if not isinstance(entry, dict):
    fail("state.gates['%s'] missing or not an object" % gate)

try:
    current = int(entry.get("fails", 0))
except (TypeError, ValueError):
    fail("state.gates['%s'].fails is not an integer" % gate)

# --- get: read-only -------------------------------------------------------
if action == "get":
    sys.stdout.write("%d\n" % current)
    sys.exit(0)

# --- Resolve cap (fail only, but harmless to compute) --------------------
def resolve_cap():
    if cap_env.strip() != "":
        try:
            c = int(cap_env)
        except ValueError:
            fail("AW_PER_GATE_CAP is not an integer: %r" % cap_env)
        if c < 1:
            fail("AW_PER_GATE_CAP must be >= 1")
        return c
    controls = state.get("controls")
    if isinstance(controls, dict) and controls.get("per_gate_cap") is not None:
        try:
            c = int(controls["per_gate_cap"])
        except (TypeError, ValueError):
            fail("state.controls.per_gate_cap is not an integer")
        if c < 1:
            fail("state.controls.per_gate_cap must be >= 1")
        return c
    return 3

def atomic_write(obj):
    # Write to a temp file in the same directory, then os.replace (atomic on POSIX).
    obj["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    d = os.path.dirname(os.path.abspath(state_path))
    fd, tmp = tempfile.mkstemp(prefix=".state.", suffix=".json.tmp", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, state_path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

# --- pass: reset to 0 -----------------------------------------------------
if action == "pass":
    entry["fails"] = 0
    atomic_write(state)
    sys.stdout.write("PASS\n")
    sys.exit(0)

# --- fail: increment, enforce cap ----------------------------------------
if action == "fail":
    cap = resolve_cap()
    new_count = current + 1

    # Cumulative per-gate attempt count — incremented on every fail, NEVER reset by
    # pass/escalate. The current-cycle `fails` drives cap enforcement; `attempts` is the
    # lifetime iteration count the run manifest reports (requirements §2.2).
    try:
        entry["attempts"] = int(entry.get("attempts", 0)) + 1
    except (TypeError, ValueError):
        entry["attempts"] = 1

    if new_count < cap:
        entry["fails"] = new_count
        atomic_write(state)
        sys.stdout.write("RETRY %d\n" % new_count)
        sys.exit(0)

    # new_count >= cap -> escalate.
    target = ROUTING[gate]
    hist = state.get("escalation_history")
    if not isinstance(hist, list):
        hist = []
        state["escalation_history"] = hist
    at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    hist.append({"gate": gate, "target": target, "at": at})
    # Escalation restarts the upstream step's budget: reset this gate counter.
    entry["fails"] = 0
    atomic_write(state)
    sys.stdout.write("ESCALATE %s\n" % target)
    sys.exit(3)

fail("unreachable action: %s" % action)
PY
