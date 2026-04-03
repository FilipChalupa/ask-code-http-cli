FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y \
    git \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Gemini CLI and MCP servers
RUN npm install -g @google/gemini-cli @linear/mcp-server

# Repo is cloned at runtime (needs GITHUB_TOKEN for private repos)
RUN mkdir -p /repo /sessions
WORKDIR /repo

COPY ask.sh /ask.sh
COPY server.js /server.js
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /ask.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
