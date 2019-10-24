#!/bin/bash

udate ()
{
  date -u +%s
}

wlog ()
{
  echo "$(udate): $1"
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
        wlog "Pod failure event!"
        wlog "$pods"
    fi
}
