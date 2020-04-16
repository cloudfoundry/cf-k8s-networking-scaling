#!/bin/bash

udate ()
{
  date +%s%N
}

pst_time ()
{
  TZ=America/Los_Angeles date +%H:%M:%S
}

wlog ()
{
  echo "$(pst_time) $1"
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

set_routes()
{
  navigator_port="${1}"
  response_code=$(curl -sS -XPOST http://localhost:${navigator_port}/set-routes -d "{\"numbers\":[$2]}" --write-out '%{http_code}' -o /tmp/navigator_output)
  if [[ "${response_code}" != "200" ]]; then
    echo "Navigator returned ${response_code}"
    cat /tmp/navigator_output
    echo
  fi
}

wait_for_pods() {
  local n="${1}"
  shift
  local pods=("${@}")
  let chunk_size="${#pods[@]} / ${n}"
  let chunks_num="$((${n} - 1))"

  for i in $(seq 0 ${chunks_num}); do
    let start="${i} * ${chunk_size}"
    let end="${start} + ${chunk_size}"
    local selector="app in ($(echo "${pods[@]:$start:$end}" | tr ' ' ','))"
    kubectl wait --for=condition=podscheduled pods -l "${selector}" &
  done

  wait
}
