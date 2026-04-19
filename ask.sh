#!/bin/bash
# Asks a question about the repo using Gemini CLI.
# Usage: ask.sh "question" [session-id]
set -e

QUESTION="$1"
SESSION_ID="$2"
SESSIONS_FILE="/sessions/sessions.json"
VERBOSE="${VERBOSE:-0}"
SHARED_MEMORY="${SHARED_MEMORY:-0}"
SHARED_MEMORY_DIR="/shared-memory"

debug() {
    [ "$VERBOSE" = "1" ] && echo "$@" >&2 || true
}

if [ -z "$QUESTION" ]; then
    echo "Usage: ask.sh 'your question' [session-id]" >&2
    exit 1
fi

if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY not set" >&2
    exit 1
fi

REPO_URL="${REPO_URL:-https://github.com/FilipChalupa/ask-code-http-cli.git}"

# Build authenticated URL if GITHUB_TOKEN is set
if [ -n "$GITHUB_TOKEN" ]; then
    AUTH_URL=$(echo "$REPO_URL" | sed "s|https://|https://${GITHUB_TOKEN}@|")
else
    AUTH_URL="$REPO_URL"
fi

# Always fetch the latest main branch before answering
debug "Fetching latest code..."
git -C /repo remote set-url origin "$AUTH_URL" 2>/dev/null
git -C /repo fetch origin main 2>/dev/null && \
    git -C /repo reset --hard origin/main >/dev/null 2>/dev/null || \
    echo "Warning: could not update repo, using cached version" >&2

# Ensure sessions file exists
mkdir -p "$(dirname "$SESSIONS_FILE")"
if [ ! -f "$SESSIONS_FILE" ]; then
    echo '{}' > "$SESSIONS_FILE"
fi

# Build prompt with optional Linear context
PROMPT="If the question is in Czech, answer in Czech. Be concise and specific. Do not modify any code - your task is only to analyze and answer questions, not to develop. Any code changes will be reset on the next query, so making edits is pointless."
if [ -n "$LINEAR_API_KEY" ]; then
    PROMPT="$PROMPT When relevant, search Linear for issues, comments, and project context to enrich your answer."
fi
if [ "$SHARED_MEMORY" = "1" ]; then
    mkdir -p "$SHARED_MEMORY_DIR"
    PROMPT="$PROMPT You have a persistent shared memory directory at $SHARED_MEMORY_DIR that survives between queries (the repo itself is reset each query, but this directory is not). Feel free to read existing notes there at the start and to write down any facts, findings, or context that might be useful for answering future questions. Organize notes into readable files (e.g. markdown) and keep them concise and accurate."
fi
PROMPT="$PROMPT Question: $QUESTION"

GEMINI_ARGS=(-p "$PROMPT" -o json --allowed-mcp-server-names linear -y)

# Look up Gemini UUID from session mapping
if [ -n "$SESSION_ID" ]; then
    GEMINI_UUID=$(jq -r --arg sid "$SESSION_ID" '.[$sid] // empty' "$SESSIONS_FILE")
    if [ -n "$GEMINI_UUID" ]; then
        GEMINI_ARGS+=(--resume "$GEMINI_UUID")
        debug "Resuming session $SESSION_ID -> $GEMINI_UUID"
    else
        debug "New session: $SESSION_ID"
    fi
fi

# Run Gemini CLI (extract only the JSON object from output, MCP logs may precede it).
# stderr is passed through so server.js logs it if gemini fails.
cd /repo
RAW_OUTPUT=$(gemini "${GEMINI_ARGS[@]}")
# Strip any non-JSON prefix (MCP logs may be prepended without newline)
RESPONSE=$(echo "$RAW_OUTPUT" | perl -0777 -pe 's/^.*?(?=\{)//s')

# Parse JSON output
ANSWER=$(echo "$RESPONSE" | jq -r '.response // empty')
NEW_GEMINI_UUID=$(echo "$RESPONSE" | jq -r '.session_id // empty')

if [ -z "$ANSWER" ]; then
    echo "No answer received. Raw response:" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

# Save session mapping if session ID was provided
if [ -n "$SESSION_ID" ] && [ -n "$NEW_GEMINI_UUID" ]; then
    jq --arg sid "$SESSION_ID" --arg uuid "$NEW_GEMINI_UUID" \
        '.[$sid] = $uuid' "$SESSIONS_FILE" > "${SESSIONS_FILE}.tmp" && \
        mv "${SESSIONS_FILE}.tmp" "$SESSIONS_FILE"
fi

# Output answer, and session tag as last line (for server.js to parse)
echo "$ANSWER"
if [ -n "$NEW_GEMINI_UUID" ]; then
    echo "SESSION_ID:$NEW_GEMINI_UUID"
fi
