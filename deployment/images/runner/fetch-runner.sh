#!/bin/sh

RUNNER_VERSION=${RUNNER_VERSION:-2.330.0}
RUNNER_ARCH=${RUNNER_ARCH:-osx-arm64}
RUNNER_CHECKSUM=${RUNNER_CHECKSUM:-e7515e45f6de15e37e6f1667bb2f962fb535a86689af1f9b219860300d06de1b}

mkdir actions-runner && cd actions-runner
curl -o actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz
echo "${RUNNER_CHECKSUM}  actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" | shasum -a 256 -c
tar xzf ./actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz