#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/../../vars.sh

# produce test pods!
group_size=$((NUM_APPS / NUM_GROUPS))

kubetpl render ${DIR}/../../yaml/rollout/gateway.yaml  \
  -s NAMESPACE=default

for ((group = 0 ; group < $NUM_GROUPS ; group++)); do
  kubetpl render ${DIR}/../../yaml/sidecar.yaml  \
    -s NAME=group-$group \
    -s NAMESPACE=default \
    -s GROUP=$group

  for ((count = 0; count < $group_size; count++)); do
    NAME=app-$count-g$group NAMESPACE=default GROUP=$group ${DIR}/../../yaml/blue-green/generate.sh
  done
done





