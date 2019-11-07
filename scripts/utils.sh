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

monpods ()
{
    pods=$(kubectl get pods -n "$1" --field-selector="status.phase!=Running" -o json)
    if [ $(echo "$pods" | jq '.items | length') -ne 0 ]; then
        podname="$(echo "$pods" | jq -r '.items[0].metadata.name')"
        event="$(echo "$pods" | jq ".items[] | .status.containerStatuses[] | .state.waiting.reason" | awk -v ORS=, '{ print $1 }' | sed 's/,$//')"
        echo "$(udate),$podname,$event"
    fi
}

howmanypilots () {
  echo "$(udate),$(kubectl get pods -n istio-system | grep pilot | wc -l)"
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
