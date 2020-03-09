#!/bin/bash

# set -ex

# Prometheus
kubectl create -f ../yaml/kube-prometheus/manifests/setup
until kubectl get servicemonitors --all-namespaces ; do date; sleep 1; echo ""; done
kubectl create -f ../yaml/kube-prometheus/manifests/

# Jaeger, Navigator, Envoy
kubetpl render ../yaml/jaeger-all-in-one-template.yml ../yaml/navigator.yaml  ../yaml/gateway.yaml | kubectl apply -n system -f -

# wait until ready
kubectl wait --for=condition=podscheduled -n system pods --all

# add Gateway to Prometheus targets
kubectl apply -f ../yaml/gateway-service-monitor.yaml

until [[ "$(kubectl -n system get services gateway -ojsonpath='{.status.loadBalancer.ingress[0].ip}')" != "" ]]; do
  sleep 5
done

