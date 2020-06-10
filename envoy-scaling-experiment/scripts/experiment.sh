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
# taint nodes for pilot and ingress-gateways
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

../scripts/prometheus_data.sh &

echo "stamp,cpuid,usr,nice,sys,iowate,irq,soft,steal,guest,gnice,idle" > cpustats.csv
forever cpustats >> cpustats.csv &
echo "stamp,down,up" > ifstats.csv
forever ifstats >> ifstats.csv &
echo "stamp,total,used,free,shared,buff,available" > memstats.csv
forever memstats  >> memstats.csv &
echo "stamp,sockets" > time_wait.csv
forever time_wait  >> time_wait.csv &

podsalive &

iwlog "GENERATE TEST PODS"
./../scripts/generate-yaml.sh > testpods.yaml
kubectl apply -f testpods.yaml

# wait for all httpbins to be scheduled
kubectl wait --for=condition=podscheduled pods $(kubectl get pods | grep httpbin | awk '{print $1}')

sleep 30 # wait for cluster to not be in a weird state after pushing so many pods
         # and get data for cluster without CP load or configuration as control


# ensure port 8081 is free before forwarding to it
kubectl port-forward -n system service/navigator :8081 > portforward.log & # so that we can reach the Navigator API
sleep 5 # wait for port-forward
navigator_addr="localhost:"$(cat portforward.log | grep -P -o "127.0.0.1:\d+" | cut -d":" -f2)
wlog "forwarding Navigator API to ${navigator_addr}"


wlog "configurating the last of the routes"
let last_route="$NUM_APPS - 1"
let half_routes="$NUM_APPS / 2"

wlog "waiting for Envoy to be ready"
mkdir -p curlstuff
url="$last_route.example.com"
status=$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/health 2>> curlstuff/route-$last_route.log)
while [ "$status" != "404" ]; do
  status=$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/health 2>> curlstuff/route-$last_route.log)
  sleep 1
done

set_routes "${navigator_addr}" "$(seq -s',' $half_routes $last_route)" # precreate second half

# wait for a known-configured route to work
url="$last_route.example.com"
status=$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/health 2>> curlstuff/route-$last_route.log)
while [ "$status" != "200" ]; do
  status=$(curl -sS -w "%{http_code}" -H "Host:${url}" http://$INGRESS_IP:80/health 2>> curlstuff/route-$last_route.log)
  sleep 1
done

wlog "the last half of routes is ready, sleeping for 30 seconds"
sleep 30 # so we can see that setup worked on the graphs

echo "stamp,status" > envoy_requests.csv
ADMIN_ADDR="${INGRESS_IP}:15000" ruby ./../scripts/endpoint_arrival.rb >> envoy_requests.csv &

iwlog "GENERATE CP LOAD"

./../scripts/cpload.sh "${navigator_addr}" "${last_route}" "${half_routes}" > route-status.csv
# ../scripts/pause.sh
iwlog "CP LOAD COMPLETE"

sleep 10

JAEGER_QUERY_IP=$(kubectl -n system get services jaeger-query -ojsonpath='{.status.loadBalancer.ingress[0].ip}')
./../jaegerscrapper/bin/scrapper -csvPath ./jaeger.csv -jaegerQueryAddr $JAEGER_QUERY_IP --operationName createSnapshot --service navigator
./../jaegerscrapper/bin/scrapper -csvPath ./sendconfigjaeger.csv -jaegerQueryAddr $JAEGER_QUERY_IP --operationName sendConfig --service navigator
./../jaegerscrapper/bin/scrapper -csvPath ./envoy_ondiscoveryresponse.csv -jaegerQueryAddr $JAEGER_QUERY_IP --operationName "GrpcMuxImpl::onDiscoveryResponse" --service ingressgateway
./../jaegerscrapper/bin/scrapper -csvPath ./envoy_pause.csv -jaegerQueryAddr $JAEGER_QUERY_IP --operationName "pause" --service ingressgateway
./../jaegerscrapper/bin/scrapper -csvPath ./envoy_eds_update.csv -jaegerQueryAddr $JAEGER_QUERY_IP --operationName "EdsClusterImpl::onConfigUpdate" --service ingressgateway
./../jaegerscrapper/bin/scrapper -csvPath ./envoy_senddiscoveryrequest.csv -jaegerQueryAddr $JAEGER_QUERY_IP --operationName "GrpcMuxImpl::sendDiscoveryRequest" --service ingressgateway

sleep 10 # wait for cluster to level out after CP load, gather data for cluster without
          # CP load but with lots of configuration

# stop monitors
kill $(jobs -p)

iwlog "TEST COMPLETE"

sleep 2 # let them quit

# make extra sure they quit
kill -9 $(jobs -p)

cp ./../templates/index.html-onerun ./index.html # TODO template in vars.sh contents
Rscript ../graph.R
Rscript ../graph_scratch.R

wlog "=== TEARDOWN ===="

# sleep 10000
./../scripts/destroy-cluster.sh "$CLUSTER_NAME"

exit
