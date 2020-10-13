#!/bin/bash

# set -ex

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source ${DIR}/../vars.sh
source ${DIR}/utils.sh

CLUSTER_NAME=$1

echo "stamp,event" > importanttimes.csv

${DIR}/build-cluster.sh $CLUSTER_NAME

# TODO make contour envoys land on their own nodes
# taint nodes for pilot and ingress-gateways
# if [ $NODES_FOR_ISTIO -gt 0 ]; then
#   nodes=$(kubectl get nodes -l 'scalers.istio != prometheus' | awk 'NR > 1 {print $1}' | head -n$NODES_FOR_ISTIO)
#   if [ "$ISTIO_TAINT" -eq 1 ]; then
#     kubectl taint nodes $nodes scalers.istio=dedicated:NoSchedule
#   fi
#   kubectl label nodes $nodes scalers.istio=dedicated
# fi

# taint a node for the dataplane pod
datanode=$(kubectl get nodes -l 'scalers.istio notin (prometheus,dedicated)'| awk 'NR > 1 {print $1}' | tail -n2 | head -n1)
kubectl taint nodes $datanode scalers.dataplane=httpbin:NoSchedule
kubectl label nodes $datanode scalers.dataplane=httpbin

# TODO deploy prometheus
# we create a separate node pool for Prometheus with taints and labels in "build-cluster.sh"
# prometheusnode=$(kubectl get nodes -l "scalers.istio=prometheus")

wlog "=== Deploying Contour ==="
# replcae envoy DaemonSet with Deployment and set desired amount of replicas
curl -sSL https://projectcontour.io/quickstart/contour.yaml | sed '/DaemonSet/,/---/{s/^spec:/spec:\n  replicas: '${ENVOY_REPLICAS}'/};{s/DaemonSet/Deployment/}' | kubectl apply -f - --validate=false


# TODO do we need helm?
# helm repo add stable https://kubernetes-charts.storage.googleapis.com/
# helm repo update
# helm install node-exporter stable/prometheus-node-exporter

# schedule the dataplane pod
kubetpl render ${DIR}/../yaml/service.yaml ${DIR}/../yaml/httpbin-loadtest.yaml -s NAME=httpbin-loadtest | kubectl apply -f -
kubectl wait --for=condition=available deployment $(kubectl get deployments | grep httpbin | awk '{print $1}')
kubectl wait --for=condition=podscheduled pods $(kubectl get pods -ojsonpath='{range $.items[*]}{@.metadata.name}{"\n"}{end}' | grep httpbin)

# curl -s -H"Host:httpbin-loadtest.example.com" http://104.155.162.193:80/anything -v
wlog "Curling to see if load test container is up"
export INGRESS_HOST=$(kubectl -n projectcontour get service envoy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n projectcontour get service envoy -o jsonpath='{.spec.ports[?(@.name=="http")].port}')
export SECURE_INGRESS_PORT=$(kubectl -n projectcontour get service envoy -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
until [ $(curl -s -o /dev/null -w "%{http_code}" -H"Host: httpbin-loadtest.example.com" http://$GATEWAY_URL/anything) -eq 200 ]; do
  export INGRESS_HOST=$(kubectl -n projectcontour get service envoy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  export INGRESS_PORT=$(kubectl -n projectcontour get service envoy -o jsonpath='{.spec.ports[?(@.name=="http")].port}')
  export SECURE_INGRESS_PORT=$(kubectl -n projectcontour get service envoy -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
  export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
  sleep 1
done
wlog "Load container up"
${DIR}/../../shared/scripts/pause.sh 10

# TODO Enable debug XDS logging for Envoy
# kubectl get pods -n projectcontour -l app=envoy -ojsonpath='{range .items[*]}{.metadata.name} {end}' | xargs -n 1 -d ' ' -I {} kubectl exec -n projectcontour {} -c envoy \
#   -- curl -sS http://localhost:15000/logging?config=debug -X POST


# TODO collect prometheus data if we think it's needed
# ${DIR}/prometheus_data.sh &
echo "stamp,event,message" > endpoint_arrival_log.csv
ruby ${DIR}/endpoint_arrival.rb >> endpoint_arrival_log.csv &

iwlog "GENERATE DP LOAD"
echo "stamp,cpuid,usr,nice,sys,iowate,irq,soft,steal,guest,gnice,idle" > cpustats.csv
forever cpustats >> cpustats.csv &
echo "stamp,down,up" > ifstats.csv
forever ifstats >> ifstats.csv &
echo "stamp,total,used,free,shared,buff,available" > memstats.csv
forever memstats  >> memstats.csv &
echo "stamp,sockets" > time_wait.csv
forever time_wait  >> time_wait.csv &
until [ $(curl -s -o /dev/null -w "%{http_code}" -H"Host: httpbin-loadtest.example.com" http://$GATEWAY_URL/anything) -eq 200 ]; do true; done
${DIR}/../../shared/scripts/pause.sh 10 # wait because otherwise the dataload sometimes fails to work at first

# create data plane load with apib
${DIR}/dataload.sh http://${GATEWAY_URL}/anything > dataload.csv 2>&1 &

podsalive &

iwlog "GENERATE TEST PODS"
${DIR}/generate.sh > testpods.yaml
kubectl apply -f testpods.yaml

# wait for all httpbins to be ready
kubectl wait --for=condition=available deployment $(kubectl get deployments | grep app | awk '{print $1}')
kubectl wait --for=condition=podscheduled pods $(kubectl get pods -ojsonpath='{range $.items[*]}{@.metadata.name}{"\n"}{end}' | grep app)
${DIR}/../../shared/scripts/pause.sh 30 # wait for cluster to not be in a weird state after pushing so many pods
         # and get data for cluster without CP load or configuration as control

iwlog "GENERATE CP LOAD"
${DIR}/userfactory.sh > user.log # 2>&1 # run in foreground for now so we wait til they're done

iwlog "CP LOAD COMPLETE"

${DIR}/../../shared/scripts/pause.sh 600 # wait for cluster to level out after CP load, gather data for cluster without
         # CP load but with lots of configuration

# stop monitors
kill $(jobs -p)

iwlog "TEST COMPLETE"

# dump the list of nodes with their labels, only gotta do this once
kubectl get nodes --show-labels | awk '{print $1","$2","$6}' > nodeswithlabels.csv
# kubectl get pods -o wide -n istio-system | awk '{print $1","$6","$7}' > instance2pod.csv

${DIR}/../../shared/scripts/pause.sh 2 # let them quit


# collect pilot logs
# wlog "collecting Pilot logs, this might take a while"
# gcloud beta logging read 'resource.type="k8s_container"
# resource.labels.cluster_name="'"${CLUSTER_NAME}"'"
# resource.labels.namespace_name="istio-system"
# resource.labels.pod_name=~"istiod"' --format json > istiod.logs

# make extra sure they quit
kill -9 $(jobs -p)

# collate and graph
${DIR}/../interpret/target/debug/interpret user.log && Rscript ${DIR}/../graph.R

wlog "=== TEARDOWN ===="

# ${DIR}/../../shared/scripts/pause.sh # let them quit
${DIR}/../../shared/scripts/destroy-cluster.sh $CLUSTER_NAME

exit
