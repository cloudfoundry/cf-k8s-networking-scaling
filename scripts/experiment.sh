#!/bin/bash

# set -ex

source ../vars.sh
source ../scripts/utils.sh

CLUSTER_NAME=$1

echo "stamp,event" > importanttimes.csv

./../scripts/build-cluster.sh $CLUSTER_NAME

# taint nodes for pilot and ingress-gateways
if [ $NODES_FOR_ISTIO -gt 0 ]; then
  nodes=$(kubectl get nodes | awk 'NR > 1 {print $1}' | head -n$NODES_FOR_ISTIO)
  if [ "$ISTIO_TAINT" -eq 1 ]; then
    kubectl taint nodes $nodes scalers.istio=dedicated:NoSchedule
  fi
  kubectl label nodes $nodes scalers.istio=dedicated
fi

# taint a node for the dataplane pod
nodes=$(kubectl get nodes | awk 'NR > 1 {print $1}' | tail -n1)
kubectl taint nodes $nodes scalers.dataplane=httpbin:NoSchedule
kubectl label nodes $nodes scalers.dataplane=httpbin

./../scripts/install-istio.sh

# schedule the dataplane pod
kubetpl render ../yaml/service.yaml ../yaml/httpbin-loadtest.yaml -s NAME=httpbin-loadtest | kubectl apply -f -
kubectl wait --for=condition=available deployment $(kubectl get deployments | grep httpbin | awk '{print $1}')

wlog "Curling to see if load test container is up"
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
until [ $(curl -s -o /dev/null -w "%{http_code}" http://$GATEWAY_URL/anything) -eq 200 ]; do
  export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
  export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
  export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
  sleep 1
done
wlog "Load container up"
sleep 10

START=$(date +%s) # used for our prometheus queries later

iwlog "GENERATE DP LOAD"
echo "stamp,cpuid,usr,nice,sys,iowate,irq,soft,steal,guest,gnice,idle" > cpustats.csv
forever cpustats >> cpustats.csv &
echo "stamp,down,up" > ifstats.csv
forever ifstats >> ifstats.csv &
echo "stamp,total,used,free,shared,buff,available" > memstats.csv
forever memstats  >> memstats.csv &
until [ $(curl -s -o /dev/null -w "%{http_code}" http://$GATEWAY_URL/anything) -eq 200 ]; do true; done
sleep 10 # wait because otherwise the dataload sometimes fails to work at first

# create data plane load with apib
./../scripts/dataload.sh http://${GATEWAY_URL}/anything > dataload.csv 2>&1 &

iwlog "GENERATE TEST PODS"
./../scripts/generate-yaml.sh > testpods.yaml
kubectl apply -f testpods.yaml

# wait for all httpbins to be ready
kubectl wait --for=condition=available deployment $(kubectl get deployments | grep httpbin | awk '{print $1}')

sleep 30 # wait for cluster to not be in a weird state after pushing so many pods
         # and get data for cluster without CP load or configuration as control

iwlog "GENERATE CP LOAD"
./../scripts/userfactory.sh > user.log # 2>&1 # run in foreground for now so we wait til they're done

iwlog "CP LOAD COMPLETE"

sleep 30 # wait for cluster to level out after CP load, gather data for cluster without
         # CP load but with lots of configuration

# stop monitors
kill $(jobs -p)

iwlog "TEST COMPLETE"

../scripts/prometheus_data.sh $START

# dump the list of nodes with their labels, only gotta do this once
kubectl get nodes --show-labels | awk '{print $1","$2","$6}' > nodeswithlabels.csv

sleep 2 # let them quit
# make extra sure they quit
kill -9 $(jobs -p)

# collate and graph
./../interpret/target/debug/interpret user.log && Rscript ../graph.R

wlog "=== TEARDOWN ===="

gcloud -q container clusters delete $CLUSTER_NAME --zone $AVAILABILITY_ZONE --async

exit
