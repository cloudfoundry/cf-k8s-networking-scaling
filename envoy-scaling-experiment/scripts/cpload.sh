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
    ./../scripts/user.sh "${i}" "${navigator_port}" "$(seq -s',' 0 $i),$(seq -s',' $(($half_routes + $i)) $last_route)" &
    sleep $USER_DELAY
  done

  echo
  wlog "finish creating routes, waiting for poll to finish" >&2
  wait
  wlog "done waiting for poll" >&2
}

main "${@}"
