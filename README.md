# cc-dumb-zone-statusline

A Claude Code statusline that tells you, at a glance, **when your model is about to get dumb**.

Three lines. Color-coded zones. Model-aware thresholds. No npm, no Node, no config — just one bash script and `jq`.

```
📁 norm.ai  🌿 main  🤖 Opus 4.7 (1M context)  v2.x
🧐 smart zone │ 84k/1M (8%) ████░░░░░░░░░░░░░░░░ │ ⏱ 23m
💰 $1.42 (─$3.67/h)  📊 18420 tpm
```

---

## What's the "dumb zone"?

Every frontier LLM has a context window it *advertises* (200k, 1M, …) and a context window it *actually performs well in*. They are not the same number.

As your conversation fills the window, attention dilutes, retrieval over the prompt degrades, and the model starts:

- forgetting instructions you gave 30 turns ago,
- contradicting code it just wrote,
- "fixing" things that weren't broken,
- inventing APIs that don't exist.

The community calls this **the dumb zone**. The [Dictionary of AI Coding](https://github.com/mattpocock/dictionary-of-ai-coding) anchors the threshold around **~100k tokens for frontier models** — but everyone agrees the exact number is model-dependent and debated:

- **Sonnet** starts drifting earlier.
- **Opus** holds longer.
- **Opus with the 1M-context beta** holds longer still, but eventually degrades too.
- **Haiku** is the most fragile.

The practical rule: **don't wait until the official window is "full"**. By the time Claude Code's built-in `%` indicator shows 50%, a Sonnet session may already be drifting. You want to `/clear` (or compact, or hand off) *before* you hit the dumb zone, not after you've spent 20 minutes wondering why the model keeps making the same mistake.

That's what this statusline is for. It shows you three zones with model-aware thresholds:

| Zone           | Meaning                                              | Action                          |
|----------------|------------------------------------------------------|---------------------------------|
| 🧐 smart zone  | Model is sharp, attention is focused                 | Keep going                      |
| 🥱 drifting    | Quality is starting to slip, recall is less reliable | Wrap up the current sub-task    |
| 🤪 dumb zone   | Model is degraded — small bugs, lost instructions    | `/clear` or compact immediately |

Thresholds are tuned per model family. See [Model thresholds](#model-thresholds) below.

---

## What you get

Three lines of statusline:

**Line 1 — context**
- 📁 current directory
- 🌿 git branch (if in a repo)
- 🤖 model display name
- Claude Code version

**Line 2 — the important one**
- Zone label (🧐 / 🥱 / 🤪) with color
- Tokens used / window size, plus % of window
- A 20-segment progress bar:
  - `█` solid = tokens you've used (colored by zone)
  - `▓` dim = safe headroom (same color as current zone)
  - `▒` red = the danger band past the dumb threshold
- ⏱ session elapsed time

**Line 3 — cost & throughput**
- 💰 total session cost in USD
- Hourly burn rate
- 📊 tokens per minute

---

## Install

### Quick install (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.sh | bash
```

This drops `statusline.sh` into `~/.claude/` and prints the snippet you need to add to `~/.claude/settings.json`.

### Manual install

1. Copy `statusline.sh` somewhere — typically `~/.claude/statusline.sh`:

   ```bash
   mkdir -p ~/.claude
   curl -fsSL https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/statusline.sh \
     -o ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Point Claude Code at it. Edit `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh",
       "padding": 0
     }
   }
   ```

3. Restart Claude Code.

### Requirements

- `bash` (Git Bash works on Windows)
- `jq` — `brew install jq` / `apt install jq` / `choco install jq`
- `git` (optional — only used to show the branch on line 1)
- A terminal that renders 256-color ANSI and basic emoji

---

## Model thresholds

The script reads `model.id` and `model.display_name` from Claude Code's statusline input and picks thresholds accordingly:

| Model family               | Window | Drift @ | Dumb @  |
|----------------------------|-------:|--------:|--------:|
| Anything with `[1m]` / `1m`| 1,000k |    200k |    400k |
| Opus                       |   200k |    120k |    160k |
| Haiku                      |   200k |     60k |    100k |
| Other (Sonnet, fallback)   |   200k |     80k |    120k |

These are opinionated defaults — `dictionary-of-ai-coding` anchors the discussion around ~100k for "frontier models" but acknowledges the exact line moves with model and task. Tune to taste; see [Customizing](#customizing).

---

## Customizing

The whole thing is one bash file (~150 lines). Open `~/.claude/statusline.sh` and edit:

- **Thresholds** — search for `T_DRIFT` and `T_DUMB`.
- **Window sizes per model** — same block.
- **Colors** — search for `# ---- colors`. Uses the 256-color ANSI palette.
- **Zone labels / emoji** — search for `ZONE_LABEL`.
- **Progress bar length** — `BAR_LEN=20`.
- **What's on each line** — search for `# ---- render ----` at the bottom.

Drop the modified file back into `~/.claude/statusline.sh`. No build step.

---

## How it works

Claude Code pipes a JSON payload into the `statusLine.command` on every render. The script:

1. Reads stdin, extracts the fields it cares about with `jq`.
2. Sums current context usage = `input + cache_creation + cache_read`.
3. Looks at `model.id` to pick window size + thresholds.
4. Decides the zone, picks a color, builds the gradient bar.
5. Computes burn rate (`cost.total_cost_usd * 3600000 / cost.total_duration_ms`) and tokens-per-minute.
6. Falls back to parsing the transcript for session elapsed if `cost.total_duration_ms` is missing.
7. Prints three `echo -e` lines with ANSI color escapes.

Total cold runtime: typically <50 ms.

---

## Prior art / inspiration

- [`chongdashu/cc-statusline`](https://github.com/chongdashu/cc-statusline) — a more configurable, npm-distributed Claude Code statusline generator. Used as a structural reference; this repo is a single-file, opinionated take focused on the dumb-zone concept.
- The [Dictionary of AI Coding](https://github.com/mattpocock/dictionary-of-ai-coding) entry on the dumb zone.

---

## License

MIT — see [LICENSE](LICENSE).
