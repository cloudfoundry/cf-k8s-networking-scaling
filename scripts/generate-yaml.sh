#!/bin/bash

source ../vars.sh

# produce test pods!
group_size=$((NUM_APPS / NUM_GROUPS))

if [ "$NAMESPACES" = "1" ]; then
  kubetpl render ../yaml/namespace-sidecar.yaml \
    -s NAMESPACE=istio-system \
    -s NAME=default \
    -s HOST='./*'

  for ((group = 0 ; group <= $NUM_GROUPS ; group++)); do
    kubetpl render ../yaml/namespace.yaml -s NAMESPACE=ns-$group
    for ((count = 0; count <= $group_size; count++)); do
      kubetpl render ../yaml/httpbin.yaml \
        -s NAME=httpbin-$count-g$group \
        -s GROUP=$group \
        -s NAMESPACE=ns-$group

      # kubetpl render ../yaml/service.yaml \
      #   -s NAME=httpbin-$count-g$group \
      #   -s GROUP=$group \
      #   -s NAMESPACE=ns-$group
    done
  done
else # namespaces off
  for ((group = 0 ; group <= $NUM_GROUPS ; group++)); do
    kubetpl render ../yaml/sidecar.yaml \
      -s NAME=group-$group \
      -s NAMESPACE=default \
      -s GROUP=$group
    for ((count = 0; count <= $group_size; count++)); do
      kubetpl render ../yaml/httpbin.yaml ../yaml/service.yaml \
        -s NAME=httpbin-$count-g$group \
        -s NAMESPACE=default \
        -s GROUP=$group
    done
  done
fi

