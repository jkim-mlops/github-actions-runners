FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV AWS_SDK_LOAD_CONFIG=true
ENV RUNNER_VERSION=2.330.0
ENV RUNNER_ARCH=linux-x64
ENV RUNNER_CHECKSUM=1f3e2f97e4e4e2e4d6f8f8c6c6d6e4e4f6f8f8c6c6d6e4e4f6f8f8c6c6d6e4e4

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    openssl \
    ca-certificates \
    libicu70 \
    && rm -rf /var/lib/apt/lists/*

# Install Kaniko
RUN wget -O /usr/local/bin/executor https://github.com/GoogleContainerTools/kaniko/releases/latest/download/executor-amd64 && \
    chmod +x /usr/local/bin/executor

# Install miniconda
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && \
    rm /tmp/miniconda.sh && \
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
COPY gh-jwt.py /runner/gh-jwt.py
COPY fetch-runner.sh /runner/fetch-runner.sh
RUN chmod +x /runner/gh-jwt.py /runner/fetch-runner.sh

CMD ["python3", "/runner/gh-jwt.py"]