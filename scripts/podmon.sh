#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

echo "timestamp,namespace,podname,cpu,memory"

while true; do
  sleep 15 &
  kubectl top pods --all-namespaces --no-headers=true | awk '{print $1","$2","$3","$4}' | xargs -I {} echo "$(udate),{}"
  wait
done

