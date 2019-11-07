#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

echo "timestamp,nodename,cpucores,cpupercent,memory,memorypercent"

while true; do
  sleep 15 &
  kubectl top node --no-headers=true | awk '{print $1","$2","$3","$4","$5}' | xargs -I {} echo "$(udate),{}"
  wait
done

