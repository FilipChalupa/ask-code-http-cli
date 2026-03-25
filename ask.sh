#!/bin/bash
# Sends a question + repo source code to Gemini API and prints the answer.
set -e

QUESTION="$1"
if [ -z "$QUESTION" ]; then
    echo "Usage: ask.sh 'your question'" >&2
    exit 1
fi

if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY not set" >&2
    exit 1
fi

MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_API_KEY}"

REPO_URL="${REPO_URL:-https://github.com/kilomayocom/background-configurator.git}"

# Build authenticated URL if GITHUB_TOKEN is set
if [ -n "$GITHUB_TOKEN" ]; then
    AUTH_URL=$(echo "$REPO_URL" | sed "s|https://|https://${GITHUB_TOKEN}@|")
else
    AUTH_URL="$REPO_URL"
fi

# Always fetch the latest main branch before answering
echo "Fetching latest code..." >&2
git -C /repo remote set-url origin "$AUTH_URL" 2>/dev/null
git -C /repo fetch --depth 1 origin main 2>/dev/null && \
    git -C /repo reset --hard origin/main 2>/dev/null || \
    echo "Warning: could not update repo, using cached version" >&2

# Gather all source files from the repo into a single context string
REPO_CONTEXT=""
for f in $(find /repo -maxdepth 2 -type f \( -name '*.html' -o -name '*.js' -o -name '*.css' -o -name '*.json' -o -name '*.md' \) ! -path '*node_modules*' ! -path '*.git*' | sort); do
    REPO_CONTEXT="${REPO_CONTEXT}
--- FILE: ${f} ---
$(cat "$f")
"
done

SYSTEM_PROMPT="You are a helpful code assistant. You have access to the full source code of the 'background-configurator' repository below. Answer the user's question based on this code. Be concise and specific. If the question is in Czech, answer in Czech.

${REPO_CONTEXT}"

# Build JSON payload using jq to properly escape strings
PAYLOAD=$(jq -n \
    --arg system "$SYSTEM_PROMPT" \
    --arg question "$QUESTION" \
    '{
        "system_instruction": {"parts": [{"text": $system}]},
        "contents": [{"parts": [{"text": $question}]}]
    }')

RESPONSE=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

# Extract the text from the response
ANSWER=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // empty')

if [ -z "$ANSWER" ]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
    if [ -n "$ERROR" ]; then
        echo "Gemini API error: $ERROR" >&2
    else
        echo "No answer received. Raw response:" >&2
        echo "$RESPONSE" >&2
    fi
    exit 1
fi

echo "$ANSWER"
