FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV AWS_SDK_LOAD_CONFIG=true
ENV RUNNER_VERSION=2.330.0
ENV RUNNER_ARCH=linux-arm64
ENV RUNNER_CHECKSUM=9cb43527912086c7c8fb4119cb06409fcbcbd6f93a2d8507f30b07c495620f5c

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    ca-certificates \
    libicu70 \
    unzip \
    buildah \
    fuse-overlayfs \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# Copy kimia executor from official multi-arch image
COPY --from=ghcr.io/rapidfort/kimia:latest /usr/local/bin/kimia /usr/local/bin/kimia

# Install miniforge (conda-forge based, no ToS issues)
RUN wget --quiet https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && \
    rm /tmp/miniforge.sh && \
    /opt/conda/bin/conda clean -afy

# Add conda to PATH
ENV PATH="/opt/conda/bin:${PATH}"

# Copy environment.yml and create conda environment
COPY environment.yml /runner/environment.yml
RUN conda env create -f /runner/environment.yml && \
    conda clean -afy

# Activate environment by default
ENV CONDA_DEFAULT_ENV=runner
ENV PATH="/opt/conda/envs/runner/bin:${PATH}"

# Create runner directory and non-root user
RUN useradd -m -d /runner runneruser && \
    mkdir -p /runner && \
    chown -R runneruser:runneruser /runner

# Configure subuid and subgid for rootless buildah
RUN echo "runneruser:100000:65536" > /etc/subuid && \
    echo "runneruser:100000:65536" > /etc/subgid

# Configure buildah for rootless operation
RUN mkdir -p /etc/containers && \
    echo '[storage]' > /etc/containers/storage.conf && \
    echo 'driver = "vfs"' >> /etc/containers/storage.conf && \
    echo '[storage.options]' >> /etc/containers/storage.conf && \
    echo '[storage.options.vfs]' >> /etc/containers/storage.conf

# Set buildah isolation mode environment variable
ENV BUILDAH_ISOLATION=chroot
WORKDIR /runner

# Copy scripts
COPY setup-runner.py /runner/setup-runner.py
COPY fetch-runner.sh /runner/fetch-runner.sh
RUN chmod +x /runner/setup-runner.py /runner/fetch-runner.sh && \
    chown runneruser:runneruser /runner/setup-runner.py /runner/fetch-runner.sh

# Switch to non-root user
USER runneruser

CMD ["python3", "/runner/setup-runner.py"]