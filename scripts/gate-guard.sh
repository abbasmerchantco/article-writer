#!/usr/bin/env bash
# DEPRECATED — removed in the article-writer simplification (see CHANGELOG.md).
# hooks/hooks.json no longer registers this as a PreToolUse hook, so Claude Code never
# invokes this file. Kept only because this session could not delete it (no shell
# access) — safe to delete manually.
echo "gate-guard.sh: deprecated, no longer used by article-writer (see CHANGELOG.md)" >&2
exit 0
