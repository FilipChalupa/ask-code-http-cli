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

### Ask a question

```bash
docker exec ask-code-agent /ask.sh "What does main.js do?"
```

### Home Assistant shell_command example

```yaml
shell_command:
  ask_code: >-
    docker exec ask-code-agent /ask.sh "{{ question }}"
```

### One-shot via environment variable

```bash
docker run --rm --env-file .env -e QUESTION="Explain the renderer" ask-code-agent
```
