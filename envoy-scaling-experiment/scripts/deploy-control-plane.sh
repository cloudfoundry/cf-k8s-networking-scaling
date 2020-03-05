#!/bin/bash

# set -ex

source ../vars.sh

kubetpl render ../yaml/navigator.yaml | kubectl apply -n system -f -

kubectl wait --for=condition=podscheduled -n system pods --all

# wait for service
sleep 15
