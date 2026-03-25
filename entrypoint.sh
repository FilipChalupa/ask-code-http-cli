#!/bin/bash
set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

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

# Default: keep container alive waiting for docker exec calls
log "ask-code-agent ready (working dir: $(pwd))"
log "Repo contents: $(ls -1 | head -10)"
log ""
log "Send questions with:"
log "  docker exec ask-code-agent /ask.sh 'your question here'"
log ""
log "Idle — waiting for docker exec calls..."
tail -f /dev/null
