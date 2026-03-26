# ask-code-agent

Docker container that answers questions about the [ask-code-http-cli](https://github.com/FilipChalupa/ask-code-http-cli) or any other repository codebase using Gemini API.

## Setup

1. Get a free Gemini API key at https://aistudio.google.com/apikey

2. Add it to `.env`:

   ```
   GEMINI_API_KEY=AIza...
   ```

3. Build and start:
   ```bash
   docker compose up -d --build
   ```

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

### One-shot via environment variable

```bash
docker run --rm --env-file .env -e QUESTION="Explain the renderer" ask-code-agent
```
