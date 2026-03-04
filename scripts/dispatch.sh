#!/bin/bash
# Codex CLI Dispatch Script
# Runs codex exec in headless mode with automatic Telegram notification on completion.
#
# Usage:
#   bash dispatch.sh --prompt "Build X" --task-name "my-task" --workdir "/path" --telegram-group "-123"

set -euo pipefail

RESULT_DIR="/home/ubuntu/clawd/data/codex-results"
META_FILE="${RESULT_DIR}/task-meta.json"
TASK_OUTPUT="${RESULT_DIR}/task-output.txt"
OPENCLAW_BIN="/home/ubuntu/.npm-global/bin/openclaw"
CODEX_BIN="${CODEX_BIN:-/home/ubuntu/.npm-global/bin/codex}"

# Defaults
PROMPT=""
TASK_NAME="codex-$(date +%s)"
TELEGRAM_GROUP="-5006066016"  # Default: Claude Code Tasks group
WORKDIR="/home/ubuntu/clawd"
MODEL=""
SANDBOX="workspace-write"
FULL_AUTO="true"
IMAGES=()
SKIP_GIT_CHECK="false"
AGENT_ID=""

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt) PROMPT="$2"; shift 2 ;;
        --task-name) TASK_NAME="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --telegram-group) TELEGRAM_GROUP="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --sandbox) SANDBOX="$2"; shift 2 ;;
        --full-auto) FULL_AUTO="$2"; shift 2 ;;
        --image) IMAGES+=("$2"); shift 2 ;;
        --skip-git-check) SKIP_GIT_CHECK="true"; shift ;;
        --agent-id) AGENT_ID="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

if [ -z "$PROMPT" ]; then
    echo "Error: --prompt is required"
    exit 1
fi

# ---- 1. Write task metadata ----
mkdir -p "$RESULT_DIR"

jq -n \
    --arg name "$TASK_NAME" \
    --arg group "$TELEGRAM_GROUP" \
    --arg prompt "$PROMPT" \
    --arg workdir "$WORKDIR" \
    --arg model "$MODEL" \
    --arg sandbox "$SANDBOX" \
    --arg agent_id "$AGENT_ID" \
    --arg ts "$(date -Iseconds)" \
    '{task_name: $name, telegram_group: $group, prompt: $prompt, workdir: $workdir, model: $model, sandbox: $sandbox, agent_id: $agent_id, started_at: $ts, status: "running"}' \
    > "$META_FILE"

echo "[dispatch] Task: $TASK_NAME"
echo "[dispatch] Workdir: $WORKDIR"
echo "[dispatch] Model: ${MODEL:-default}"
echo "[dispatch] Sandbox: $SANDBOX"

# ---- 2. Ensure workdir has git ----
mkdir -p "$WORKDIR"
if [ ! -d "$WORKDIR/.git" ] && [ "$SKIP_GIT_CHECK" != "true" ]; then
    echo "[dispatch] Initializing git in $WORKDIR"
    cd "$WORKDIR" && git init -q
fi

# ---- 3. Build codex command ----
CMD=("$CODEX_BIN" "exec")

if [ "$FULL_AUTO" = "true" ]; then
    CMD+=("--full-auto")
fi

CMD+=("--sandbox" "$SANDBOX")
CMD+=("-C" "$WORKDIR")

if [ -n "$MODEL" ]; then
    CMD+=("--model" "$MODEL")
fi

for img in "${IMAGES[@]}"; do
    CMD+=("--image" "$img")
done

CMD+=("$PROMPT")

echo "[dispatch] Running: ${CMD[*]}"

# ---- 4. Run Codex ----
"${CMD[@]}" 2>&1 | tee "$TASK_OUTPUT"
EXIT_CODE=${PIPESTATUS[0]}

echo "[dispatch] Codex exited with code: $EXIT_CODE"

# ---- 5. Update metadata ----
COMPLETED_AT="$(date -Iseconds)"
jq --arg status "$([ "$EXIT_CODE" -eq 0 ] && echo 'done' || echo 'failed')" \
   --arg exit_code "$EXIT_CODE" \
   --arg completed "$COMPLETED_AT" \
   '. + {status: $status, exit_code: ($exit_code|tonumber), completed_at: $completed}' \
   "$META_FILE" > "${META_FILE}.tmp" && mv "${META_FILE}.tmp" "$META_FILE"

# ---- 6. Write latest.json ----
OUTPUT=$(tail -c 4000 "$TASK_OUTPUT" 2>/dev/null || echo "no output")

