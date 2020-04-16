#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh
source ../scripts/progressbar.sh

mkdir -p curlstuff

poll() {
  local user="${1}"
  local url="${user}.example.com"
  local start="$(udate)"

  local status=0

  while [[ "${status}" != "200" ]]; do
    status="$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/status/200 2>> curlstuff/route-${user}.log)"
    echo "$(udate),${user},${status},${start}"
  done
}

user() {
  local user="${1}"
  local navigator_port="${2}"
  local routes="${3}"
  set_routes "${2}" "$(seq -s',' 0 $i),$(seq -s',' $(($half_routes + $i)) $last_route)"
  poll "${i}"
}

main() {
  local navigator_port="${1}"
  local last_route="${2}"
  local half_routes="${3}"

  echo "stamp,route,status,startstamp"

  let num_users_minus_one="${NUM_USERS} - 1"
  for (( i = 0; i < ${NUM_USERS}; i++ )); do
    draw_progress_bar "${i}" "${num_users_minus_one}" "users" >&2
    user "${i}" "${navigator_port}" "$(seq -s',' 0 $i),$(seq -s',' $(($half_routes + $i)) $last_route)" &
    sleep $USER_DELAY
  done

  echo
  wlog "finish creating routes, waiting for poll to finish" >&2
  wait
  wlog "done waiting for poll" >&2
}

main "${@}"
