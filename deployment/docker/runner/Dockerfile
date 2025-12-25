FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV AWS_SDK_LOAD_CONFIG=true
ENV RUNNER_VERSION=2.330.0
ENV RUNNER_ARCH=linux-arm64
ENV RUNNER_CHECKSUM=5d13b77d4f8c8d432e590ff75c4f299c9590c3835fa744c2e2c36e5c6d4ea63e

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    ca-certificates \
    libicu70 \
    && rm -rf /var/lib/apt/lists/*

# Copy Kaniko executor from official multi-arch image
COPY --from=gcr.io/kaniko-project/executor:latest /kaniko/executor /usr/local/bin/executor

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

# Create runner directory
WORKDIR /runner

# Copy scripts
COPY setup-runner.py /runner/setup-runner.py
COPY fetch-runner.sh /runner/fetch-runner.sh
RUN chmod +x /runner/setup-runner.py /runner/fetch-runner.sh

CMD ["python3", "/runner/setup-runner.py"]