#!/bin/bash
set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

ask_claude() {
    local question="$1"
    log "Question received: $question"
    log "Claude is thinking..."
    claude -p --allowedTools "Read,Glob,Grep,WebFetch" "$question"
    local status=$?
    if [ $status -eq 0 ]; then
        log "Done."
    else
        log "Claude exited with status $status"
    fi
    return $status
}

# If a question is passed as an argument, run Claude in non-interactive mode
if [ $# -gt 0 ]; then
    ask_claude "$*"
    exit $?
fi

# If QUESTION env var is set (e.g. from Home Assistant / Slack), use that
if [ -n "$QUESTION" ]; then
    ask_claude "$QUESTION"
    exit $?
fi

# Default: keep container alive waiting for questions via docker exec
log "ask-code-agent ready (working dir: $(pwd))"
log "Repo contents: $(ls -1 | head -10)"
log ""
log "Send questions with:"
log "  docker exec ask-code-agent claude -p 'your question here'"
log ""
log "Idle — waiting for docker exec calls..."
tail -f /dev/null
