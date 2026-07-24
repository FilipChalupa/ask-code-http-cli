# Helpers for expanding Slack permalinks in a question into thread context.
# Needs SLACK_BOT_TOKEN (scopes: channels:history + users:read, plus
# groups:history for private channels; the bot must be a member of the linked
# channel). Sourced by ask.sh. Everything here is best-effort: any failure
# means answering without the context, never blocking the answer.

SLACK_USERS_CACHE="${SLACK_USERS_CACHE:-/sessions/slack-users.json}"

slack_api() {
    curl -sf --max-time 10 -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
        "https://slack.com/api/$1"
}

# Print "channel ts" for a Slack permalink. The p-suffix is the message
# timestamp with the dot removed. A thread_ts query param (permalink to a
# reply inside a thread) points at the thread parent and wins -
# conversations.replies expects the parent's ts.
slack_link_parse() {
    local link="$1" channel pts ts thread_ts
    channel=$(echo "$link" | sed -nE 's|.*/archives/([A-Z0-9]+)/p[0-9].*|\1|p')
    pts=$(echo "$link" | sed -nE 's|.*/p([0-9]{7,}).*|\1|p')
    [ -n "$channel" ] && [ -n "$pts" ] || return 1
    ts="${pts%??????}.${pts#"${pts%??????}"}"
    thread_ts=$(echo "$link" | grep -oE 'thread_ts=[0-9]+\.[0-9]+' | head -n1 | cut -d= -f2 || true)
    [ -n "$thread_ts" ] && ts="$thread_ts"
    echo "$channel $ts"
}

# Display name for a Slack user id, cached in SLACK_USERS_CACHE (author ids
# repeat across threads; users.info would otherwise be called over and over).
# Falls back to the raw id when the lookup fails.
slack_user_name() {
    local uid="$1" name=""
    if [ -f "$SLACK_USERS_CACHE" ]; then
        name=$(jq -r --arg u "$uid" '.[$u] // empty' "$SLACK_USERS_CACHE" 2>/dev/null) || name=""
    fi
    if [ -z "$name" ]; then
        name=$(slack_api "users.info?user=$uid" \
            | jq -r '.user | (.profile.display_name | select(. != null and . != "")) // .real_name // .name // empty' \
            2>/dev/null) || name=""
        if [ -n "$name" ]; then
            (
                flock 9
                [ -f "$SLACK_USERS_CACHE" ] || echo '{}' > "$SLACK_USERS_CACHE"
                jq --arg u "$uid" --arg n "$name" '.[$u] = $n' \
                    "$SLACK_USERS_CACHE" > "${SLACK_USERS_CACHE}.tmp" 2>/dev/null && \
                    mv "${SLACK_USERS_CACHE}.tmp" "$SLACK_USERS_CACHE" || true
            ) 9>"${SLACK_USERS_CACHE}.lock"
        fi
    fi
    echo "${name:-$uid}"
}

# Print a thread as "author: text" lines, oldest first (the parent message
# comes first). Capped at ~16 kB from the start so the parent - usually the
# reason the thread was linked - always survives.
fetch_slack_thread() {
    local channel="$1" ts="$2" replies names uid name
    replies=$(slack_api "conversations.replies?channel=$channel&ts=$ts&limit=100") || return 1
    if [ "$(echo "$replies" | jq -r '.ok' 2>/dev/null)" != "true" ]; then
        debug "Slack API error for $channel/$ts: $(echo "$replies" | jq -r '.error // "unknown"' 2>/dev/null)"
        return 1
    fi
    names='{}'
    for uid in $(echo "$replies" | jq -r '[.messages[].user // empty] | unique | .[]' 2>/dev/null); do
        name=$(slack_user_name "$uid")
        names=$(echo "$names" | jq --arg u "$uid" --arg n "$name" '.[$u] = $n')
    done
    echo "$replies" | jq -r --argjson names "$names" \
        '.messages[] | "\(if .user then ($names[.user] // .user) else (.username // "bot") end): \(.text // "")"' \
        | head -c 16000
}

# Print a context block covering every Slack permalink found in the question
# (up to 3). Empty output when there are no links or nothing could be fetched.
slack_context_for_question() {
    local question="$1" context="" link parts thread
    for link in $(echo "$question" \
        | grep -oE 'https://[A-Za-z0-9.-]+\.slack\.com/archives/[A-Z0-9]+/p[0-9]+[^ <>|]*' \
        | head -n 3); do
        parts=$(slack_link_parse "$link") || continue
        debug "Fetching Slack thread ${parts/ //} ..."
        # shellcheck disable=SC2086 - parts is "channel ts", split intended
        thread=$(fetch_slack_thread $parts) || continue
        [ -n "$thread" ] || continue
        context="$context
Content of the Slack thread linked as $link (one message per line, 'author: text', oldest first):
$thread"
    done
    echo "$context"
}
