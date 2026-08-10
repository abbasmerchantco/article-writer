# Article Writer

A Claude Code plugin for writing your own blog posts. You give it a topic — plus
whatever of audience, intention, angle, and points to cover you already have in mind —
and it researches the topic, checks the facts it's going to state, drafts it, and then
iterates with you conversationally until you're happy. When you say it's good, it
writes the final, formatted article into one folder, ready to drop into your site.

There are no gates, caps, or adversarial-review loops. An earlier version of this
plugin had all of that (a deterministic 8-step pipeline with per-gate caps and an
independent fact-checking subagent) — it was built for deeply-reported, argumentative
journalism, and it made writing a movie review or a trip log take 45+ minutes and cost
six figures of tokens for no real benefit. It was removed. See `CHANGELOG.md` if you're
curious what used to be here.

## Usage

```
/write-article <topic, plus any of: audience, intention, angle, points to cover>
/write-article continue     # resume a draft you didn't finish
```

Say as much or as little as you want. At minimum you need a topic; if you don't give an
audience or intention, it'll ask once, briefly, and otherwise just proceed with sensible
defaults and tell you what it assumed. From there:

1. **Research.** It reads up on the topic and checks the specific facts the piece is
   going to state — scaled to what the piece actually needs. A personal reflection
   (a musing, a trip log, a photo caption) needs little or none of this; a movie/book
   take needs a couple of facts checked; anything more involved gets a fuller pass.
2. **Draft.** It writes a complete draft and shows you the whole thing.
3. **Iterate.** You react to it in plain conversation — "cut the second paragraph,"
   "make the ending less neat," whatever — and it revises and shows you the result.
   Keep going as long as you want. This conversation *is* the quality control; there's
   no separate review step you have to pass.
4. **Publish.** When you say it's good, it writes:
   - `scope.md` — a short, readable record of the brief (topic, audience, intention,
     angle, points to cover).
   - `article.md` — the final article, with YAML frontmatter matching your site's
     format (`title`, `category`, `date`, `excerpt`, `readTime`, `featured`,
     `coverImage`, `published`, `layout`, `imageAlt`, `image`) and the body underneath.

   Both land in one folder: `<output_root>/<YYYYMMDD-NNNNN-slug>/`. `published` always
   defaults to `false` and image fields default to a `TODO-` placeholder if you didn't
   have one ready — check both before it goes live.

## Components

```
article-writer/
├── .claude-plugin/plugin.json   # manifest: output_root + a few soft defaults
├── commands/write-article.md    # the whole flow: brief -> research -> draft -> iterate -> publish
├── scripts/
│   ├── init-run.sh              # allocate one run folder, write brief.json
│   └── publish.sh                # assemble scope.md + article.md (frontmatter + body)
└── docs/requirements.md          # what this plugin does and doesn't do
```

Everything else you may see in this repo (`skills/`, `agents/`, `templates/`,
`config/`, several other `scripts/*.sh`) is left over from the removed gated pipeline —
each of those files now just prints a deprecation notice or says so in a comment, and
none of them are called by anything. They're safe to delete; see `CHANGELOG.md` for the
full list. They're still here only because deleting files wasn't possible in the
session that did this rewrite.

## Controls

`output_root` — absolute, persistent folder where every run lives (default: none, uses
the current working directory). Set this to a synced folder (OneDrive, Dropbox, etc.) so
runs survive a temporary/sandboxed session.

`audience` / `tone` / `length` / `post_category` — soft fallbacks used only when you
don't specify them for a given run. None of these are enforced; they're just defaults
the agent uses unless you say otherwise.

## Installation

**Requirements:** Claude Code, `bash`, `python3` (or `python`/`py -3` — the scripts
fall back automatically).

From GitHub (the canonical marketplace location):

```
/plugin marketplace add abbasmerchantco/article-writer
/plugin install article-writer@article-writer
```

To pick up new commits after the initial install: `/plugin marketplace update
article-writer` then `/reload-plugins` (or restart Claude Code).

For local development: clone the repo, run `/plugin`, add the folder as a local
marketplace source, and enable `article-writer`.

## Honest limits

This is a writing assistant, not a fact-checking service. It checks the concrete claims
a piece states where it reasonably can, using web search, but there's no independent
adversarial review step anymore — the human reading the draft and giving feedback is
the check. For a personal reflection with nothing externally checkable in it, it won't
do external research at all, and it'll say so rather than imply verification it didn't
perform.

## License

MIT — see [LICENSE](LICENSE).
