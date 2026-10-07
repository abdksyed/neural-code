# Presenting NeuralCode

Eighteen commits, each one a working program you can run. `present.sh` moves
between them and tells you what changed.

```bash
bash present.sh list       # every stage, numbered
bash present.sh 7          # jump to commit 7
bash present.sh next       # next stage  (prev also works)
bash present.sh diff       # the patch this stage introduced
bash present.sh files      # what this stage touched
bash present.sh show ui.py # a file as it was at this stage
bash present.sh run        # run the agent as of this stage
bash present.sh main       # back to the tip
```

Switching refuses to clobber uncommitted edits. Add `-f` to throw them away.

You are on a detached HEAD the whole time. That is fine — it is read-only
tourism through history. `bash present.sh main` puts you back.

---

## Before the first session

**1. Credentials.** Stage 9 onwards reads `~/.agents/env`. If that file does
not exist, `uv run neuralcode` dies with `KeyError: 'BASE_URL'` — a confusing
way to lose two minutes in front of a room.

```bash
bash present.sh setup      # copies .agents/.env to ~/.agents/env
```

Stages 1-8 read `BASE_URL` / `API_KEY` straight from the environment instead;
`run` hands them `--env-file .agents/.env` so this is handled either way.

**2. Start from a clean tree.** `git status` must be empty. Uncommitted edits
block every switch, and the guard will stop you mid-presentation.

**3. Pre-warm uv.** `uv.lock` changes across the stages, so the first `uv run`
at a given stage may hit the network to re-resolve. Walk the whole history once
before the talk with `bash present.sh run` at each stop, so nothing downloads
while people are watching.

**4. Stage 4 needs a skill.** The repo ships `.agents/skills/` empty. Before
that stage, create one:

```bash
mkdir -p .agents/skills/commit-style
cat > .agents/skills/commit-style/SKILL.md <<'EOF'
---
name: commit-style
description: How to write commit messages in this repo.
---

Subject line in the imperative, under 60 characters, no trailing period.
One blank line, then a short body explaining why, not what.
EOF
```

---

## The arc

Say this at the top, and come back to it: **a coding agent is a loop around a
model that can call tools.** Stages 1-5 build that loop. Stages 6-18 are what
you need once it is load-bearing: context that stays fresh, actions you can
trust, and a transcript that does not outgrow its window.

Stages 1-8 live at the repo root; stage 9 moves everything into `neuralcode/`.
The entry point follows: `uv run llm.py` → `uv run agent.py` → `uv run
neuralcode`. `bash present.sh run` picks the right one.

---

### 1 — minimal chat completion round-trip

```bash
bash present.sh 1
```

`llm.py`, 38 lines. One system prompt, one user message, print the answer and
the usage dict.

**Type:** `explain what a coding agent is in two sentences`

Land it: *Four token counts printed underneath, and nothing else. No memory, no
tools, no loop — it reads one line and forgets you.*

### 2 — chat with a simple bash tool

```bash
bash present.sh 2
```

The bash tool is hardcoded into `llm.py`: one schema, one `subprocess.run`.

**Type:** `list the files in this directory`

Land it: *The model ran nothing. It asked us to run something, and we printed
the answer to our own screen. The result never goes back to it.*

### 3 — generic tools

```bash
bash present.sh 3
```

`tools.py` appears. The single hardcoded tool becomes `TOOLS` (name → callable)
plus `TOOL_SCHEMAS` (what the model is offered).

Land it: *Same behaviour, new shape. bash is now one entry in a dict, which is
why every tool after this one is 20 lines instead of a rewrite.*

### 4 — add a read_file tool

```bash
bash present.sh 4
```

**Type:** `read pyproject.toml and tell me what it does`

Land it: *Two tools. The model chooses between them by itself — nobody wrote an
if-statement for that. We still run one and stop.*

### 5 — the agent loop

```bash
bash present.sh 5
```

`agent.py` is born. The `while` loop: call the model, run whatever tool calls it
returns, append the results, call again. Stop when it returns none.

**Type:** `read pyproject.toml, then create NOTES.md listing its dependencies`

Land it: *That is the whole trick. Everything else in this repo is polish on
these twenty lines. If your students remember one commit, make it this one.*

### 6 — better UI please

```bash
bash present.sh 6
```

`ui.py`, +135 lines. Markdown rendering, a spinner, themed tool calls.

**Type:** a prompt that produces a list, so the markdown shows.

Land it: *Diff `agent.py` — the loop is untouched. Presentation moved into its
own module, and the logic never learned about colour.*

### 7 — skill discovery and reading

```bash
bash present.sh 7
```

`skills.py` scans `.agents/skills/*/SKILL.md`, parses the YAML frontmatter, and
injects only name + description into the prompt. The body is a tool call away.

**Type:** `what skills do you have?` then `use the commit-style skill and
suggest a commit message for this repo`

Land it: *The model knows every skill exists without any of them costing
context. That is progressive disclosure, and it is why the skill body can be
2,000 words.*

### 8 — file editing tools

```bash
bash present.sh 8
```

`write_file`, and `str_replace` — which refuses unless `old_str` matches
exactly once.

**Type:** `create hello.py that prints the current date, then add a docstring`

Land it: *That refusal is the feature. It forces the model to include enough
surrounding context to prove it is editing the right place, instead of
rewarding a lucky guess.*

### 9 — env block late injection

```bash
bash present.sh 9
```

