# Codex CLI Dispatch

一个 [OpenClaw](https://github.com/openclaw/openclaw) 技能插件，用于将编码任务分发给 [OpenAI Codex CLI](https://github.com/openai/codex)（`codex exec`）后台执行，任务完成后**自动发送 Telegram 通知**。

> 无需轮询，无需阻塞。发射即忘 —— 完成时自动通知你。

## 功能特性

- 🚀 **后台执行** — 将 Codex CLI 作为后台进程运行，不阻塞 AI Agent
- 📲 **自动 Telegram 通知** — 任务完成时自动发送结果摘要到指定 Telegram 群组
- 🔄 **Agent 唤醒钩子** — 完成后通过 webhook 唤醒 OpenClaw Agent 进行后续处理
- 🛡️ **沙盒模式** — 支持 `read-only`（只读）、`workspace-write`（工作区写入）、`danger-full-access`（完全访问）
- 📊 **结果追踪** — 输出结构化 JSON 结果，方便下游处理
- 🖼️ **图片支持** — 可附加图片到 Codex 提示词，提供视觉上下文

## 前置要求

- 已安装并运行 [OpenClaw](https://github.com/openclaw/openclaw)
- 已安装 [Codex CLI](https://github.com/openai/codex)（`npm i -g @openai/codex`）
- Codex 已完成认证（运行 `codex login` 或配置 `~/.codex/config.toml`）
- （可选）OpenClaw 中已配置 Telegram Bot，用于接收通知

## 安装

### 作为 OpenClaw 技能安装

将技能文件夹复制到你的 OpenClaw 工作区：

```bash
cp -r codex-cli-dispatch /path/to/your/clawd/skills/
```

OpenClaw 会自动从 `SKILL.md` 发现该技能。

### 独立使用

你也可以单独使用 `scripts/dispatch.sh`：

```bash
git clone https://github.com/win4r/codex-cli-dispatch.git
cd codex-cli-dispatch
chmod +x scripts/dispatch.sh
```

## 配置

脚本会自动检测路径，你也可以通过环境变量覆盖：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPENCLAW_WORKSPACE` | `scripts/` 的上级目录 | OpenClaw 工作区根目录（如 `~/clawd`） |
| `OPENCLAW_BIN` | 从 `$PATH` 自动检测 | `openclaw` 可执行文件路径 |
| `CODEX_BIN` | 从 `$PATH` 自动检测 | `codex` 可执行文件路径 |
| `OPENCLAW_CONFIG` | `~/.openclaw/openclaw.json` | OpenClaw 配置文件（用于唤醒钩子） |

**示例** — 如果你的工作区在 `/opt/openclaw`：

```bash
export OPENCLAW_WORKSPACE=/opt/openclaw
bash scripts/dispatch.sh --prompt "修复登录 bug" --task-name "login-fix"
```

> **注意：** 结果文件（`latest.json`、`task-meta.json`、`task-output.txt`）会写入 `$OPENCLAW_WORKSPACE/data/codex-results/` 目录，请确保该目录可写。

## 使用方法

### 基本用法

```bash
bash scripts/dispatch.sh \
  --prompt "用 Express.js 和 TypeScript 构建一个 REST API" \
  --task-name "express-api" \
  --workdir "/path/to/project"
```

### 完整参数示例

```bash
bash scripts/dispatch.sh \
  --prompt "将认证模块重构为 JWT 方案" \
  --task-name "auth-refactor" \
  --workdir "/home/user/projects/my-app" \
  --telegram-group "-1001234567890" \
  --model "gpt-5.3-codex" \
  --sandbox "workspace-write" \
  --full-auto true \
  --image "./screenshot.png"
```

### 参数说明

| 参数 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `--prompt` | ✅ | — | Codex 任务指令 |
| `--task-name` | ❌ | `codex-<时间戳>` | 任务名称（便于识别） |
| `--workdir` | ❌ | 当前目录 | 任务工作目录 |
| `--telegram-group` | ❌ | — | Telegram 群组 ID，用于完成通知 |
| `--model` | ❌ | Codex 配置默认值 | 模型覆盖（如 `gpt-5.3-codex`、`o3`） |
| `--sandbox` | ❌ | `workspace-write` | 沙盒模式：`read-only`、`workspace-write`、`danger-full-access` |
| `--full-auto` | ❌ | `true` | 跳过交互式确认 |
| `--image` | ❌ | — | 附加图片（可重复使用） |
| `--skip-git-check` | ❌ | `false` | 跳过 git 仓库初始化 |
| `--agent-id` | ❌ | — | 完成后唤醒的 OpenClaw Agent ID |

### 在 OpenClaw Agent 中使用

作为 OpenClaw 技能使用时，Agent 这样分发任务：

```bash
# 必须使用 nohup + & 后台运行，避免阻塞 Agent
nohup bash /path/to/skills/codex-cli-dispatch/scripts/dispatch.sh \
  --prompt "用 React 构建一个 TODO 应用" \
  --task-name "todo-app" \
  --workdir "/home/user/projects/todo-app" \
  --telegram-group "-1001234567890" \
  > /tmp/dispatch-codex.log 2>&1 &
```

## 工作原理

```
OpenClaw Agent
  ├── exec: dispatch.sh（后台，非阻塞）
  │     ├── 写入任务元数据（task-meta.json）
  │     ├── 运行：codex exec --full-auto --sandbox workspace-write "prompt"
  │     ├── 捕获输出（task-output.txt）
  │     ├── 写入结果（latest.json）
  │     ├── 通过 openclaw message send 发送 Telegram 通知
  │     └── 通过 /hooks/wake 端点唤醒 Agent
  └── （Agent 继续处理其他请求）
```

## 输出文件

结果写入 `data/codex-results/` 目录：

| 文件 | 说明 |
|------|------|
| `latest.json` | 最近一次任务结果（task_name、output、status、exit_code） |
| `task-meta.json` | 任务元数据（prompt、workdir、时间信息） |
| `task-output.txt` | Codex CLI 原始输出 |

### `latest.json` 示例

```json
{
  "task_name": "express-api",
  "timestamp": "2026-03-04T12:34:56+00:00",
  "output": "... Codex 输出的最后 4000 字符 ...",
  "telegram_group": "-1001234567890",
  "exit_code": 0,
  "status": "done"
}
```

## 注意事项

1. **Codex 需要 git 仓库** — 脚本会自动初始化，使用 `--skip-git-check` 可跳过
2. **不要轮询后台进程** — 脚本会自动发送通知，轮询只会浪费资源
3. **注意沙盒模式** — 默认 `workspace-write` 最安全，仅在系统级任务时使用 `danger-full-access`
4. **长任务可能 OOM** — Codex 推理模式内存消耗较大，建议拆分大型任务
5. **Git 初始化隔离** — 脚本仅在 `--workdir` 层级创建 git 仓库，不会嵌套

## 许可证

MIT

## 相关项目

- [OpenClaw](https://github.com/openclaw/openclaw) — 本技能所基于的 AI Agent 框架
- [Codex CLI](https://github.com/openai/codex) — OpenAI 的终端编程 Agent
- [ClawhHub](https://clawhub.com) — 发现更多 OpenClaw 技能
