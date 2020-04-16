#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

mkdir -p curlstuff

poll() {
  user="${1}"
  url="${user}.example.com"
  start="$(udate)"
  status=$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/status/200 2>> curlstuff/route-${user}.log)
  echo "$(udate),${user},${status},${start}"
}

poll_user() {
  while true; do
    sleep $USER_POLL_DELAY &
    poll "${1}"
    wait
  done
}

for (( i = 0; i < ${NUM_USERS}; i++)); do
  poll_user "${i}" &
done

wait

