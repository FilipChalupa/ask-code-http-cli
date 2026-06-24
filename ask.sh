#!/bin/bash
# Asks a question about the repo using Gemini CLI.
# Usage: ask.sh "question" [session-id]
set -e

QUESTION="$1"
SESSION_ID="$2"
SESSIONS_FILE="/sessions/sessions.json"
VERBOSE="${VERBOSE:-0}"

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

REPOS_DIR=/repos

# Print one repo URL per line. Reads REPO_URLS (preferred) or REPO_URL (legacy),
# either of which may hold several URLs separated by commas/whitespace/newlines.
repo_urls() {
    local raw="${REPO_URLS:-$REPO_URL}"
    raw="${raw:-https://github.com/FilipChalupa/ask-code-http-cli.git}"
    echo "$raw" | tr ',\r\n\t' '    ' | xargs -n1
}

repo_dirname() {
    basename "$1" .git
}

repo_auth_url() {
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$1" | sed "s|https://|https://${GITHUB_TOKEN}@|"
    else
        echo "$1"
    fi
}

# Always fetch the latest code for every configured repo before answering
debug "Fetching latest code..."
mkdir -p "$REPOS_DIR"
for url in $(repo_urls); do
    dir="$REPOS_DIR/$(repo_dirname "$url")"
    auth_url=$(repo_auth_url "$url")
    if [ ! -d "$dir/.git" ]; then
        debug "Cloning $url ..."
        git clone "$auth_url" "$dir" 2>/dev/null || \
            echo "Warning: could not clone $url" >&2
        continue
    fi
    git -C "$dir" remote set-url origin "$auth_url" 2>/dev/null
    git -C "$dir" fetch origin 2>/dev/null && \
        git -C "$dir" reset --hard '@{u}' >/dev/null 2>/dev/null || \
        echo "Warning: could not update $dir, using cached version" >&2
done

# Ensure sessions file exists
mkdir -p "$(dirname "$SESSIONS_FILE")"
if [ ! -f "$SESSIONS_FILE" ]; then
    echo '{}' > "$SESSIONS_FILE"
fi

# Build prompt with optional Linear context
PROMPT="If the question is in Czech, answer in Czech. Be concise and specific. The working directory may contain several repositories as subdirectories - consider all of them when answering. Do not modify any code - your task is only to analyze and answer questions, not to develop. Any code changes will be reset on the next query, so making edits is pointless."
if [ -n "$LINEAR_API_KEY" ]; then
    PROMPT="$PROMPT When relevant, search Linear for issues, comments, and project context to enrich your answer."
fi
PROMPT="$PROMPT Question: $QUESTION"

GEMINI_ARGS=(-p "$PROMPT" -o json --allowed-mcp-server-names linear -y --skip-trust)
if [ -n "$GEMINI_MODEL" ]; then
    GEMINI_ARGS+=(-m "$GEMINI_MODEL")
fi

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

# Run Gemini CLI with a few retries. The model occasionally returns an empty
# response / malformed tool call (error type INVALID_STREAM), often when an MCP
# tool call fails mid-stream; a plain retry almost always succeeds.
# stderr is passed through so server.js logs it if gemini keeps failing.
cd "$REPOS_DIR"
MAX_ATTEMPTS="${GEMINI_MAX_ATTEMPTS:-3}"
ANSWER=""
RESPONSE=""
NEW_GEMINI_UUID=""
attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    # '|| true' so set -e doesn't abort before we can inspect/retry the output
    RAW_OUTPUT=$(gemini "${GEMINI_ARGS[@]}") || true
    # Strip any non-JSON prefix (MCP logs may be prepended without newline)
    RESPONSE=$(echo "$RAW_OUTPUT" | perl -0777 -pe 's/^.*?(?=\{)//s')

    # Parse JSON output
    ANSWER=$(echo "$RESPONSE" | jq -r '.response // empty' 2>/dev/null)
    NEW_GEMINI_UUID=$(echo "$RESPONSE" | jq -r '.session_id // empty' 2>/dev/null)

    [ -n "$ANSWER" ] && break

    debug "Attempt $attempt/$MAX_ATTEMPTS returned no answer; retrying..."
    attempt=$((attempt + 1))
    [ "$attempt" -le "$MAX_ATTEMPTS" ] && sleep 2
done

if [ -z "$ANSWER" ]; then
    echo "No answer received after $MAX_ATTEMPTS attempts. Raw response:" >&2
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
