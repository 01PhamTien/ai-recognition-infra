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
COPY --from=node-runtime /usr/local/bin/node /usr/local/bin/node
COPY --from=node-runtime /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node-runtime /usr/local/bin/npm /usr/local/bin/npm
COPY --from=node-runtime /usr/local/bin/npx /usr/local/bin/npx

ENV PATH="/usr/local/bin:${PATH}"

USER jenkins
