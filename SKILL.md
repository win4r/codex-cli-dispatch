---
name: codex-cli-dispatch
description: Dispatch coding and development tasks to Codex CLI (codex exec) in background with automatic callback/notification on completion. Use when the user asks to use Codex or Codex CLI for build, fix, review, refactor, or other long-running coding tasks.
---

# Codex CLI Dispatch Skill

Dispatch development tasks to OpenAI's Codex CLI (`codex exec`) with automatic Telegram notification on completion.

## When to Use

- User asks to use Codex / OpenAI Codex to build, fix, or review code
- User explicitly says "use Codex" or "codex cli"
- Tasks that benefit from GPT-5.3-Codex model (OpenAI's coding agent)

## Architecture

```
AGI (main session)
  → exec: dispatch.sh (background)
    → codex exec (headless, sandboxed)
    → on exit: notify via openclaw message send
    → write results to latest.json
```

## Quick Reference

### Dispatch a Task

```bash
bash /home/ubuntu/clawd/skills/codex-cli-dispatch/scripts/dispatch.sh \
  --prompt "Build a REST API with Express.js" \
  --task-name "express-api" \
  --workdir "/home/ubuntu/projects/express-api" \
  --telegram-group "-5006066016" \
  --model "gpt-5.3-codex" \
  --sandbox "workspace-write"
```

### Parameters

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--prompt` | Yes | — | Task instructions for Codex |
| `--task-name` | No | `codex-<timestamp>` | Human-readable task name |
| `--workdir` | No | `/home/ubuntu/clawd` | Working directory |
| `--telegram-group` | No | — | Telegram chat ID for notification |
| `--model` | No | (from config.toml) | Model override |
| `--sandbox` | No | `workspace-write` | `read-only`, `workspace-write`, or `danger-full-access` |
| `--full-auto` | No | true | Skip approvals (sandboxed) |
| `--image` | No | — | Image file(s) to attach |

### Dispatch Pattern (from AGI)

⚠️ **MUST use `nohup` + background** — dispatch.sh blocks until Codex finishes. Short exec timeout will SIGTERM the process.

```bash
# 1. Create project dir
mkdir -p /home/ubuntu/projects/my-project
cd /home/ubuntu/projects/my-project && git init

# 2. Dispatch (ALWAYS use nohup + &)
nohup bash /home/ubuntu/clawd/skills/codex-cli-dispatch/scripts/dispatch.sh \
  --prompt "..." \
  --task-name "my-task" \
  --workdir "/home/ubuntu/projects/my-project" \
  --telegram-group "-5006066016" \
  > /tmp/dispatch-codex.log 2>&1 &
```

Alternative: use `exec` with `background=true` so AGI doesn't block.

## Result Files

| File | Content |
|------|---------|
| `data/codex-results/latest.json` | Last task result (task_name, output, status) |
| `data/codex-results/task-meta.json` | Task metadata (written before run) |
| `data/codex-results/task-output.txt` | Raw Codex output |

## ⚠️ Critical Gotchas

1. **Codex needs a git repo** — Use `--skip-git-repo-check` or `git init` the workdir first
2. **`codex exec` is headless** — No PTY wrapper needed (unlike Claude Code), it exits cleanly
3. **Sandbox modes matter** — `workspace-write` is safe default; `danger-full-access` for system tasks only
4. **Auth** — Codex uses `~/.codex/config.toml` credentials. Run `codex login` if auth fails
5. **Model** — Default is `gpt-5.3-codex`; can override with `--model o3` etc.
6. **Output format** — Use `--json` for JSONL event stream if needed for parsing

## Code Review Mode

Codex has a built-in code review:

```bash
codex exec review --full-auto -C /path/to/repo
```

## ⚠️ Critical Gotchas (continued)

7. **Don't poll and wait!** dispatch.sh is a blocking script. After starting it with `exec background=true`, **do not `process poll`**. The script will automatically send a Telegram notification when finished. Polling just wastes agent turns (lesson learned: a security scan task was polled 20+ times)
8. **Long tasks may be OOM killed** — Codex's `gpt-5.3-codex` reasoning mode is memory-intensive; long-running scan tasks may be killed by the system (SIGKILL). Consider splitting large tasks or reducing reasoning effort

## Debugging

```bash
# Check Codex version
codex --version

# Check auth
cat ~/.codex/config.toml

# View last result
cat /home/ubuntu/clawd/data/codex-results/latest.json | jq .
```
