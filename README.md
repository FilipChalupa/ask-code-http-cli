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
