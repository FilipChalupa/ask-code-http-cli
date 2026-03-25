#!/bin/bash
set -e

# If a question is passed as an argument, run Claude in non-interactive mode
if [ $# -gt 0 ]; then
    QUESTION="$*"
    echo "--- Question: $QUESTION ---"
    claude -p --allowedTools "Read,Glob,Grep,WebFetch" "$QUESTION"
    exit $?
fi

# If QUESTION env var is set (e.g. from Home Assistant / Slack), use that
if [ -n "$QUESTION" ]; then
    echo "--- Question: $QUESTION ---"
    claude -p --allowedTools "Read,Glob,Grep,WebFetch" "$QUESTION"
    exit $?
fi

# Default: keep container alive waiting for questions via docker exec
echo "ask-code-agent ready. Send questions with:"
echo "  docker exec ask-code-agent claude -p 'your question here'"
echo ""
echo "Or restart the container with:"
echo "  docker run --rm -e QUESTION='your question' ask-code-agent"
echo ""
echo "Waiting for input..."
tail -f /dev/null
