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
    wlog "Started loop"
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
        wlog "UNREADINESS EVENT"
        wlog "EVENT $podname $(echo "$pods" | jq ".items[] | .status.containerStatuses[] | .state.waiting.reason")"
        wlog "JSON $pods"
        wlog "DESCRIBE $(kubectl describe pod -n istio-system $podname)"
    fi
}
