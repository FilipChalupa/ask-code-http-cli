#!/bin/bash

CONTAINER_NAME="ask-code-agent"

echo "Checking if Docker container '$CONTAINER_NAME' is running..."
if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
    echo "Error: Docker container '$CONTAINER_NAME' is not running."
    echo "Please start it using 'docker compose up -d --build' in the project root directory."
    exit 1
fi

echo "Asking a question to trigger Linear integration..."
# This question is designed to be general enough that if Linear integration is working,
# the gemini CLI should be able to find relevant context.
QUESTION="Can you tell me about any open issues or recent discussions related to project setup?"

docker exec "$CONTAINER_NAME" /ask.sh "$QUESTION"
