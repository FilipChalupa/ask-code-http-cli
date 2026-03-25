FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Gemini CLI
RUN npm install -g @google/gemini-cli

# Repo is cloned at runtime (needs GITHUB_TOKEN for private repos)
RUN mkdir -p /repo
WORKDIR /repo

COPY ask.sh /ask.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /ask.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
