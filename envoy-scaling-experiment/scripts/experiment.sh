#!/bin/bash

# set -ex

source ../vars.sh
source ../scripts/utils.sh

CLUSTER_NAME=$1

if [ $STEADY_STATE != 1 ]; then
  wlog "Only steady-state load is supported at this time. Please set STEADY_STATE to 1."
  exit 1
fi

if [ $NUM_USERS -gt $(($NUM_APPS / 2)) ]; then
  wlog "For steady-state load, NUM_APPS ($NUM_APPS) must be double or more NUM_USERS ($NUM_USERS)."
  exit 1
fi

echo "stamp,event" > importanttimes.csv

./../scripts/build-cluster.sh $CLUSTER_NAME

# TODO
taint nodes for pilot and ingress-gateways
if [ $NODES_FOR_CP -gt 0 ]; then
  nodes=$(kubectl get nodes | awk 'NR > 1 {print $1}' | head -n$NODES_FOR_CP)
  kubectl taint nodes $nodes scalers.cp=dedicated:NoSchedule
  kubectl label nodes $nodes scalers.cp=dedicated
fi

# taint a node for the dataplane pod
# datanode=$(kubectl get nodes | awk 'NR > 1 {print $1}' | tail -n2 | head -n1)
# kubectl taint nodes $datanode scalers.dataplane=httpbin:NoSchedule
# kubectl label nodes $datanode scalers.dataplane=httpbin
# prometheusnode=$(kubectl get nodes | awk 'NR > 1 {print $1}' | tail -n1)
# kubectl taint nodes $prometheusnode scalers.istio=prometheus:NoSchedule
# kubectl label nodes $prometheusnode scalers.istio=prometheus

iwlog "Installing system components"
./../scripts/install-system-components.sh

export INGRESS_IP=$(kubectl -n system get services gateway -ojsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=80
echo "INGRESS: $INGRESS_IP:$INGRESS_PORT"

# TODO
# schedule the dataplane pod
# kubetpl render ../yaml/service.yaml ../yaml/httpbin-loadtest.yaml -s NAME=httpbin-loadtest | kubectl apply -f -
# kubectl wait --for=condition=available deployment $(kubectl get deployments | grep httpbin | awk '{print $1}')

# wlog "Curling to see if load test container is up"
# export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
# export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
# export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
# until [ $(curl -s -o /dev/null -w "%{http_code}" http://$GATEWAY_URL/anything) -eq 200 ]; do
#   export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#   export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
#   export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
#   export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
#   sleep 1
# done
# wlog "Load container up"
# sleep 10

../scripts/prometheus_data.sh &

echo "stamp,cpuid,usr,nice,sys,iowate,irq,soft,steal,guest,gnice,idle" > cpustats.csv
forever cpustats >> cpustats.csv &
echo "stamp,down,up" > ifstats.csv
forever ifstats >> ifstats.csv &
echo "stamp,total,used,free,shared,buff,available" > memstats.csv
forever memstats  >> memstats.csv &
echo "stamp,sockets" > time_wait.csv
forever time_wait  >> time_wait.csv &
# iwlog "GENERATE DP LOAD"
# until [ $(curl -s -o /dev/null -w "%{http_code}" http://$GATEWAY_URL/anything) -eq 200 ]; do true; done
# sleep 10 # wait because otherwise the dataload sometimes fails to work at first
# create data plane load with apib
# ./../scripts/dataload.sh http://${GATEWAY_URL}/anything > dataload.csv 2>&1 &

podsalive &

iwlog "GENERATE TEST PODS"
./../scripts/generate-yaml.sh > testpods.yaml
kubectl apply -f testpods.yaml

# wait for all httpbins to be scheduled
kubectl wait --for=condition=podscheduled pods $(kubectl get pods | grep httpbin | awk '{print $1}')

sleep 30 # wait for cluster to not be in a weird state after pushing so many pods
         # and get data for cluster without CP load or configuration as control

echo "stamp,route,status" > route-status.csv
./../scripts/route-poller.sh >> route-status.csv &

set_routes()
{
  response_code=$(curl -sS -XPOST http://localhost:${navigator_port}/set-routes -d "{\"numbers\":[$1]}" --write-out '%{http_code}' -o /tmp/navigator_output)
  if [[ "${response_code}" != "200" ]]; then
    echo "Navigator returned ${response_code}"
    cat /tmp/navigator_output
    echo
  fi
}

# ensure port 8081 is free before forwarding to it
kubectl port-forward -n system service/navigator :8081 > portforward.log & # so that we can reach the Navigator API
sleep 5 # wait for port-forward
navigator_port=$(cat portforward.log | grep -P -o "127.0.0.1:\d+" | cut -d":" -f2)
wlog "forwarding Navigator API to localhost:${navigator_port}"

LAST_ROUTE=$(($NUM_APPS - 1))
HALF_ROUTES=$(($NUM_APPS / 2))
set_routes "$(seq -s',' $HALF_ROUTES $LAST_ROUTE)" # precreate second half

# wait for a known-configured route to work
url="$LAST_ROUTE.example.com"
status=$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/status/200 2>> curlstuff/route-$LAST_ROUTE.log)
while [ "$status" != "200" ]; do
  status=$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/status/200 2>> curlstuff/route-$LAST_ROUTE.log)
done
sleep 30 # so we can see that setup worked on the graphs

ADMIN_ADDR="${INGRESS_IP}:15000" ruby ./../scripts/endpoint_arrival.rb &

iwlog "GENERATE CP LOAD"

for i in $(seq 0 $(($NUM_USERS - 1)) ); do
  wlog "creating route $i"
  set_routes "$(seq -s',' 0 $i),$(seq -s',' $(($HALF_ROUTES + $i)) $LAST_ROUTE)"
  sleep $USER_DELAY
done

iwlog "CP LOAD COMPLETE"

sleep 10

JAEGER_QUERY_IP=$(kubectl -n system get services jaeger-query -ojsonpath='{.status.loadBalancer.ingress[0].ip}')
./../jaegerscrapper/bin/scrapper -csvPath ./jaeger.csv -jaegerQueryAddr $JAEGER_QUERY_IP --operationName createSnapshot
./../jaegerscrapper/bin/scrapper -csvPath ./sendconfigjaeger.csv -jaegerQueryAddr $JAEGER_QUERY_IP --operationName sendConfig

sleep 600 # wait for cluster to level out after CP load, gather data for cluster without
          # CP load but with lots of configuration

# stop monitors
kill $(jobs -p)

iwlog "TEST COMPLETE"

sleep 2 # let them quit

# make extra sure they quit
kill -9 $(jobs -p)

cp ./../templates/index.html-onerun ./index.html # TODO template in vars.sh contents
Rscript ../graph.R

wlog "=== TEARDOWN ===="

./destroy-cluster.sh "$CLUSTER_NAME"

exit
