---
name: write-article
description: >-
  Two-phase entry point for the article-writer 8-step workflow. Phase A
  (`/write-article <subject>`) sets up an isolated run and drops a scope
  template for the human to complete — it does NOT begin writing. Phase B
  (`/write-article continue`) resumes a run from its current step and executes
  the workflow. Use to commission a new article or to resume an in-progress one.
argument-hint: "<subject> | continue"
disable-model-invocation: true
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# `/write-article` — two-phase run entry & routing

You are the **entry point and router** for the `article-writer` workflow. Your
only jobs are: set up a run (Phase A), or select and resume a run and hand off
to the right skill (Phase B). **You do not perform any of the 8 workflow
steps yourself** — the step skills and the orchestrator do that.

Runs live under a **run root**, in three sibling folders: `input/`, `interim/`,
`output/`. Each run has an identically-named subfolder in all three:
`input/<run_id>/`, `interim/<run_id>/`, `output/<run_id>/`. By default the run
root is the **current working directory** (where Claude was launched) — but it
is overridable (see below), because that directory can be an ephemeral
session/sandbox path that disappears, which loses runs.

Deterministic scripts under `${CLAUDE_PLUGIN_ROOT}/scripts/` own folder
allocation, the state file, and gate counters. Never hand-edit `state.json`
counters — the scripts are the sole mutator.

## Resolving the run root (requirements §2.4 `output_root`)

Do this **once, first**, before Phase A or Phase B — every path in this file
and in the skills it hands off to is relative to the resolved root, not
blindly to wherever Claude happens to be running from.

1. Read the plugin's `output_root` control (from `userConfig`, or however
   your run's control overrides are supplied). If it is set (non-blank),
   that is the **requested root** — an absolute path such as a OneDrive-
   synced folder. If it is blank/unset, the root is the current working
   directory (original behavior; nothing else below changes).
2. Export it so every script invocation resolves the same way:
   ```
   export AW_OUTPUT_ROOT="<the requested root, or empty if unset>"
   ```
   `init-run.sh` treats an empty value as "use cwd," creates the directory if
   it does not exist, and always resolves it to an **absolute** path — which
   it then records in `trigger.json`/`state.json` as `paths.root`. From the
   moment a run exists, `paths.root` in that run's own `state.json` is the
   authoritative root for that run — prefer it over re-deriving
   `AW_OUTPUT_ROOT` yourself, because a run keeps the root it was *created*
   with even if `output_root` is changed later or a future session's cwd
   differs.
3. Wherever this file (or `orchestrator`, or any `step-N` skill) says
   `input/<run_id>/...`, `interim/<run_id>/...`, or `output/<run_id>/...`,
   read that as `<root>/input/<run_id>/...` etc.
4. **Backward compatibility:** a run created before this control existed (or
   in a session where it was left unset) lives directly under the plain
   current working directory with no `paths.root` field. When scanning for
   runs (Phase B, resumability) or resolving `--reuse`, and `AW_OUTPUT_ROOT`
   differs from the plain cwd, check **both** locations rather than assuming
   every run lives under the new root.

The argument you were invoked with is:

```
$ARGUMENTS
```

**Dispatch on the argument:**
- If the argument is exactly `continue` (case-insensitive, no other words) →
  run **Phase B** below.
- Otherwise, treat the **entire argument string, verbatim** as the article
  subject → run **Phase A** below.
- If the argument is empty → tell the user the two forms
  (`/write-article <subject>` to start, `/write-article continue` to resume)
  and stop.

---

## Phase A — `/write-article <subject>` (SETUP ONLY — MUST NOT begin writing)

> Acceptance criterion: Phase A **creates folders and a scope template but does
> not begin writing.** Only Phase B executes the workflow. Do **not** run Step 1
> reconciliation, research, drafting, or any step work here.

1. **Capture the commission.** Record the raw subject **verbatim**, exactly as
   typed after the command (do not trim, reword, or normalize it — the slug is
   derived by the script; the raw subject is preserved), plus the current
   timestamp.

