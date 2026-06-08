# check=skip=InvalidDefaultArgInFrom
# BASE_IMAGE is always supplied by the docker module's build_args (the runner
# image digest), so an empty default here is intentional.
#
# Docker-in-Docker runner: extends the base runner image with a Docker daemon
# so CI jobs can run `docker build`. Built FROM the runner image (BASE_IMAGE) to
# keep setup_runner.py and the conda env as the single source of truth.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER root
ENV DEBIAN_FRONTEND=noninteractive

# Docker engine (dockerd + CLI) for in-task Docker-in-Docker.
RUN apt-get update && apt-get install -y --no-install-recommends \
        docker.io \
    && rm -rf /var/lib/apt/lists/*

# Let the non-root runner user reach the Docker socket.
RUN groupadd -f docker && usermod -aG docker runneruser

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
