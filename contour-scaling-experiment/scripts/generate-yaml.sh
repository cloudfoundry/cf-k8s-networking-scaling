#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source $DIR/../vars.sh

# produce test pods!
group_size=$((NUM_APPS / NUM_GROUPS))
half=$((group_size / 2))

if [ "$NAMESPACES" = "1" ]; then
  kubetpl render $DIR/../yaml/namespace-sidecar.yaml \
    -s NAMESPACE=istio-system \
    -s NAME=default \
    -s HOST='./*'

  for ((group = 0 ; group < $NUM_GROUPS ; group++)); do
    kubetpl render $DIR/../yaml/namespace.yaml -s NAMESPACE=ns-$group
    for ((count = 0; count < $group_size; count++)); do
      kubetpl render $DIR/../yaml/httpbin.yaml $DIR/../yaml/service.yaml \
        -s NAME=httpbin-$count-g$group \
        -s GROUP=$group \
        -s NAMESPACE=ns-$group
    done
  done
else # namespaces off
  for ((group = 0 ; group < $NUM_GROUPS ; group++)); do
    kubetpl render $DIR/../yaml/sidecar.yaml \
      -s NAME=group-$group \
      -s NAMESPACE=default \
      -s GROUP=$group
    for ((count = 0; count < $group_size; count++)); do
      kubetpl render $DIR/../yaml/httpbin.yaml $DIR/../yaml/service.yaml \
        -s NAME=httpbin-$count-g$group \
        -s NAMESPACE=default \
        -s GROUP=$group

      if [ $count -ge $half ] && [ $STEADY_STATE -eq 1 ]; then
        kubetpl render $DIR/../yaml/gateway.yaml $DIR/../yaml/virtualservice.yaml \
          -s NAME=httpbin-$count-g$group \
          -s NAMESPACE=default
      fi
    done
  done
fi