jq -n \
    --arg task "$TASK_NAME" \
    --arg ts "$COMPLETED_AT" \
    --arg output "$OUTPUT" \
    --arg group "$TELEGRAM_GROUP" \
    --arg exit_code "$EXIT_CODE" \
    '{task_name: $task, timestamp: $ts, output: $output, telegram_group: $group, exit_code: ($exit_code|tonumber), status: (if ($exit_code|tonumber) == 0 then "done" else "failed" end)}' \
    > "${RESULT_DIR}/latest.json"

# ---- 7. Send Telegram notification ----
if [ -n "$TELEGRAM_GROUP" ] && [ -x "$OPENCLAW_BIN" ]; then
    STATUS_EMOJI="✅"
    [ "$EXIT_CODE" != "0" ] && STATUS_EMOJI="❌"

    # Calculate duration
    DURATION=""
    STARTED=$(jq -r '.started_at // ""' "$META_FILE" 2>/dev/null || echo "")
    if [ -n "$STARTED" ]; then
        START_TS=$(date -d "$STARTED" +%s 2>/dev/null || echo 0)
        END_TS=$(date +%s)
        if [ "$START_TS" -gt 0 ]; then
            ELAPSED=$(( END_TS - START_TS ))
            MINS=$(( ELAPSED / 60 ))
            SECS=$(( ELAPSED % 60 ))
            DURATION="${MINS}m${SECS}s"
        fi
    fi

    # Extract last meaningful output (skip token counts etc)
    SUMMARY=$(tail -20 "$TASK_OUTPUT" | head -c 1000)

    MSG="${STATUS_EMOJI} *Codex CLI 任务完成*

📋 *任务:* \`${TASK_NAME}\`
📂 *路径:* \`${WORKDIR}\`"

    [ -n "$DURATION" ] && MSG="${MSG}
⏱ *耗时:* ${DURATION}"

    [ "$EXIT_CODE" != "0" ] && MSG="${MSG}
⚠️ *Exit Code:* ${EXIT_CODE}"

    MSG="${MSG}

📝 *输出摘要:*
\`\`\`
${SUMMARY}
\`\`\`"

    "$OPENCLAW_BIN" message send \
        --channel telegram \
        --target "$TELEGRAM_GROUP" \
        --message "$MSG" 2>/dev/null && echo "[dispatch] Telegram notification sent" || echo "[dispatch] Telegram send failed"
fi

# ---- Wake AGI or target agent ----
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
HOOK_TOKEN=""
OPENCLAW_CONFIG="/home/ubuntu/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_CONFIG" ]; then
    HOOK_TOKEN=$(jq -r '.hooks.token // ""' "$OPENCLAW_CONFIG" 2>/dev/null || echo "")
fi

if [ -n "$HOOK_TOKEN" ]; then
    WAKE_TEXT="[CODEX_CLI_DONE] task=${TASK_NAME} status=$([ "$EXIT_CODE" -eq 0 ] && echo done || echo failed) group=${TELEGRAM_GROUP:-none} ts=$(date -Iseconds)"

    if [ -n "$AGENT_ID" ] && [ "$AGENT_ID" != "main" ]; then
        # Wake specific agent
        AGENT_PAYLOAD=$(jq -n \
            --arg message "$WAKE_TEXT" \
            --arg agentId "$AGENT_ID" \
            --arg channel "telegram" \
            --arg to "${TELEGRAM_GROUP}" \
            '{message: $message, agentId: $agentId, wakeMode: "now", deliver: true, channel: $channel, to: $to}')

        curl -s -o /dev/null -X POST \
            "http://localhost:${GATEWAY_PORT}/hooks/agent" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${HOOK_TOKEN}" \
            -d "$AGENT_PAYLOAD" 2>/dev/null && echo "[dispatch] Agent wake sent (agentId=$AGENT_ID)" || echo "[dispatch] Agent wake failed"
    else
        # Wake main session
        curl -s -o /dev/null -X POST \
            "http://localhost:${GATEWAY_PORT}/hooks/wake" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${HOOK_TOKEN}" \
            -d "{\"text\":\"${WAKE_TEXT}\",\"mode\":\"now\"}" 2>/dev/null && echo "[dispatch] Wake sent to main" || echo "[dispatch] Wake failed"
    fi
else
    echo "[dispatch] No hook token, skipping wake"
fi

echo "[dispatch] Done."
