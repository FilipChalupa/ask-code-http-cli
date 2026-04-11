# ask-code-agent

Docker container that answers questions about the [ask-code-http-cli](https://github.com/FilipChalupa/ask-code-http-cli) or any other repository codebase using Gemini API.

## Setup

1. Get a free Gemini API key at https://aistudio.google.com/apikey

2. Copy `.env.sample` to `.env` and fill in your values:

   ```bash
   cp .env.sample .env
   ```

   ```
   GEMINI_API_KEY=AIza...
   REPO_URL=https://github.com/your-org/your-repo.git
   ```

3. Build and start:
   ```bash
   docker compose up -d --build
   ```

### Optional: Private repositories

For private repos, create a fine-grained GitHub PAT with **Contents: read** permission and add it to `.env`:

```
GITHUB_TOKEN=github_pat_...
```

### Optional: Linear integration

The agent can also search [Linear](https://linear.app) for relevant issues, comments, and project context when answering questions.

1. In Linear, go to **Settings > API > Personal API keys**
2. Create a new key (read access is sufficient)
3. Add it to `.env`:

   ```
   LINEAR_API_KEY=lin_api_...
   ```

When configured, the agent automatically queries Linear for context related to the question alongside the codebase search. If the key is not set, the agent works with the codebase only.

## Usage

### HTTP server (default)

The container starts an HTTP server on port 3000. Send a POST request with the question as the body:

```bash
curl -X POST http://localhost:3000 -d "What does main.js do?"
```

#### Conversation sessions

Use the `X-Session-Id` header to maintain context across follow-up questions. You can use any string as the session ID (e.g. Slack thread timestamps):

```bash
# First question — starts a new session
curl -X POST http://localhost:3000 \
  -H "X-Session-Id: 1711234567.123456" \
  -d "What does the auth module do?"

# Follow-up — same session ID preserves context
curl -X POST http://localhost:3000 \
  -H "X-Session-Id: 1711234567.123456" \
  -d "How does it handle token refresh?"
```

Without the header, each request is stateless.

#### Health check

```bash
curl http://localhost:3000
# Returns: ok, queue length, busy status
```

#### Home Assistant rest_command example

```yaml
rest_command:
  ask_code:
    url: "http://localhost:3000"
    method: POST
    payload: "{{ question }}"
    content_type: "text/plain"
```

### CLI

You can also ask questions directly via `docker exec`:

```bash
docker exec ask-code-agent /ask.sh "What does main.js do?"
```

### Verbose mode

Set `VERBOSE=1` in `.env` to enable debug output (fetching status, session resuming). Disabled by default.

### One-shot via environment variable

```bash
docker run --rm --env-file .env -e QUESTION="Explain the renderer" ask-code-agent
```
