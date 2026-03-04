# Codex CLI Dispatch

An [OpenClaw](https://github.com/openclaw/openclaw) skill that dispatches coding tasks to [OpenAI Codex CLI](https://github.com/openai/codex) (`codex exec`) in background mode, with **automatic Telegram notification** on completion.

> No polling. No blocking. Fire and forget — get notified when it's done.

## Features

- 🚀 **Background execution** — dispatches Codex CLI as a background process, never blocks your agent
- 📲 **Auto Telegram notification** — sends task result summary to a Telegram chat when done
- 🔄 **Agent wake hook** — wakes your OpenClaw agent on completion for follow-up actions
- 🛡️ **Sandbox modes** — supports `read-only`, `workspace-write`, and `danger-full-access`
- 📊 **Result tracking** — writes structured JSON results for downstream processing
- 🖼️ **Image support** — attach images to the Codex prompt for visual context

## Prerequisites

- [OpenClaw](https://github.com/openclaw/openclaw) installed and running
- [Codex CLI](https://github.com/openai/codex) installed (`npm i -g @openai/codex`)
- Codex authenticated (`codex login` or `~/.codex/config.toml`)
- (Optional) Telegram bot configured in OpenClaw for notifications

## Installation

### As an OpenClaw Skill

Copy the skill folder into your OpenClaw workspace:

```bash
cp -r codex-cli-dispatch /path/to/your/clawd/skills/
```

OpenClaw will auto-discover the skill from `SKILL.md`.

### Standalone

You can also use `scripts/dispatch.sh` independently:

```bash
git clone https://github.com/win4r/codex-cli-dispatch.git
cd codex-cli-dispatch
chmod +x scripts/dispatch.sh
```

## Usage

### Basic Dispatch

```bash
bash scripts/dispatch.sh \
  --prompt "Build a REST API with Express.js and TypeScript" \
  --task-name "express-api" \
  --workdir "/path/to/project"
```

### Full Options

```bash
bash scripts/dispatch.sh \
  --prompt "Refactor the auth module to use JWT" \
  --task-name "auth-refactor" \
  --workdir "/home/user/projects/my-app" \
  --telegram-group "-1001234567890" \
  --model "gpt-5.3-codex" \
  --sandbox "workspace-write" \
  --full-auto true \
  --image "./screenshot.png"
```

### Parameters

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--prompt` | ✅ | — | Task instructions for Codex |
| `--task-name` | ❌ | `codex-<timestamp>` | Human-readable task name |
| `--workdir` | ❌ | Current directory | Working directory for the task |
| `--telegram-group` | ❌ | — | Telegram chat ID for completion notification |
| `--model` | ❌ | From Codex config | Model override (e.g., `gpt-5.3-codex`, `o3`) |
| `--sandbox` | ❌ | `workspace-write` | Sandbox mode: `read-only`, `workspace-write`, `danger-full-access` |
| `--full-auto` | ❌ | `true` | Skip interactive approvals |
| `--image` | ❌ | — | Attach image(s) to the prompt (repeatable) |
| `--skip-git-check` | ❌ | `false` | Skip git repo initialization |
| `--agent-id` | ❌ | — | OpenClaw agent ID to wake on completion |

### From an OpenClaw Agent

When used as an OpenClaw skill, the agent dispatches tasks like this:

```bash
# Always use nohup + & to avoid blocking the agent
nohup bash /path/to/skills/codex-cli-dispatch/scripts/dispatch.sh \
  --prompt "Build a TODO app with React" \
  --task-name "todo-app" \
  --workdir "/home/user/projects/todo-app" \
  --telegram-group "-1001234567890" \
  > /tmp/dispatch-codex.log 2>&1 &
```

## How It Works

```
OpenClaw Agent
  ├── exec: dispatch.sh (background, non-blocking)
  │     ├── writes task metadata (task-meta.json)
  │     ├── runs: codex exec --full-auto --sandbox workspace-write "prompt"
  │     ├── captures output (task-output.txt)
  │     ├── writes result (latest.json)
  │     ├── sends Telegram notification via openclaw message send
  │     └── wakes agent via /hooks/wake endpoint
  └── (agent continues handling other requests)
```

## Output Files

Results are written to `data/codex-results/`:

| File | Description |
|------|-------------|
| `latest.json` | Last task result (task_name, output, status, exit_code) |
| `task-meta.json` | Task metadata (prompt, workdir, timing) |
| `task-output.txt` | Raw Codex CLI output |

### `latest.json` Example

```json
{
  "task_name": "express-api",
  "timestamp": "2026-03-04T12:34:56+00:00",
  "output": "... last 4000 chars of codex output ...",
  "telegram_group": "-1001234567890",
  "exit_code": 0,
  "status": "done"
}
```

## Tips & Gotchas

1. **Codex needs a git repo** — The script auto-initializes one if missing. Use `--skip-git-check` to skip.
2. **Don't poll the background process** — The script sends notifications automatically. Polling wastes resources.
3. **Sandbox matters** — Use `workspace-write` (default) for safety. Only use `danger-full-access` for system-level tasks.
4. **Long tasks may OOM** — Codex's reasoning mode is memory-intensive. Consider splitting large tasks.
5. **Git init isolation** — The script creates git repos at `--workdir` level only, never nested.

## License

MIT

## Related

- [OpenClaw](https://github.com/openclaw/openclaw) — The AI agent framework this skill is built for
- [Codex CLI](https://github.com/openai/codex) — OpenAI's terminal coding agent
- [ClawhHub](https://clawhub.com) — Discover more OpenClaw skills
