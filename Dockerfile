FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    git \
    curl \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Shallow clone the target repository
RUN git clone --depth 1 https://github.com/kilomayocom/background-configurator.git /repo

WORKDIR /repo

COPY ask.sh /ask.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /ask.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
