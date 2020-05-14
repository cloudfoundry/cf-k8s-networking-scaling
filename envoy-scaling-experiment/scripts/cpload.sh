#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh
source ../scripts/progressbar.sh

mkdir -p curlstuff

main() {
  local navigator_port="${1}"
  local last_route="${2}"
  local half_routes="${3}"

  echo "stamp,route,status,startstamp"

  let num_users_minus_one="${NUM_USERS} - 1"
  for (( i = 0; i < ${NUM_USERS}; i++ )); do
    draw_progress_bar "${i}" "${num_users_minus_one}" "users" >&2
    let half_plus_one="$half_routes + $i"
    routes1="$(seq -s',' 0 $i)"
    routes2="$(seq -s',' $half_plus_one $last_route )"
    routes="$routes1,$routes2"
    # echo "Half: $half_routes" >&2
    # echo "${routes1}::${routes2}" >&2
    ./../scripts/user.sh "${i}" ${navigator_port} "${routes}"  &
    sleep $USER_DELAY
  done

  echo
  wlog "finish creating routes, waiting for poll to finish" >&2
  wait
  wlog "done waiting for poll" >&2
}

main "${@}"
