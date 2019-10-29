#!/bin/bash

# set -ex

source ../vars.sh
source ../scripts/utils.sh

CLUSTER_NAME=$1

echo "event,stamp" > importanttimes.csv

./../scripts/build-cluster.sh $CLUSTER_NAME
./../scripts/install-istio.sh

export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

iwlog "POD MONITORING"

forever monpods default > default_pods.log 2>&1 &
forever monpods istio-system > istio_pods.log 2>&1 &
forever monpods kube-system > system_pods.log 2>&1 &

./../scripts/sidecarstats.sh > sidecarstats.csv &
./../scripts/gatewaystats.sh > gatewaystats.csv &

sleep 10

iwlog "GENERATE TEST PODS"
for ((n=0;n<$NUM_USERS;n++))
do
  kubetpl render ../yaml/httpbin.yaml -s NAME=httpbin-$n | kubectl apply -f -
done

# wait for all httpbins to be ready
kubectl wait --for=condition=available deployment $(kubectl get deployments | grep httpbin | awk '{print $1}')

iwlog "GENERATE DP LOAD"

# create data plane load with apib
./../scripts/dataload.sh http://${GATEWAY_URL}/productpage > dataload.csv 2>&1 &

sleep 60 # data load against an idle cluster

iwlog "GENERATE CP LOAD"
./../scripts/userfactory.sh > user.log 2>&1 # run in foreground for now so we wait til they're done

iwlog "CP LOAD COMPLETE"

sleep 60

# stop monitors
kill $(jobs -p)

iwlog "COLLECT RESULTS"

sleep 2 # let them quit

# go/rust run collate program

wlog "Default Pod unreadiness event count: $(cat default_pods.log | grep "UNREADINESS EVENT" | wc -l)"
wlog "Istio Pod unreadiness event count: $(cat istio_pods.log | grep "UNREADINESS EVENT" | wc -l)"
wlog "System Pod unreadiness event count: $(cat system_pods.log | grep "UNREADINESS EVENT" | wc -l)"

wlog "=== TEARDOWN ===="

gcloud container clusters delete $CLUSTER_NAME --zone us-central1-f

wait
