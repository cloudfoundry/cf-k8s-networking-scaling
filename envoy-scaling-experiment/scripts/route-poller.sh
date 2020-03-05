#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

mkdir curlstuff
while true; do
  seq 0 $(($NUM_APPS - 1)) | xargs -n 1 -P0 -I {} bash -c '
    source ../scripts/utils.sh
    url="{}.example.com"
    status=$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/status/200 2>> curlstuff/route-{}.log)
    echo "$(udate),{},$status"
  '
  # for i in $(seq 0 $(($NUM_APPS - 1))); do
  #   url="$i.example.com"
  #   status=$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/status/200 2>> curlstuff/route-$i.log)
  #   echo "$(udate),$i,$status"
  # done
  sleep $USER_POLL_DELAY
done
