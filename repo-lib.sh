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

# Build the authenticated git URL for a repo. The credential is picked by host:
# GITHUB_TOKEN for github.com, BITBUCKET_TOKEN for bitbucket.org (which expects
# the x-token-auth:TOKEN@ form). URLs that already embed credentials
# (https://user:secret@host/...) are passed through untouched, so mixing hosts
# and hand-authenticated URLs in REPO_URLS is safe.
repo_auth_url() {
    local url="$1"
    case "$url" in
        https://*@*)
            echo "$url" ;;
        https://github.com/*)
            if [ -n "$GITHUB_TOKEN" ]; then
                echo "$url" | sed "s|https://|https://${GITHUB_TOKEN}@|"
            else
                echo "$url"
            fi ;;
        https://bitbucket.org/*)
            if [ -n "$BITBUCKET_TOKEN" ]; then
                echo "$url" | sed "s|https://|https://x-token-auth:${BITBUCKET_TOKEN}@|"
            else
                echo "$url"
            fi ;;
        *)
            echo "$url" ;;
    esac
}
