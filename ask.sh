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
PROMPT="If the question is in Czech, answer in Czech. Be concise and specific. Do not greet the user or address them by name, do not thank them, and do not add closing pleasantries such as offers of further help - reply with the answer itself and nothing else. The working directory may contain several repositories as subdirectories - consider all of them when answering. Do not modify any code - your task is only to analyze and answer questions, not to develop. Any code changes will be reset on the next query, so making edits is pointless."
if [ -n "$LINEAR_API_KEY" ]; then
    PROMPT="$PROMPT Linear is an optional source of extra context: when relevant you may search it for issues, comments, and project context. If any Linear tool call fails or returns an error, silently ignore it and answer from the repository code instead - never let a Linear failure block or appear in your answer."
fi
PROMPT="$PROMPT Question: $QUESTION"

GEMINI_ARGS=(-o json --allowed-mcp-server-names linear -y --skip-trust)
if [ -n "$GEMINI_MODEL" ]; then
    GEMINI_ARGS+=(-m "$GEMINI_MODEL")
fi

# Look up Gemini UUID from session mapping
GEMINI_UUID=""
if [ -n "$SESSION_ID" ]; then
    GEMINI_UUID=$(jq -r --arg sid "$SESSION_ID" '.[$sid] // empty' "$SESSIONS_FILE")
    if [ -n "$GEMINI_UUID" ]; then
        debug "Resuming session $SESSION_ID -> $GEMINI_UUID"
    else
        debug "New session: $SESSION_ID"
    fi
fi

# We keep our own transcript of each thread (Q/A pairs) alongside the session
# mapping. When resuming a Gemini session keeps failing, the last attempt
# starts a fresh session with this transcript injected into the prompt, so the
# thread context survives even though the Gemini-side history is abandoned.
TRANSCRIPTS_DIR="$(dirname "$SESSIONS_FILE")/transcripts"
TRANSCRIPT_FILE=""
FALLBACK_PROMPT="$PROMPT"
if [ -n "$SESSION_ID" ]; then
    TRANSCRIPT_FILE="$TRANSCRIPTS_DIR/$SESSION_ID.txt"
    if [ -f "$TRANSCRIPT_FILE" ]; then
        FALLBACK_PROMPT="Earlier messages in this conversation, oldest first (Q is the user, A is you):
$(cat "$TRANSCRIPT_FILE")

$PROMPT"
    fi
fi

# Run Gemini CLI with a few retries. The model occasionally returns an empty
# response / malformed tool call (error type INVALID_STREAM), often when an MCP
# tool call fails mid-stream. These failures come in streaks tied to a resumed
# session, so plain resume retries don't always recover - the final attempt
# drops --resume and falls back to a fresh session + our transcript instead.
# stderr is passed through so server.js logs it if gemini keeps failing.
cd "$REPOS_DIR"
MAX_ATTEMPTS="${GEMINI_MAX_ATTEMPTS:-3}"
ANSWER=""
RESPONSE=""
NEW_GEMINI_UUID=""
attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    ATTEMPT_ARGS=("${GEMINI_ARGS[@]}")
    if [ -n "$GEMINI_UUID" ] && { [ "$attempt" -lt "$MAX_ATTEMPTS" ] || [ "$MAX_ATTEMPTS" -eq 1 ]; }; then
        ATTEMPT_ARGS+=(--resume "$GEMINI_UUID" -p "$PROMPT")
    elif [ -n "$GEMINI_UUID" ]; then
        debug "Resume kept failing; falling back to a fresh session with transcript"
        ATTEMPT_ARGS+=(-p "$FALLBACK_PROMPT")
    else
        ATTEMPT_ARGS+=(-p "$PROMPT")
    fi

    # '|| true' so set -e doesn't abort before we can inspect/retry the output
    RAW_OUTPUT=$(gemini "${ATTEMPT_ARGS[@]}") || true
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

# Append this exchange to the thread transcript (kept to the newest ~16 kB)
# so a future fresh-session fallback can restore the context.
if [ -n "$TRANSCRIPT_FILE" ]; then
    mkdir -p "$TRANSCRIPTS_DIR"
    printf 'Q: %s\nA: %s\n---\n' "$QUESTION" "$ANSWER" >> "$TRANSCRIPT_FILE"
    tail -c 16000 "$TRANSCRIPT_FILE" > "${TRANSCRIPT_FILE}.tmp" && \
        mv "${TRANSCRIPT_FILE}.tmp" "$TRANSCRIPT_FILE"
fi

# Output answer, and session tag as last line (for server.js to parse)
echo "$ANSWER"
if [ -n "$NEW_GEMINI_UUID" ]; then
    echo "SESSION_ID:$NEW_GEMINI_UUID"
fi
