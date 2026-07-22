#!/bin/bash
set -e

REPOS_DIR=/repos

# Keep Gemini CLI data on the same persistent volume as our session mapping,
# but via a symlink so our files never sit inside a directory Gemini owns.
mkdir -p /sessions/gemini
ln -sfn /sessions/gemini /root/.gemini

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

. /repo-lib.sh

# Configure Gemini CLI MCP servers
configure_mcp() {
    local gemini_dir="$HOME/.gemini"
    mkdir -p "$gemini_dir"

    local mcp_servers="{}"

    if [ -n "$LINEAR_API_KEY" ]; then
        log "Configuring Linear MCP server..."
        # Create wrapper script that passes env to MCP server
        cat > /linear-mcp.sh <<WRAPPER
#!/bin/bash
export LINEAR_API_KEY="$LINEAR_API_KEY"
exec linear-mcp
WRAPPER
        chmod +x /linear-mcp.sh
        # Read-only tool whitelist: the agent must never write to Linear, and
        # fewer tools also mean less prompt surface for malformed calls.
        mcp_servers=$(echo "$mcp_servers" | jq \
            '.linear = {
                "command": "/linear-mcp.sh",
                "includeTools": [
                    "get_issue", "list_issues", "search_issues",
                    "list_comments", "get_comment", "list_documents",
                    "list_teams", "list_projects", "get_status_map",
                    "list_attachments"
                ]
            }')
    fi

    echo "{\"mcpServers\": $mcp_servers}" | jq . > "$gemini_dir/settings.json"
}

configure_mcp

# Clone any not-yet-present repos on first start
mkdir -p "$REPOS_DIR"
for url in $(repo_urls); do
    dir="$REPOS_DIR/$(repo_dirname "$url")"
    if [ ! -d "$dir/.git" ]; then
        log "Cloning $url ..."
        git clone "$(repo_auth_url "$url")" "$dir"
        log "Clone complete: $dir"
    fi
done

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
