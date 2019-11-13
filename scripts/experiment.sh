#!/bin/bash

# set -ex

source ../vars.sh
source ../scripts/utils.sh

CLUSTER_NAME=$1


echo "stamp,event" > importanttimes.csv

./../scripts/build-cluster.sh $CLUSTER_NAME

if ["$ISTIO_TAINT" -eq 1]; then
  nodes=$(kubectl get nodes | awk 'NR > 1 {print $1}' | head -n10)
  kubectl taint nodes $nodes scalers.istio=dedicated:NoSchedule
  kubectl label nodes $nodes scalers.istio=dedicated
fi

./../scripts/install-istio.sh

# use httpbin instead of bookinfo to apply load to
kubetpl render ../yaml/httpbin.yaml -s NAME=httpbin-loadtest | kubectl apply -f -
kubetpl render ../yaml/httpbin-gateway-wildcard-host.yaml -s NAME=httpbin-loadtest | kubectl apply -f -
kubetpl render ../yaml/httpbin-virtualservice-wildcard-host.yaml -s NAME=httpbin-loadtest | kubectl apply -f -
kubectl wait --for=condition=available deployment $(kubectl get deployments | grep httpbin | awk '{print $1}')

export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

wlog "Curling to see if load test container is up"
until [ $(curl -s -o /dev/null -w "%{http_code}" http://$GATEWAY_URL/anything) -eq 200 ]; do
  export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
  export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
  export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
  sleep 1
done
wlog "Load container up"
sleep 10

iwlog "GENERATE DP LOAD"

echo "stamp,node,pod" > nodes4pods.csv
slow_forever nodes4pods >> nodes4pods.csv &

echo "stamp,cpuid,usr,nice,sys,iowate,irq,soft,steal,guest,gnice,idle" > cpustats.csv
forever cpustats >> cpustats.csv &

echo "stamp,down,up" > ifstats.csv
forever ifstats >> ifstats.csv &

echo "stamp,total,used,free,shared,buff,available" > memstats.csv
forever memstats  >> memstats.csv &

echo "stamp,podname,event" > default_pods.log
echo "stamp,podname,event" > istio_pods.log
echo "stamp,podname,event" > system_pods.log
forever monpods default >> default_pods.log 2>&1 &
forever monpods istio-system >> istio_pods.log 2>&1 &
forever monpods kube-system >> system_pods.log 2>&1 &

echo "stamp,count" > howmanypilots.csv
forever howmanypilots >> howmanypilots.csv &

until [ $(curl -s -o /dev/null -w "%{http_code}" http://$GATEWAY_URL/anything) -eq 200 ]; do true; done
sleep 10

./../scripts/nodemon.sh > nodemon.csv &
./../scripts/sidecarstats.sh istio-system ingressgateway > gatewaystats.csv &

# create data plane load with apib
./../scripts/dataload.sh http://${GATEWAY_URL}/anything > dataload.csv 2>&1 &

sleep 120 # idle cluster, very few pods

iwlog "GENERATE TEST PODS"
# for ((n=0;n<$NUM_APPS;n++))
# do
#   kubetpl render ../yaml/httpbin.yaml -s NAME=httpbin-$n | kubectl apply -f -
# done
kubectl apply -f ../yaml/namespace/namespaced1k.yaml

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
# make extra sure they quit
kill -9 $(jobs -p)

# collate and graph in the background
./../interpret/target/debug/interpret user.log && Rscript ../graph.R &

wlog "=== TEARDOWN ===="

gcloud -q container clusters delete $CLUSTER_NAME --zone $AVAILABILITY_ZONE --async

exit
