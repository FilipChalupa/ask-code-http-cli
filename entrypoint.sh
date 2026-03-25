#!/bin/bash
set -e

REPO_URL="${REPO_URL:-https://github.com/kilomayocom/background-configurator.git}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Build the authenticated git URL if GITHUB_TOKEN is set
repo_auth_url() {
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$REPO_URL" | sed "s|https://|https://${GITHUB_TOKEN}@|"
    else
        echo "$REPO_URL"
    fi
}

# Clone repo on first start
if [ ! -d /repo/.git ]; then
    log "Cloning repository..."
    git clone --depth 1 "$(repo_auth_url)" /repo
    log "Clone complete."
fi

ask() {
    local question="$1"
    log "Question received: $question"
    log "Thinking..."
    /ask.sh "$question"
    local status=$?
    if [ $status -eq 0 ]; then
        log "Done."
    else
        log "ask.sh exited with status $status"
    fi
    return $status
}

# If a question is passed as an argument
if [ $# -gt 0 ]; then
    ask "$*"
    exit $?
fi

# If QUESTION env var is set (e.g. from Home Assistant / Slack)
if [ -n "$QUESTION" ]; then
    ask "$QUESTION"
    exit $?
fi

# Default: start web server (docker exec /ask.sh still works too)
log "ask-code-agent ready (working dir: $(pwd))"
log "Repo contents: $(ls -1 | head -10)"
log ""
log "HTTP server starting on port ${PORT:-3000}"
log "CLI still available: docker exec ask-code-agent /ask.sh 'your question'"
exec node /server.js
