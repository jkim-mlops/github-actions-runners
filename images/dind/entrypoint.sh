#!/usr/bin/env bash
# Start the Docker daemon, then hand off to the runner as the non-root user.
# Runs as root (the task is privileged) so dockerd can set up cgroups/overlayfs.
set -euo pipefail

# Start the Docker daemon in the background. /var/lib/docker is an ECS host
# volume on the instance's real filesystem, so overlay2 works (not nested on
# the container's overlay rootfs).
dockerd >/var/log/dockerd.log 2>&1 &

# Wait for the daemon to accept connections; fail fast if it never comes up so
# the job errors clearly instead of hanging.
for attempt in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        break
    fi
    if [ "$attempt" -eq 30 ]; then
        echo "dockerd failed to start within 30s" >&2
        cat /var/log/dockerd.log >&2
        exit 1
    fi
    sleep 1
done

# Drop to the non-root runner user (in the docker group) and start the runner
# with the conda environment activated. Force bash: su defaults to /bin/sh
# (dash), where `source` doesn't exist.
exec su runneruser -s /bin/bash -c \
    'source /opt/conda/etc/profile.d/conda.sh && conda activate runner && exec python /runner/setup_runner.py'