2. **Allocate the run** by invoking the init script (with `AW_OUTPUT_ROOT`
   already exported per *Resolving the run root* above — the script reads it
   from the environment). This is the only thing that creates folders, writes
   the trigger log, and initializes state:

   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/init-run.sh "<raw subject>"
   ```

   Interpret its **stdout + exit code** (diagnostics go to stderr):

   - **`RUN <run_id>` (exit 0)** — the run was created. Proceed to step 3 with
     this `<run_id>`.

   - **`DUPLICATE_MATCH <run_id>` (exit 2)** — a run with a matching **slug**
     already exists (a trivially-reworded subject still collides). **STOP and
     ask the user** (show the matched `<run_id>`), offering exactly three
     choices:
       - **Reuse** the existing run → re-invoke
         `${CLAUDE_PLUGIN_ROOT}/scripts/init-run.sh --reuse <run_id>` and use the
         returned run.
       - **Create a new run** anyway → re-invoke
         `${CLAUDE_PLUGIN_ROOT}/scripts/init-run.sh --force-new "<raw subject>"`
         and use the returned `RUN <run_id>`.
       - **Cancel** → abort; create nothing.
     Do not guess the user's intent — a slug collision must halt and prompt.

   - **Any other exit (exit 1 / usage error)** — report the stderr message and
     stop; do not fabricate a run.

3. **Drop the blank scope template.** Once a run exists, write the blank scope
   template to:

   ```
   <root>/input/<run_id>/scope-template.md
   ```

   where `<root>` is this run's `paths.root` from the `state.json` that
   `init-run.sh` just wrote (§ *Resolving the run root*). (The template's
   content is authored by the `input-scope-template` task; your job in Phase A
   is only to ensure a blank copy lands at that exact path so the human has a
   form to complete.)

4. **Confirm state.** `init-run.sh` has already initialized
   `<root>/interim/<run_id>/state.json` with `status: awaiting-scope`. Verify
   that is the case; do not advance the status.

5. **STOP and hand back to the human.** Tell them **exactly**:
   - the run id,
   - the **full, absolute path** of the scope template they must complete
     (`<root>/input/<run_id>/scope-template.md` — spell out the real `<root>`
     value, not the placeholder, so they know exactly which folder to open;
     this matters more than before now that `<root>` may not be their
     terminal's cwd), noting the two **mandatory** fields (audience / target
     reader, and purpose / desired takeaway) that will hard-stop resumption if
     left blank,
   - that they resume with **`/write-article continue`** once it is filled in.

   Do **not** proceed to Step 1 or any writing. Phase A ends here.

---

## Phase B — `/write-article continue` (general resume verb — NOT scope-specific)

> Acceptance criteria: `continue` resumes from the run's **current step**
> (general resume — could be `awaiting-scope`, or mid-Step-5, etc.); it **asks
> which run** when more than one is resumable; and a **blank mandatory scope
> field hard-stops** it, leaving the run at `awaiting-scope`.

1. **Find resumable runs.** Scan `<root>/interim/*/state.json` (per §
   *Resolving the run root* — `<root>` from the resolved `output_root`
   control). If `<root>` differs from the plain current working directory,
   **also** scan `interim/*/state.json` there, so runs created before this
   control was set (or in a session without it) still surface — a run found
   this way has its own `paths.root` recorded inside it, which is what you
   use from then on, not the currently-resolved `<root>`. A run is
   **resumable** when its `status` is anything from `awaiting-scope` through
   an in-progress step (`step-1` … `step-8`) — i.e. **anything except
   `published`**.
   - **0 resumable** → tell the user there are no in-progress runs, and suggest
     starting one with `/write-article <subject>`. Stop.
   - **exactly 1 resumable** → select it and continue.
   - **more than 1 resumable** → **list them** (for each: `run_id`, `status`,
     and `raw_subject` from state) and **ask the user which to resume.** Do not
     pick one silently.

2. **Resume from the current step.** Read the selected run's `state.json`.
   Resume **from whatever step `status` records** — this is a general resume,
   not a scope-only continuation.

3. **If `status` is `awaiting-scope`:** read the completed
   `<root>/input/<run_id>/scope-template.md`, where `<root>` is this run's own
   `state.json.paths.root` (fall back to the plain current working directory
   if that field is absent — a pre-`output_root` run).
   - **MANDATORY-FIELD HARD-STOP:** if **either** mandatory field is blank —
     **audience / target reader**, or **purpose / desired takeaway** — do **not**
     proceed, and do **not** guess or fill them in. List **exactly which**
     mandatory field(s) are missing, tell the user to complete them in the
     template, and **STOP**, leaving the run at `awaiting-scope`.
   - If both mandatory fields are present, hand off to the **`step-1-scope`**
     skill (via the orchestrator) to run the Step 1 human-agent reconciliation.
     Do not perform the reconciliation yourself.

4. **From Step 1 onward, defer to the orchestrator.** For any run already past
   scope (or once the scope hard-stop clears), hand control to the
   **`orchestrator`** skill, which runs Steps 1–8, manages `state.json`, and
   enforces the gates via the deterministic scripts. Your responsibility is
   **entry and routing only** — you do not execute step logic, mutate gate
   counters, or decide loop continuation. You do not need to pass the root
   separately: the orchestrator re-reads `state.json` on entry (as always),
   and this run's own `paths.root` is already in it.
