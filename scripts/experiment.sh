#!/bin/bash

# set -ex

source ../vars.sh
source ../scripts/utils.sh

CLUSTER_NAME=$1

forever cpustats > cpustats.log &
ifstat -t -n -i ens4 -b > networkstats.log &
forever memstats  >> memstats.log &

echo "event,stamp" > importanttimes.csv

./../scripts/build-cluster.sh $CLUSTER_NAME
./../scripts/install-istio.sh

export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

echo "stamp,podname,event" > default_pods.log
echo "stamp,podname,event" > istio_pods.log
echo "stamp,podname,event" > system_pods.log
forever monpods default >> default_pods.log 2>&1 &
forever monpods istio-system >> istio_pods.log 2>&1 &
forever monpods kube-system >> system_pods.log 2>&1 &

echo "stamp,count" > howmanypilots.csv
forever howmanypilots >> howmanypilots.csv &

iwlog "GENERATE DP LOAD"
./../scripts/sidecarstats.sh istio-system ingressgateway > gatewaystats.csv &

# create data plane load with apib
./../scripts/dataload.sh http://${GATEWAY_URL}/productpage > dataload.csv 2>&1 &

sleep 60 # idle cluster, very few pods

iwlog "GENERATE TEST PODS"
for ((n=0;n<$NUM_USERS;n++))
do
  kubetpl render ../yaml/httpbin.yaml -s NAME=httpbin-$n | kubectl apply -f -
done

# wait for all httpbins to be ready
kubectl wait --for=condition=available deployment $(kubectl get deployments | grep httpbin | awk '{print $1}')

iwlog "START MONITORING SIDECARS"

./../scripts/sidecarstats.sh default httpbin > sidecarstats.csv &

sleep 60 # idle cluster, many pods

iwlog "GENERATE CP LOAD"
./../scripts/userfactory.sh > user.log 2>&1 # run in foreground for now so we wait til they're done

iwlog "CP LOAD COMPLETE"

sleep 60 # idle cluster with lots of services floatin' around

# stop monitors
kill $(jobs -p)

iwlog "TEST COMPLETE"

sleep 2 # let them quit

# go/rust run collate program
./../interpret/target/debug/interpret user.log

# generate graphs with r
Rscript ../graph.R

wlog "=== TEARDOWN ===="

gcloud -q container clusters delete $CLUSTER_NAME --zone us-central1-f --async

wait
