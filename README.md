# cc-dumb-zone-statusline

**Know when your Claude Code session is about to get dumb — before you waste an hour wondering why it keeps making the same mistake.**

[![CI](https://github.com/juanpinheiro/cc-dumb-zone-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/juanpinheiro/cc-dumb-zone-statusline/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/juanpinheiro/cc-dumb-zone-statusline)](https://github.com/juanpinheiro/cc-dumb-zone-statusline/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A three-line statusline for [Claude Code](https://github.com/anthropics/claude-code) that color-codes your context usage against **model-aware "dumb zone" thresholds** — so you can `/clear` *before* quality degrades, not after.

```
🧐 smart zone │ 84k/1M (8%) ████░░░░░░░░░░░░░░░░ │ ⏱ 23m
📁 norm.ai  🌿 main  🤖 Opus 4.7 (1M context)  v2.x
💰 $1.42 ($3.67/h)  📊 18,420 tpm
```

One bash script. No Node, no npm, no config. Cross-platform (macOS, Linux, Windows), one-liner install, automatic `settings.json` patch with backup, validated end-to-end before it tells you "Done".

---

## Why this exists

Every frontier LLM has a context window it *advertises* (200k, 1M, …) and a context window it *actually performs well in*. They are not the same number.

As your conversation fills up, attention dilutes, retrieval over the prompt degrades, and the model starts:

- forgetting instructions you gave 30 turns ago,
- contradicting code it just wrote,
- "fixing" things that weren't broken,
- inventing APIs that don't exist.

The community calls this **the dumb zone**. The [Dictionary of AI Coding](https://github.com/mattpocock/dictionary-of-ai-coding) anchors the threshold around **~100k tokens for frontier models** — but the exact line moves with the model:

- **Sonnet** drifts earlier.
- **Opus** holds longer.
- **Opus with the 1M-context beta** holds longer still, but eventually degrades too.
- **Haiku** is the most fragile.

By the time Claude Code's built-in `%` indicator shows 50%, a Sonnet session may already be drifting. **You want to `/clear` (or compact, or hand off) before you hit the dumb zone, not after.** That's the entire job of this statusline.

| Zone           | What it means                                              | What to do                          |
|----------------|------------------------------------------------------------|-------------------------------------|
| 🧐 smart zone  | Model is sharp, attention is focused                       | Keep going                          |
| 🥱 drifting    | Quality is starting to slip, recall is less reliable       | Wrap up the current sub-task        |
| 🤪 dumb zone   | Model is degraded — small bugs, lost instructions          | `/clear` or compact immediately     |

---

## What you see

**Line 1 — the important one**
- Zone label (🧐 / 🥱 / 🤪) with color
- Tokens used / window size, plus % of window
- A 20-segment progress bar:
  - `█` solid = tokens used (colored by zone)
  - `▓` dim = safe headroom (same color as current zone)
  - `▒` red = the danger band past the dumb threshold
- ⏱ session elapsed time

**Line 2 — context**
- 📁 current directory
- 🌿 git branch (if in a repo)
- 🤖 model display name
- Claude Code version

**Line 3 — cost & throughput**
- 💰 total session cost in USD
- Hourly burn rate
- 📊 tokens per minute

---

## Install

Pick your platform. Each one-liner downloads `statusline.sh`, patches `~/.claude/settings.json` automatically (with a `.bak` backup if anything is already there), runs a smoke test, and only reports success once everything works.

### macOS

```bash
# 1. Install jq if you don't already have it
brew install jq

# 2. Install the statusline
curl -fsSL https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.sh | bash

# 3. Restart Claude Code
```

### Linux

```bash
# 1. Install jq (pick the one for your distro)
sudo apt install jq        # Debian / Ubuntu
sudo dnf install jq        # Fedora / RHEL
sudo pacman -S jq          # Arch
sudo apk add jq            # Alpine

# 2. Install the statusline
curl -fsSL https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.sh | bash

# 3. Restart Claude Code
```

### Windows (PowerShell)

This is the recommended path for Windows. The wrapper finds Git Bash or WSL automatically and delegates to it.

```powershell
# 1. Install jq
winget install jqlang.jq

# 2. Install the statusline
irm https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.ps1 | iex

# 3. Restart Claude Code
```

If neither Git Bash nor WSL is installed, the wrapper tells you exactly which one to install and exits cleanly. You can grab Git Bash from [git-scm.com/download/win](https://git-scm.com/download/win) or enable WSL with `wsl --install`.

### Windows (Git Bash)

If you already have Git Bash open, you can use the same one-liner as macOS/Linux:

```bash
winget install jqlang.jq   # (if jq isn't already installed)
curl -fsSL https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.sh | bash
```

> **Note on Windows execution paths:** Claude Code launches the statusline through `cmd.exe`, where `bash` is usually not on the system PATH. The installer probes this automatically and writes an absolute path to `bash.exe` into `settings.json` if needed — so the statusline works regardless of how you launched the install.

---

## Verify it worked

After restarting Claude Code, you should see three lines of statusline at the bottom of the window. If you don't, check:

- `~/.claude/settings.json` contains a `statusLine` block pointing at `~/.claude/statusline.sh`
- `~/.claude/statusline.sh` exists and is executable
- `jq` is on your PATH (`command -v jq`)

The installer runs a smoke test before declaring success, so this should be rare. If you do see issues, see [Troubleshooting](#troubleshooting).

---

## Pinning a version

By default, the installer fetches the latest tagged release. Pin to a specific version with `VERSION=`:

```bash
VERSION=v0.1.0 curl -fsSL https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.sh | bash
```

```powershell
$env:VERSION = "v0.1.0"
irm https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.ps1 | iex
```

---

## Overwriting an existing `statusLine`

If `~/.claude/settings.json` already has a `statusLine` pointing to something else (another statusline, a custom setup), the installer **aborts by default** to protect your config. To overwrite it (a `.bak` backup is always saved):

```bash
FORCE=1 curl -fsSL https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.sh | bash
```

```powershell
$env:FORCE = "1"
irm https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.ps1 | iex
```

Re-running the installer when it already points at our path is **idempotent** — no prompts, no spurious `.bak` files.

---

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.sh | bash -s -- --uninstall
```

This removes the `statusLine` key from `~/.claude/settings.json` (only if it points to our script — a `.bak` is saved), then deletes `~/.claude/statusline.sh` and `~/.claude/lib/`. Foreign `statusLine` entries are left alone with a warning. Safe to run twice.

---

## Manual install

If you'd rather not pipe `curl` into `bash`, you can install by hand:

1. Download the script and supporting libs:
   ```bash
   mkdir -p ~/.claude/lib
   BASE=https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main
   curl -fsSL $BASE/statusline.sh -o ~/.claude/statusline.sh
   for f in parse_hook_input.sh classify_zone.sh render_lines.sh; do
     curl -fsSL $BASE/lib/$f -o ~/.claude/lib/$f
   done
   chmod +x ~/.claude/statusline.sh
   ```

2. Add this to `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh",
       "padding": 0
     }
   }
   ```
   On Windows where `bash` isn't on the `cmd.exe` PATH, use the absolute path to `bash.exe` instead:
   ```json
   "command": "\"C:\\Program Files\\Git\\bin\\bash.exe\" \"C:\\Users\\<you>\\.claude\\statusline.sh\""
   ```

3. Restart Claude Code.

---

## Requirements

- **`bash`** — Git Bash works on Windows
- **`jq`** — hard requirement at both install time and runtime
- **`git`** — optional, only used to show the branch on line 2
- A terminal that renders **256-color ANSI** and basic emoji

---

## Model thresholds

The script reads `model.id` and `model.display_name` from Claude Code's statusline input and picks thresholds accordingly:

| Model family                  | Window | Drift @ | Dumb @  |
|-------------------------------|-------:|--------:|--------:|
| Anything with `[1m]` / `1m`   | 1,000k |    200k |    400k |
| Opus                          |   200k |    120k |    160k |
| Haiku                         |   200k |     60k |    100k |
| Other (Sonnet, fallback)      |   200k |     80k |    120k |

These are opinionated defaults — `dictionary-of-ai-coding` anchors the discussion around ~100k for "frontier models" but acknowledges the exact line moves with model and task. Tune to taste; see [Customizing](#customizing).

---

## Customizing

The runtime is three short bash modules under `~/.claude/lib/`:

| File                          | What to change there                            |
|-------------------------------|-------------------------------------------------|
| `lib/classify_zone.sh`        | Thresholds (`T_DRIFT`, `T_DUMB`), window sizes  |
| `lib/render_lines.sh`         | Colors, emoji, layout, what's on each line      |
| `lib/parse_hook_input.sh`     | Which fields to read from Claude Code's input   |

Edit in place. No build step, no restart of anything other than Claude Code itself.

---

## How it works

Claude Code pipes a JSON payload into the `statusLine.command` on every render. The script:

1. **Parses** the input with a single `jq` invocation (`lib/parse_hook_input.sh`).
2. **Classifies** the current state — given the model ID and total context tokens, picks the right window size and zone thresholds (`lib/classify_zone.sh`).
3. **Renders** three ANSI-colored lines from the resolved facts (`lib/render_lines.sh`).
4. Falls back to parsing the transcript file for session elapsed if `cost.total_duration_ms` is missing.

Total cold runtime: typically **<50 ms**.

The installer (`install.sh`) is similarly modular: it bootstraps a release-aware download, patches `settings.json` atomically with a `.bak`, runs a two-stage validator (smoke test + runtime check), and refuses to declare success until both pass.

---

## Troubleshooting

**The statusline doesn't appear.**
Check `~/.claude/settings.json` actually has a `statusLine` block. If you installed something else first, run with `FORCE=1` to overwrite (a `.bak` is saved).

**`[jq-check] jq not found.`**
Install jq with the command the installer printed for your OS — `brew install jq`, `apt install jq`, `winget install jqlang.jq`, etc.

**`[smoke-test]` or `[runtime-check]` failure.**
The installer validated the statusline before exiting, and something didn't work. Read the error message — it tells you exactly what failed (empty output, missing file, bad path). Most common cause: a path with unusual characters in `$HOME`.

**Windows: statusline runs in install but blank in Claude Code.**
The installer auto-detects this case and writes an absolute path to `bash.exe` into `settings.json`. If you installed before this was added (pre-`v0.1.0`), reinstall — the resolver handles it now.

**Emojis show as `?` or boxes.**
Your terminal needs basic emoji rendering. On Windows, prefer Windows Terminal over the legacy console.

---

## Prior art

- [`chongdashu/cc-statusline`](https://github.com/chongdashu/cc-statusline) — a more configurable, npm-distributed Claude Code statusline generator. Used as a structural reference; this repo is a single-file, opinionated take focused on the dumb-zone concept.
- The [Dictionary of AI Coding](https://github.com/mattpocock/dictionary-of-ai-coding) entry on the dumb zone.

---

## License

MIT — see [LICENSE](LICENSE).