`context.py`. Time, date, git branch — appended as the **last** message before
each request rather than baked into the system prompt.

**Type:** `what time is it, and what branch are we on?`

Land it: *Appending at the end means everything in front of it stays
byte-identical turn to turn, and that is exactly what keeps the provider's
prompt cache warm. A changing system prompt would invalidate the whole prefix
every time you ask what time it is.*

### 10 — file freshness reminders

```bash
bash present.sh 10
```

Every file git reports as changed gets hashed each turn. If a hash moved between
turns, the model is told to read it again before editing.

**Demo:** open a second terminal, edit the file the agent just wrote, then ask
it a follow-up question about that file.

Land it: *It cannot see your editor. Hashing what git already tracks is how it
notices you changed the file while it was thinking.*

### 11 — sessions, slash commands, and rewind

```bash
bash present.sh 11
```

Append-only JSONL, one file per chat. `rewind` writes a `rewind_to` entry rather
than truncating the file.

**Type:** `/rewind` then `/sessions`

Land it: *Rewinds are recorded, not applied. The file stays a complete log of
the session including every time you changed your mind. That is what makes
`/sessions` able to replay it.*

### 12 — installable neuralcode command

```bash
bash present.sh 12
```

Everything moves into `neuralcode/`, imports go relative, and `pyproject.toml`
gains `[project.scripts]`. `config.py` appears, reading `~/.agents/env`.

**Type:** `uv run neuralcode`

Land it: *No behaviour change at all — pure packaging. Worth showing that a
refactor commit can be boring on purpose.*

### 13 — todo list

```bash
bash present.sh 13
```

`todos.py`. The plan lives in a module-level list, not in the transcript, and is
re-injected every turn inside `<todos>` tags.

**Type:** something with four or five steps, e.g. `add a --version flag to
cli.py, update the README, and add a test`

Land it: *Outside the transcript means compaction cannot eat the plan, and the
model cannot quietly forget step four. It also gives the spinner something
honest to say.*

### 14 — tool permissions

```bash
bash present.sh 14
```

`permissions.py`. Every tool call is rated allow / ask / deny before it runs.
Rules are fnmatch patterns; the **last** match wins.

**Type:** `delete the build directory` (denied outright), then `git commit the
current changes` (stops and asks you)

Land it: *Two separate questions. The sandbox decides what is possible; this
decides what is worth interrupting a human for. Read-only commands run silently
so the noise is reserved for things that can actually hurt.*

**If you have time:** show `split_command`. A naive split on `;` and `|` also
cuts inside quotes, so `rg "cap|max"` would fragment into gibberish and fall
through to "ask". It tracks quoting to avoid that.

### 15 — OS sandbox for bash

```bash
bash present.sh 15
```

`sandbox.py`. macOS gets `sandbox-exec` with a seatbelt profile; Linux gets
bubblewrap. Read anything, write only inside the project, no network.

**Type:** `using bash, write "hi" to /tmp/escape.txt`

Land it: *That passed permissions — `echo` is allow-listed, and nothing about it
looks dangerous. The kernel refused it anyway, and the file does not exist. That
is the difference: `permissions.py` is a Python file the agent could rewrite.
The seatbelt profile is not reachable from inside the process at all.*

**Do not demo this with curl.** `curl *` is already a deny rule in
`permissions.py`, so it never reaches the sandbox and the point is lost —
students see a blocked command and cannot tell which layer blocked it.

### 16 — readable todos and a real input line

```bash
bash present.sh 16
```

`prompt.py` replaces `input()`. Todos get proper status marks.

**Demo:** paste a message longer than the terminal is wide, then use
option-arrow to jump words and edit the middle of it.

Land it: *`input()` cannot edit a line that has wrapped past the screen width,
because the terminal owns the wrapping and readline cannot see it. prompt_toolkit
redraws the line itself, so editing keeps working at any length.*

### 17 — compaction and context overflow

```bash
bash present.sh 17
```

`history.py` and `compact.py`. Three mechanisms, cheapest first: **cap** a fresh
tool result and spill the rest to a temp file; **strip** results down to stubs
once the turn is over; **drop** whole results if a single request still will not
fit. Compaction is the expensive last resort.

**Type:** run something that produces a huge tool result, then `/compact`.

Land it: *Note where each edit lands. Cap and strip both write at the tail, so
the cached prefix in front survives. Compaction is the only thing in the repo
that destroys information permanently, which is why it is the only mechanism
that gets its own agent.*

### 18 — exploration subagents

```bash
bash present.sh 18
```

`subagent.py`. A second agent with its own context window, asked to go find
something and report back just the answer.

**Type:** `how does the permission layer decide what to block?`

Land it: *It explored with its own context and handed back a paragraph. That
whole search never entered this conversation. And note subagents go through the
same `execute()` — a subagent is not a way around the permission rules.*

---

## If something goes wrong

**"Refusing to switch over them"** — something is uncommitted. `git stash` if
you want it, `bash present.sh <n> -f` if you do not.

**"stage 9+ reads ~/.agents/env"** — run `bash present.sh setup`.

**Model returns an error mid-demo** — stage 1-8 have no error handling on the
API call, on purpose. That is honestly a good moment: point out that the older
stages die on a rate limit and stage 17 is where that gets addressed.

**Lost your place** — `bash present.sh list` and match the subject line.

## Afterwards

```bash
bash present.sh main
git status          # should be clean
```

Then `git stash pop` if you stashed anything at the start.
