#!/bin/bash

# set -ex

kubetpl render ../yaml/jaeger-all-in-one-template.yml ../yaml/navigator.yaml  ../yaml/gateway.yaml | kubectl apply -n system -f -

# wait until ready
kubectl wait --for=condition=podscheduled -n system pods --all

until [[ "$(kubectl -n system get services gateway -ojsonpath='{.status.loadBalancer.ingress[0].ip}')" != "" ]]; do
  sleep 5
done

