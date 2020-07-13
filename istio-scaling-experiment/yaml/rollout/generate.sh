#!/bin/bash

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

kubetpl render -s NAME="${NAME}" -s NAMESPACE=${NAMESPACE} -s GROUP=${GROUP} -s REPLICAS=${REPLICAS} -s VERSION=v0 -s TARGET=live \
  ${DIR}/service.yaml \
  ${DIR}/virtualservice.yaml \
  ${DIR}/whoami.yaml

kubetpl render -s NAME="${NAME}" -s NAMESPACE=${NAMESPACE} -s GROUP=${GROUP} -s REPLICAS=${REPLICAS} -s VERSION=v1 -s TARGET=canary \
  ${DIR}/whoami.yaml

