#!/usr/bin/env bash
#
# review-loop.sh — deterministic Step 8 adversarial-loop controller (task P4-T2).
#
# The model (adversarial-reviewer agent) produces JUDGEMENT — a classified ledger. This
# script owns the CONTROL: it counts rounds, enforces min/max bounds, decides early-stop,
# and computes the severity-based routing target. Loop control must be deterministic, not
# model self-report (requirements §5.2, §5.3, §11; contracts.md §6).
#
# Usage:
#   review-loop.sh <state_path> <ledger_json_path>
#
# <ledger_json_path> is the reviewer's output for THIS round (schema: object with
# `verification_guarantee` and `ledger[]` of {verdict, load_bearing, ...}).
#
# Behaviour (per invocation = one completed review round):
#   1. rounds += 1 (persisted; hard-capped so it can never exceed the max).
#   2. Store this round's ledger + verification_guarantee into state.adversarial.
#   3. Analyse the ledger for SUBSTANTIVE problems (cosmetic/verified never count):
#        load-bearing wrong/misrepresented  |  unsupported  |  peripheral wrong
#   4. Decide and print exactly one control line:
#        STOP-CLEAN                 -> no substantive problems; min already satisfied; publish. exit 0
#        ROUTE <step>               -> fix upstream, then re-review. exit 0
#        CAP-REACHED <n_unresolved> -> max rounds hit with problems still open; do NOT loop
#                                      again. exit 3 (orchestrator publishes WITH disclosure
#                                      in the manifest, or halts for human per policy).
#
# Severity routing (requirements §5.2), most-severe first:
#   load-bearing wrong/misrepresented -> step-3   (thesis rests on a false premise;
#                                                   escalates to step-1 if it has PERSISTED)
#   unsupported                       -> step-2   (research didn't finish — source or cut)
#   peripheral wrong                  -> step-5   (correct in place, re-review)
#
# min/max come from AW_ADVERSARIAL_MIN/CAP env, else state.controls, else 1/5.
# Atomic writes, no jq, no network, bash 3.2 (macOS).

set -euo pipefail

usage() { echo "usage: review-loop.sh <state_path> <ledger_json_path>" >&2; }
die() { echo "review-loop.sh: $1" >&2; exit "${2:-1}"; }

# Resolve a python3 interpreter (Windows may only expose python.exe/py.exe, not a
# python3 alias) and force UTF-8 I/O so non-ASCII characters in state.json survive
# read/write round-trips instead of being mangled by the system locale codepage.
if command -v python3 >/dev/null 2>&1; then PY3=python3
elif command -v python >/dev/null 2>&1; then PY3=python
elif command -v py >/dev/null 2>&1; then PY3="py -3"
else die "no python3 interpreter found on PATH (tried python3, python, py -3)" 1
fi
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

[ "$#" -eq 2 ] || { usage; exit 1; }
STATE_PATH="$1"
LEDGER_PATH="$2"
[ -f "$STATE_PATH" ]  || die "state file not found: $STATE_PATH" 1
[ -f "$LEDGER_PATH" ] || die "ledger file not found: $LEDGER_PATH" 1

MIN_ENV="${AW_ADVERSARIAL_MIN:-}"
CAP_ENV="${AW_ADVERSARIAL_CAP:-}"

$PY3 - "$STATE_PATH" "$LEDGER_PATH" "$MIN_ENV" "$CAP_ENV" <<'PY'
import json, os, sys, tempfile
from datetime import datetime, timezone

state_path, ledger_path, min_env, cap_env = sys.argv[1:5]

def die(msg):
    sys.stderr.write("review-loop.sh: %s\n" % msg); sys.exit(1)

try:
    state = json.load(open(state_path))
except (ValueError, OSError) as e:
    die("invalid or unreadable state JSON: %s" % e)
try:
    review = json.load(open(ledger_path))
except (ValueError, OSError) as e:
    die("invalid or unreadable ledger JSON: %s" % e)
if not isinstance(state, dict):
    die("state root is not an object")

def resolve(env, controls_key, default):
    if env.strip() != "":
        try: v = int(env)
        except ValueError: die("%s is not an integer: %r" % (controls_key, env))
    else:
        c = state.get("controls", {}) or {}
        v = c.get(controls_key, default)
        try: v = int(v)
        except (TypeError, ValueError): die("controls.%s is not an integer" % controls_key)
    if v < 1: die("%s must be >= 1" % controls_key)
    return v

cap = resolve(cap_env, "adversarial_cap", 5)
mn  = resolve(min_env, "adversarial_min", 1)
if mn > cap: mn = cap

adv = state.get("adversarial")
if not isinstance(adv, dict):
    adv = {"rounds": 0, "ledger": []}
    state["adversarial"] = adv

# --- 1. count this round (hard-capped so rounds can never exceed the max) ---
rounds = int(adv.get("rounds", 0)) + 1
if rounds > cap:
    rounds = cap
adv["rounds"] = rounds

# --- 2. persist this round's ledger + guarantee ---
ledger = review.get("ledger", [])
if not isinstance(ledger, list):
    die("ledger.ledger is not a list")
adv["ledger"] = ledger
guarantee = review.get("verification_guarantee")
if guarantee in ("external-truth", "internal-consistency-only"):
    adv["verification_guarantee"] = guarantee
else:
    # Absent/invalid -> record the weaker guarantee honestly (never over-claim).
    adv["verification_guarantee"] = "internal-consistency-only"

# --- 3. analyse substantive problems ---
def is_wrongish(v): return v in ("wrong", "misrepresented")
lb_wrong = any(is_wrongish(i.get("verdict")) and i.get("load_bearing") for i in ledger if isinstance(i, dict))
unsupported = any(i.get("verdict") == "unsupported" for i in ledger if isinstance(i, dict))
periph_wrong = any(is_wrongish(i.get("verdict")) and not i.get("load_bearing") for i in ledger if isinstance(i, dict))
n_unresolved = sum(1 for i in ledger if isinstance(i, dict)
                   and (i.get("verdict") in ("wrong", "misrepresented", "unsupported")))
substantive = lb_wrong or unsupported or periph_wrong

def atomic_write(obj):
    obj["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    d = os.path.dirname(os.path.abspath(state_path))
    fd, tmp = tempfile.mkstemp(prefix=".state.", suffix=".json.tmp", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f, indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, state_path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise

# --- 4. decide ---
# min-reviews floor: even a clean ledger must run at least `mn` rounds before STOP-CLEAN.
if not substantive:
    if rounds < mn:
        atomic_write(state)
        # Clean, but the minimum review count isn't met yet — run another round.
        sys.stdout.write("ROUTE re-review\n"); sys.exit(0)
    atomic_write(state)
    sys.stdout.write("STOP-CLEAN\n"); sys.exit(0)

# Substantive problems remain.
if rounds >= cap:
    atomic_write(state)
    sys.stdout.write("CAP-REACHED %d\n" % n_unresolved); sys.exit(3)

# Route by highest severity. Load-bearing that has PERSISTED (seen at/after the midpoint of
# the budget) points at the angle/thesis itself -> step-1; otherwise the structure -> step-3.
if lb_wrong:
    target = "step-1" if rounds >= (cap + 1) // 2 else "step-3"
elif unsupported:
    target = "step-2"
else:
    target = "step-5"
atomic_write(state)
sys.stdout.write("ROUTE %s\n" % target); sys.exit(0)
PY
