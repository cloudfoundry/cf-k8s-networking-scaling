#!/bin/bash

set -eo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

TRACK=${1}

kubetpl render -s NAME=${NAME} -s NAMESPACE=${NAMESPACE} -s GROUP=${GROUP} -s TRACK=${TRACK} \
  ${DIR}/service.yaml
