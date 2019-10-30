#!/bin/bash

source ../scripts/utils.sh

echo "timestamp,podname,memory,heap"

while true; do
  # dump envoy's memory and heap utilization
  for pod in $(kubectl get pods -n $1 --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep $2 | sort | head -n6); do
    echo "$(udate),$pod,$(kubectl exec -n $1 "$pod" -c istio-proxy -- pilot-agent request GET stats | yq '."server.memory_allocated",."server.memory_heap_size"' | awk -v ORS=, '{ print $1 }')" | sed 's/,$//' &
  done
  wait
done
