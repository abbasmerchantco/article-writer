# Integration Contracts — DEPRECATED

This document described the `state.json` schema and script interfaces for the earlier
8-step gated pipeline (per-gate caps, adversarial review loop, citation styles,
source-tier enforcement). That system was removed — see `CHANGELOG.md` for what
replaced it and why.

The current, much smaller interface (just `scripts/init-run.sh` and `scripts/publish.sh`,
and the `brief.json`/`draft.md`/`frontmatter.json` files they read and write) is
described in `docs/requirements.md` §3–§4. This file is kept only for historical
reference and is safe to delete.
