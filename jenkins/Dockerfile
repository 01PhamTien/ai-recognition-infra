# Extend official Jenkins LTS with tools required by CI.
FROM docker:cli AS docker-cli
FROM node:22-bookworm-slim AS node-runtime
FROM jenkins/jenkins:lts-jdk21

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       python3 \
       python3-pip \
       python3-venv \
    && rm -rf /var/lib/apt/lists/*

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
# Copy the complete Node installation so npm's relative paths and symlinks
# resolve exactly as they do in the official Node image.
COPY --from=node-runtime /usr/local/ /usr/local/

ENV PATH="/usr/local/bin:${PATH}"

USER jenkins
