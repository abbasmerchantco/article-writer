# Architecture Decision — DEPRECATED

This document recorded why and how the earlier 8-step pipeline's gates and loop caps
were enforced deterministically (scripts owning counters, a `PreToolUse` hook guarding
deliverable writes). That whole architecture was removed — see `CHANGELOG.md`.

The plugin no longer has gates, caps, or a guard hook to reason about: quality control
is the human's own feedback in conversation (`docs/requirements.md` §1, §5). This file
is kept only for historical reference and is safe to delete.
