#!/bin/bash
# Asks a question about the repo using Gemini CLI.
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

REPO_URL="${REPO_URL:-https://github.com/FilipChalupa/ask-code-http-cli.git}"

# Build authenticated URL if GITHUB_TOKEN is set
if [ -n "$GITHUB_TOKEN" ]; then
    AUTH_URL=$(echo "$REPO_URL" | sed "s|https://|https://${GITHUB_TOKEN}@|")
else
    AUTH_URL="$REPO_URL"
fi

# Always fetch the latest main branch before answering
echo "Fetching latest code..." >&2
git -C /repo remote set-url origin "$AUTH_URL" 2>/dev/null
git -C /repo fetch origin main 2>/dev/null && \
    git -C /repo reset --hard origin/main >/dev/null 2>/dev/null || \
    echo "Warning: could not update repo, using cached version" >&2

# Run Gemini CLI in non-interactive mode from the repo directory
cd /repo
gemini -p "If the question is in Czech, answer in Czech. Be concise and specific. Question: $QUESTION"
