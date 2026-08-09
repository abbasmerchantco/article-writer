# Scope — please complete before resuming

This form is the human half of the Step 1 handshake. The agent will not begin
writing until it has your answers. Fill in the blank areas below, save the file,
then run `/write-article continue`.

Two fields are **MANDATORY**. The rest are optional — if you leave an optional
field blank, the agent will *propose* a value and show it to you (it never fills a
mandatory field on your behalf).

---

## Subject (read-only context)

> This is the raw subject you typed after `/write-article`, preserved verbatim in
> the trigger log. It is shown here only for reference — you do **not** need to
> re-enter it.

**Subject:** `<raw subject is recorded in input/<run>/trigger.json>`

---

## MANDATORY FIELDS — leaving either blank STOPS the run

> If either of the two fields below is blank when you run `continue`, the run
> hard-stops, tells you exactly which field is missing, and stays at
> `awaiting-scope`. The agent will **never** guess these.

### 🔴 MANDATORY — Audience / target reader
_Who is this for, and what do they already know? Name the reader and their assumed
knowledge level (e.g. "practising clinicians, comfortable with trial statistics" or
"curious non-specialists with no economics background"). This reshapes vocabulary,
depth, and what can be assumed vs. explained._

**Your answer:**
```
(write here)
```

### 🔴 MANDATORY — Purpose / desired takeaway
_What should the reader believe, understand, or be able to do after reading? One or
two sentences. This is the destination the whole piece is steered toward._

**Your answer:**
```
(write here)
```

---

## OPTIONAL FIELDS — blank is fine; the agent will propose a value

> For any field you leave blank, the agent proposes a value during reconciliation
> and surfaces it for your awareness. Fill one in only if you already have a
> preference you want to lock.

### Angle / stance
_A preferred lens or argumentative position, if you have one (e.g. "argue mandates
are mostly about control, not productivity"). Leave blank to let the agent derive
one from the research._

**Your answer:**
```
(optional — write here or leave blank)
```

### Length / format target
_Rough size and shape (e.g. "~1,200-word explainer", "short op-ed", "long-form
feature with subheads")._

**Your answer:**
```
(optional — write here or leave blank)
```

### Tone / voice
_Register and formality (e.g. "dry and precise", "warm and conversational",
"neutral, plain")._

**Your answer:**
```
(optional — write here or leave blank)
```

### Must-include points
_Anything that has to appear — a specific study, argument, example, or caveat._

**Your answer:**
```
(optional — write here or leave blank)
```

### Must-avoid points / constraints
_Anything off-limits — claims not to make, framings to avoid, topics to steer clear
of, hard don'ts._

**Your answer:**
```
(optional — write here or leave blank)
```

### Source-policy overrides
_Deviations from the default source policy (§6): a whitelist/blacklist tweak, a
different quality threshold, a source you specifically do or don't want used. Leave
blank to use the shipped defaults._

**Your answer:**
```
(optional — write here or leave blank)
```

### Referencing / citation style
_Which referencing scheme should the article use for in-text citations and its
bibliography? Pick one (leave blank and Step 1 will ask you explicitly):_
_**apa** · **mla** · **chicago-author-date** · **chicago-notes** · **harvard** ·
**ieee** · **vancouver** · **none** (no referencing)._

**Your answer:**
```
(optional — write here or leave blank; Step 1 will prompt if blank)
```

---

_When you are done: save this file, then run `/write-article continue`._
