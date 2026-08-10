# Requirements: `article-writer` — Claude Code Plugin

**Version:** 0.6.0
**Type:** Claude Code plugin (one command + two small scripts)

> This replaces the earlier 8-step, gated-pipeline spec (deterministic per-gate caps,
> an independent adversarial fact-checking subagent, citation-style menus, source-tier
> enforcement). That system is documented, for history only, in `CHANGELOG.md`. It was
> removed because it was built for deeply-reported journalism and made writing a
> personal blog post (a movie review, a trip log, a musing) take 45+ minutes and cost
> six figures of tokens for no real benefit to that kind of writing.

## 1. What it does

`article-writer` turns a topic (plus whatever brief details you have — audience,
intention, angle, points to cover) into a published article through one continuous,
conversational flow:

1. **Gather the brief.** Topic is required. Audience/intention/angle/points/post
   category are all optional — if audience and intention are both missing, ask once,
   briefly; otherwise proceed with sensible defaults and say what was assumed. Nothing
   ever hard-stops waiting on a form.
2. **Research**, scaled to what the piece needs. A personal reflection needs little or
   none; an opinion/review piece needs a handful of named facts checked; anything more
   involved gets a fuller pass. Prefer primary/reputable sources for anything stated as
   settled fact; say so plainly (in the draft, or by asking) when something can't be
   confirmed, rather than inventing it.
3. **Draft** the whole piece and show it in full.
4. **Iterate.** Every subsequent message about the draft is feedback — apply it, show
   the result, repeat. This conversation is the quality control. There is no fixed
   number of passes and no gate to satisfy other than the human being happy.
5. **Publish**, once the human signals they're done: write `scope.md` (a readable
   record of the brief) and `article.md` (the final piece, with site frontmatter) into
   one folder.

### Non-goals

- Not a fact-checking or journalism-verification service — see *Honest limits* below.
- Not a citation manager — sources, if relevant, are just mentioned/linked in the body.
- Not a CMS integration — output is files (`published: false` by default; the human
  flips it in their own site's admin once they've checked it).

## 2. Inputs, outputs, controls

**Inputs (the brief):** topic (required); audience, intention/purpose, angle, points to
cover, post category, tone, length (all optional, all free text, none enforced).

**Outputs (per run, one folder):**
- `scope.md` — the brief, as a readable record.
- `article.md` — the published article: YAML frontmatter (`title`, `category`, `date`,
  `excerpt`, `readTime`, `featured`, `coverImage`, `published`, `layout`, `imageAlt`,
  `image`) followed by the body.

**Interim (stays inside `.article-writer/`, inside the run folder, never shown to the
human as a deliverable):** `brief.json` (the brief + run status), `draft.md` (the
working draft through every iteration), `frontmatter.json` (title/excerpt/etc. decided
at publish time).

**Controls (`userConfig`, all soft defaults, none enforced):** `output_root`,
`audience`, `tone`, `length`, `post_category`.

## 3. Run folder

One folder per run, directly under the resolved root (`output_root`, or the current
working directory if unset):

```
<root>/<run_id>/
  scope.md                  # written at publish time
  article.md                # written at publish time
  .article-writer/
    brief.json               # the brief + status ("drafting" | "published")
    draft.md                 # the working draft
    frontmatter.json         # written just before publish
```

`run_id` is `YYYYMMDD-NNNNN-<slug>` — date prefix for chronological sort, a 5-digit
sequence reset daily, and a slug derived from the topic. A slug collision (a
trivially-reworded topic run before) halts and asks: reuse / new / cancel, rather than
silently overwriting. This part is unchanged from the earlier version and is still
handled deterministically by `scripts/init-run.sh`.

## 4. Interfaces

- `/write-article <topic + any brief details>` — starts a run (see §1).
- `/write-article continue` — resumes the most recent run still at `status: drafting`
  (asks which, if more than one).
- `scripts/init-run.sh` — allocates the run folder, writes `brief.json`.
- `scripts/publish.sh <run_id> <root>` — assembles `scope.md` + `article.md`
  deterministically from `brief.json` + `draft.md` + `frontmatter.json` (date, readTime,
  and layout are computed; title/excerpt/images are supplied by the model or default to
  a placeholder).

## 5. Honest limits

This plugin checks the concrete, checkable claims a piece states, where it has web
search available, using ordinary judgement about source quality — there is no
enforced whitelist/blacklist, no source-tiering, and no independent adversarial
re-verification step. The human reading the draft and giving feedback is the real
review. For a personal reflection with nothing externally checkable in it, research is
skipped outright, and the plugin does not imply verification it did not perform.

## 6. Non-functional

- No script in this repo makes a network call, spawns a background process, or writes
  outside the resolved run root. The only external capability used is the model's own
  declared web search/fetch during research.
- `scripts/init-run.sh` and `scripts/publish.sh` are the only two scripts anything
  calls. Every other script/skill/agent file still present in this repo is dead code
  left over from the removed gated pipeline (see `CHANGELOG.md`) and safe to delete.
