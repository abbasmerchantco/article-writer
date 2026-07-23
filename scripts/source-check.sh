#!/usr/bin/env bash
#
# source-check.sh — deterministic source-tier policy validator (task P5-T1).
#
# Enforces the §6 source policy on the recorded research: every LOAD-BEARING claim must
# rest on a whitelisted, sufficiently-high tier. A load-bearing claim whose only source is
# blacklisted or low/unknown tier is a VIOLATION — it must be treated as `unsupported` and
# independently re-sourced or cut (requirements §6.3, routes per §5.2). Non-load-bearing
# claims are reported as warnings but do not fail the check.
#
# Usage:  source-check.sh <state_path>
#   exit 0 — no load-bearing violations
#   exit 3 — one or more load-bearing violations (treat those claims as unsupported)
#   exit 1 — usage / unreadable state
#
# Tier classification is keyword-based over each claim's `tier` (and `source`) string, so
# it tolerates the free-text tiers the research step records. No jq, no network, bash 3.2.

set -euo pipefail
die() { echo "source-check.sh: $1" >&2; exit "${2:-1}"; }
[ "$#" -eq 1 ] || die "usage: source-check.sh <state_path>" 1
[ -f "$1" ] || die "state file not found: $1" 1

# Locate the canonical source policy (single source of truth). Resolution order:
#   1. AW_SOURCE_POLICY_FILE env override
#   2. <plugin_root>/config/source-policy.json, derived from this script's own location
#      (works in-repo AND in the installed plugin cache).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_FILE="${AW_SOURCE_POLICY_FILE:-$SCRIPT_DIR/../config/source-policy.json}"
[ -f "$POLICY_FILE" ] || die "source policy file not found: $POLICY_FILE" 1

python3 - "$1" "$POLICY_FILE" <<'PY'
import json, re, sys

state = json.load(open(sys.argv[1]))
policy = json.load(open(sys.argv[2]))
claims = (state.get("research", {}) or {}).get("claims", []) or []

# Blacklist / whitelist signals + blocked domains/URL patterns come from the CANONICAL
# policy file — never hardcoded here (requirements §6; config/source-policy.json is the
# single source of truth).
BLACK = [s.lower() for s in policy.get("blacklist", {}).get("signals", [])]
WHITE = [s.lower() for s in policy.get("whitelist", {}).get("signals", [])]
BLOCKED_DOMAINS = [d.lower().lstrip("*").lstrip(".") for d in
                   policy.get("blocked_domains", {}).get("domains", []) if d.strip()]
BLOCKED_PATTERNS = [p.lower() for p in
                    policy.get("blocked_url_patterns", {}).get("patterns", []) if p.strip()]

HOST_RE = re.compile(r"(?:https?://)?(?:www\.)?((?:[a-z0-9-]+\.)+[a-z]{2,})")

def source_text(claim):
    # Everything that might carry a URL/citation for this claim.
    return " ".join(str(claim.get(k, "")) for k in ("source", "independent_source", "url")).lower()

def blocked_hit(claim):
    """Return (kind, matched) if the source is HARD-blocked by domain or URL pattern."""
    text = source_text(claim)
    for pat in BLOCKED_PATTERNS:
        if pat in text:
            return ("url-pattern", pat)
    # Extract candidate hosts and do proper suffix matching (so 'reddit.com' blocks
    # 'old.reddit.com' but NOT 'notreddit.com').
    for host in HOST_RE.findall(text):
        for d in BLOCKED_DOMAINS:
            if host == d or host.endswith("." + d):
                return ("domain", d)
    return None

def classify(claim):
    blob = ("%s %s" % (claim.get("tier", ""), claim.get("source", ""))).lower()
    if any(b in blob for b in BLACK):
        return "blacklist"
    if any(w in blob for w in WHITE):
        return "whitelist"
    return "unknown"

violations, warnings = [], []
for c in claims:
    if not isinstance(c, dict):
        continue
    lb = bool(c.get("load_bearing"))
    hit = blocked_hit(c)
    if hit:
        # HARD block: a blocked domain / URL pattern is a violation for ANY claim.
        violations.append({"claim": c.get("claim"), "tier": c.get("tier"),
                           "source": c.get("source"), "class": "blocked-%s" % hit[0],
                           "matched": hit[1]})
        continue
    cls = classify(c)
    if cls in ("blacklist", "unknown"):
        rec = {"claim": c.get("claim"), "tier": c.get("tier"),
               "source": c.get("source"), "class": cls, "matched": None}
        (violations if lb else warnings).append(rec)

print("source-check: %d claim(s), %d violation(s), %d non-load-bearing warning(s)"
      % (len(claims), len(violations), len(warnings)))
for v in violations:
    if v["class"].startswith("blocked-"):
        print("  VIOLATION (HARD-BLOCKED %s: %r) -> source rejected, must be re-sourced: %r [source=%r]"
              % (v["class"], v["matched"], v["claim"], v["source"]))
    else:
        print("  VIOLATION (load-bearing, %s tier) -> treat as UNSUPPORTED: %r [tier=%r source=%r]"
              % (v["class"], v["claim"], v["tier"], v["source"]))
for w in warnings:
    print("  warning (non-load-bearing, %s tier): %r [tier=%r]"
          % (w["class"], w["claim"], w["tier"]))

sys.exit(3 if violations else 0)
PY
