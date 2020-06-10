#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh
mkdir -p curlstuff

poll() {
  local user="${1}"
  local url="${user}.example.com"
  local start="$(udate)"

  local status=0

  while [[ "${status}" != "200" ]]; do
    status="$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/health 2>> curlstuff/route-${user}.log)"
    sleep ${USER_POLL_DELAY}
    echo "$(udate),${user},${status},${start}"
  done
}

user() {
  local user="${1}"
  local navigator_port="${2}"
  local routes="${3}"

  set_routes "${navigator_port}" "${routes}" 2>&1 > curlstuff/navigator-${user}.log
  poll "${user}"
}

user "${@}"
