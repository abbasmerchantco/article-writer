---
name: write-article
description: >-
  Entry point for article-writer. `/write-article <topic and any brief details>`
  gathers the brief (audience, intention, angle, points to cover), researches the
  topic, writes a draft, and then iterates on your feedback conversationally until
  you're happy — at which point it writes the final formatted article (plus a scope
  record) into one folder. `/write-article continue` resumes a draft in progress.
argument-hint: "<topic + any brief details> | continue"
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, WebSearch, WebFetch, AskUserQuestion
---

# `/write-article` — one simple flow: brief → research → draft → iterate → publish

You are writing an article **with** the human, conversationally. There are no gates,
no caps, no adversarial review, no rigid step sequence to obey — those existed in an
earlier version of this plugin and were deliberately removed (see `CHANGELOG.md`)
because they made a personal-blog writing tool slow and heavy for what it actually
needs to do. The only real quality control here is **the human's own feedback**, given
in plain conversation, which you act on until they're happy.

## Resolving the run root

Do this once, first. This plugin's configured `output_root` value is:

```
${user_config.output_root}
```

Claude Code substitutes the real configured value into that line before you ever see
this file. Export it so `init-run.sh`/`publish.sh` resolve the same root:

```
export AW_OUTPUT_ROOT="<value>"
```

(blank/unset → `AW_OUTPUT_ROOT=""`, which `init-run.sh` treats as "use the current
working directory"). If what you see above is still the literal text
`${user_config.output_root}` with braces intact, substitution didn't happen — treat it
as blank rather than passing that placeholder string anywhere.

The argument you were invoked with is:

```
$ARGUMENTS
```

- If it is exactly `continue` (case-insensitive, no other words) → go to **Resuming a
  draft** below.
- If it is empty → ask the user what they'd like to write about (topic is the one
  thing you can't proceed without) and stop.
- Otherwise → treat the whole argument as the **topic and whatever brief details the
  human chose to include**, and go to **Starting a new run** below.

---

## Starting a new run

### 1. Extract the brief from what they gave you

Read the argument as natural language, not a form with required syntax. Pull out
whichever of these the human already told you, in whatever order or phrasing they used:

- **topic** — required; it's why they ran the command.
- **audience** — who this is for.
- **intention / purpose** — what they want the reader to take away, or just "why write
  this."
- **angle** — a preferred lens or stance, if they have one.
- **points to cover** — anything that has to appear.
- **post category** — if it's for a specific section of their blog (e.g. musings,
  learnings, movies, books, photos, travel, mba) — this only flavors how much research
  you do (see step 3), it's not a rigid enum.
- **tone / length** — if mentioned.

**Don't hard-stop on anything missing.** If audience and intention are *both* absent,
ask one short, friendly question for those two (they shape everything downstream more
than the others) — a single message, not a form. If only some details are missing,
just proceed with reasonable defaults and say what you assumed, e.g. "I'll write this
for general readers of your blog unless you tell me otherwise." The human can always
correct you once they see the draft — that's what the feedback loop is for.

### 2. Allocate the run folder

```
${CLAUDE_PLUGIN_ROOT}/scripts/init-run.sh "<topic>"
```

with the brief exported first:

```
export AW_AUDIENCE="<audience or blank>" AW_INTENTION="<intention or blank>" \
       AW_ANGLE="<angle or blank>" AW_POINTS="<points to cover or blank>" \
       AW_POST_CATEGORY="<post category or blank>" AW_TONE="<tone or blank>" \
       AW_LENGTH="<length or blank>"
```

Interpret stdout + exit code (diagnostics go to stderr):

- **`RUN <run_id>` (exit 0)** — created. Continue below with this `<run_id>`.
- **`DUPLICATE_MATCH <run_id>` (exit 2)** — a run with a matching slug already exists.
  Tell the user and ask: **reuse** it (`init-run.sh --reuse <run_id>`, then resume it as
  in *Resuming a draft*) / **start a new one anyway**
  (`init-run.sh --force-new "<topic>"`) / **cancel**.
