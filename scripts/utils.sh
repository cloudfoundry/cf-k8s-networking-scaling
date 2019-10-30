#!/bin/bash

udate ()
{
  date -u +%s
}

wlog ()
{
  echo "$(udate) $1"
}

iwlog ()
{
  echo "$1,$(udate)" >> importanttimes.csv
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
