#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/../vars.sh

# produce test pods!
group_size=$((NUM_APPS / NUM_GROUPS))

kubetpl render ${DIR}/../yaml/rollout/gateway.yaml  \
  -s NAMESPACE=default

for ((group = 0 ; group < $NUM_GROUPS ; group++)); do
  kubetpl render ${DIR}/../yaml/sidecar.yaml  \
    -s NAME=group-$group \
    -s NAMESPACE=default \
    -s GROUP=$group

  for ((count = 0; count < $group_size; count++)); do
    export NAME=app-$count-g$group NAMESPACE=default GROUP=$group

    if [[ "${SCENARIO}" == "rolling" ]]; then
      ${DIR}/../yaml/rollout/generate.sh
    elif [[ "${SCENARIO}" == "blue-green" ]]; then
      ${DIR}/../yaml/blue-green/generate.sh
    elif [[ "${SCENARIO}" == "mixed" ]]; then
      let cond="$group % 2"
      if [[ $cond == 0 ]]; then
        ${DIR}/../yaml/rollout/generate.sh
      else
        ${DIR}/../yaml/blue-green/generate.sh
      fi
    fi
  done
done





