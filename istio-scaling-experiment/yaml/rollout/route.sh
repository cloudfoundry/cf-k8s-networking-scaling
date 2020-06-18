#!/bin/bash

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

VERSION=${1}

kubetpl render -s NAME=${NAME} -s NAMESPACE=${NAMESPACE} -s VERSION=${VERSION} \
  ${DIR}/service.yaml