- **Any other exit** — report the stderr message; don't fabricate a run.

The run now lives at `<root>/<run_id>/` with a small internal `.article-writer/`
subfolder holding `brief.json`. You'll write the draft there as you go; nothing
user-facing exists yet until you publish.

### 3. Research — scaled to what this piece actually needs

The goal is to understand the topic well enough to write it accurately, not to produce
an academic literature review. Use `WebSearch`/`WebFetch` to:

- get enough context on the topic to write about it competently;
- check the handful of concrete, checkable facts the piece will actually state (names,
  dates, figures, claims) — prefer primary/reputable sources for anything you're
  stating as settled fact; if you can't confirm something, say so plainly in the draft
  (a bracketed note) or ask the human, rather than inventing it;
- skim what else has been written about the topic, if that helps you say something
  sharper or avoid restating the obvious.

Scale effort to the post category if one was given: a personal reflection (musings,
photos, travel, a trip log) usually needs little to no outside research — it's the
human's own account. An opinion/review piece (movies, books, learnings, mba) usually
needs a handful of facts checked, not a deep dive. Anything else, or an explicitly
research-heavy ask, gets a fuller pass. Use judgement; don't over-research a short
personal post just because the tools are available.

### 4. Draft

Write a complete draft that reflects the brief and what you learned. Save it to:

```
<root>/<run_id>/.article-writer/draft.md
```

Then **show the full draft in your response** — not a summary of it — so the human can
react to the actual text.

### 5. Iterate — this is the real quality control

From here, just keep talking. Every message the human sends about this draft is
feedback: apply it (edit `.article-writer/draft.md`), show the result, and keep going.
There is no fixed number of passes and no formal gate to satisfy — you're done with a
round when they say so. If feedback is ambiguous, ask; if it's clear, just make the
change and show it rather than narrating what you're about to do.

### 6. Publish — when they say it's good

Watch for a clear signal that they're happy (e.g. "looks good," "publish it," "that's
the one," "ship it"). When you get one:

1. Decide `title` and a short `excerpt` (1–2 sentences) from the finished draft. Ask
   the human only if you're genuinely unsure. Default `featured: false` and
   `published: false` unless they say otherwise (they can flip `published` in their own
   CMS once they've done a final check).
2. If they have a cover image ready, ask for its path/URL and alt text; otherwise leave
   it — `publish.sh` fills a `TODO-` placeholder they can swap in later. Don't hold up
   publishing to chase down an image.
3. Write these to `<root>/<run_id>/.article-writer/frontmatter.json`:
   ```json
   { "title": "...", "excerpt": "...", "featured": false, "published": false,
     "coverImage": "...", "image": "...", "imageAlt": "..." }
   ```
   (omit any of `coverImage`/`image`/`imageAlt` you don't have — `publish.sh` defaults
   them).
4. Run:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh <run_id> <root>
   ```
   This writes `<root>/<run_id>/scope.md` (a readable record of the brief) and
   `<root>/<run_id>/article.md` (the frontmatter + body, ready for the site) — the only
   two files the human needs to see.
5. Tell the human the folder path, and flag anything you defaulted (placeholder image,
   assumed audience, etc.) so they know what to check before it goes live.

---

## Resuming a draft (`/write-article continue`)

Scan `<root>/*/.article-writer/brief.json` for runs whose `status` is `"drafting"`
(i.e. not yet `"published"`).

- **0 found** — say so; suggest starting one with `/write-article <topic>`.
- **exactly 1** — read its `brief.json` and, if present, `.article-writer/draft.md`.
  Show the human where things stand (the brief, and the current draft if one exists)
  and pick the conversation back up from there — ask what they'd like to change, or
  if there's no draft yet, continue from research/drafting.
- **more than 1** — list them (topic + created date, from each `brief.json`) and ask
  which to resume. Don't guess.
