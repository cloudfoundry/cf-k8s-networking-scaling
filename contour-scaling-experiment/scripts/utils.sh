#!/bin/bash

udate ()
{
  date +%s%N
}

wlog ()
{
  echo "$(udate) $1"
}

iwlog ()
{
  echo "$(udate),$1" >> importanttimes.csv
  wlog "====== $1 ======"
}

forever ()
{
    while true; do
        $@;
        sleep 0.5;
    done
}

podsalive ()
{
  echo "stamp,unscheduledpods"
  while true; do
    echo "$(udate),$(kubectl get pods --all-namespaces | grep httpbin | grep -v Running | wc -l)" >> podalive.csv
    sleep 1;
  done
}

cpustats ()
{
  mpstat -P ON 1 1 | grep -v CPU | awk '/Average/ {$1=systime(); print $1 "000000000," $2 "," $3 "," $4 "," $5 "," $6 "," $7 "," $8 "," $9 "," $10 "," $11 "," $12}'
}

memstats ()
{
  free -m | awk '/Mem/ {$1=systime(); print $1 "000000000," $2 "," $3 "," $4 "," $5 "," $6 "," $7}'
}

ifstats ()
{
  ifstat -q -t -n -i ens4 1 1 | awk 'NR > 2 {$1=systime(); print $1 "000000000," $2 "," $3}'
}

time_wait ()
{
  netstat -on | grep TIME_WAIT | wc | awk '{$10=systime(); print $10 "0000000000," $1}'
}

port_forward()
{
  namespace="$1"
  resource="$2"
  resource_port="$3"

  t="$(mktemp)"
  kubectl port-forward -n "${namespace}" "${resource}" :"${resource_port}" > ${t} 2>/dev/null &
  sleep 2
  local_port=$(grep -P -o "127.0.0.1:\d+" < ${t} | cut -d":" -f2)
  echo "${local_port}"
}
