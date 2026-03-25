# ask-code-agent

Docker container running Claude Code agent against the [background-configurator](https://github.com/kilomayocom/background-configurator) repository. Designed to answer code questions from Slack via Home Assistant.

## Setup

1. Add your API key to `.env`:

   ```
   ANTHROPIC_API_KEY=sk-ant-...
   ```

2. Build and start:
   ```bash
   docker compose up -d --build
   ```

## Usage

### From Home Assistant / Slack automation

Run a one-shot question:

```bash
docker exec ask-code-agent claude -p --allowedTools "Read,Glob,Grep,WebFetch" "What does main.js do?"
```

Or pass via environment variable:

```bash
docker run --rm --env-file .env -e QUESTION="Explain the renderer" ask-code-agent
```

### Keeping the container alive

By default (no `QUESTION` set) the container stays running, ready for `docker exec` calls. This is the recommended mode for Home Assistant — call `docker exec` from a shell_command whenever a Slack message arrives.

#### Example Home Assistant `configuration.yaml`

```yaml
shell_command:
  ask_code: >-
    docker exec ask-code-agent claude -p --allowedTools "Read,Glob,Grep,WebFetch" "{{ question }}"
```
