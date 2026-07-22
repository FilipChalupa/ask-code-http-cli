# Shared helpers for working with the configured repositories.
# Sourced by entrypoint.sh and ask.sh.

# Print one repo URL per line. Reads REPO_URLS (preferred) or REPO_URL (legacy),
# either of which may hold several URLs separated by commas/whitespace/newlines.
repo_urls() {
    local raw="${REPO_URLS:-$REPO_URL}"
    raw="${raw:-https://github.com/FilipChalupa/ask-code-http-cli.git}"
    echo "$raw" | tr ',\r\n\t' '    ' | xargs -n1
}

# Local directory name for a repo URL (basename without the .git suffix).
# When several configured repos share a basename (org1/api.git, org2/api.git),
# a short URL hash is appended so they do not silently collide in /repos.
repo_dirname() {
    local url="$1" base other count=0
    base=$(basename "$url" .git)
    for other in $(repo_urls); do
        [ "$(basename "$other" .git)" = "$base" ] && count=$((count + 1))
    done
    if [ "$count" -gt 1 ]; then
        echo "$base-$(echo -n "$url" | sha1sum | cut -c1-8)"
    else
        echo "$base"
    fi
}

# Build the authenticated git URL if GITHUB_TOKEN is set
repo_auth_url() {
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$1" | sed "s|https://|https://${GITHUB_TOKEN}@|"
    else
        echo "$1"
    fi
}
