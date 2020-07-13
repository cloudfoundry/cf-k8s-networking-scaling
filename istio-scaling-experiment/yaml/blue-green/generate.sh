#!/bin/bash

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

kubetpl render -s NAME="${NAME}-blue" -s HOSTNAME="${NAME}-blue" -s NAMESPACE=${NAMESPACE} -s GROUP=${GROUP} -s REPLICAS=${REPLICAS} \
  ${DIR}/service.yaml \
  ${DIR}/virtualservice.yaml \
  ${DIR}/whoami.yaml

kubetpl render -s NAME="${NAME}-green" -s HOSTNAME="${NAME}-green" -s NAMESPACE=${NAMESPACE} -s GROUP=${GROUP} -s REPLICAS=${REPLICAS} \
  ${DIR}/service.yaml \
  ${DIR}/whoami.yaml
