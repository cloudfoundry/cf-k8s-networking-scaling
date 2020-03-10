#!/bin/bash

source ../scripts/utils.sh

rm -f prometheus_errors.txt

kubectl port-forward -n monitoring service/prometheus-k8s :9090 > promprotforwarding.log & # so that we can reach the Prometheus Query API
sleep 5 # wait for port-forward
PROMETHEUS_LOCALPORT=$(cat promprotforwarding.log | grep -P -o "127.0.0.1:\d+" | cut -d":" -f2)
wlog "forwarding Prometheus API to localhost:${PROMETHEUS_LOCALPORT}"
START=$(date +%s)
STEP=15

until [ $(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PROMETHEUS_LOCALPORT/graph) -eq 200 ]; do sleep 1; done


echo "Step size: $STEP"

queryprom ()
{
  data=$(curl -s -G \
    --data-urlencode "query=$@" \
    --data-urlencode "start=$START" \
    --data-urlencode "end=$END" \
    --data-urlencode "step=$STEP" \
    http://localhost:$PROMETHEUS_LOCALPORT/api/v1/query_range)

  printf "=========\nquery: $@\nstart: $START end: $END step: $STEP\nresult: $data\n" >> prometheus_errors.txt

  if [ -z "$data" ]; then
    printf "Blank, trying again\n" >> prometheus_errors.txt
    data=$(queryprom "$@")
  fi

  echo $data
}

echo "timestamp,percent,nodename,type" > nodemon.csv
echo "timestamp,memory,podname" > gatewaystats.csv
echo "stamp,count,instance,pod" > envoyclusters.csv
echo "stamp,node,pod" > nodes4pods.csv
echo "stamp,number,route" > envoy_cluster_update_attempts.csv
echo "stamp,number,route" > envoy_cluster_update_successes.csv

while true
do
  echo "Querying prometheus"
  sleep 180
  END=$(date +%s)

  # CPU usage per node
  queryprom '(100 - (sum by (instance) (irate(node_cpu_seconds_total{mode="idle"}[24h])) * 12.5)) * on(instance) group_left(nodename) node_uname_info' |
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.nodename] + ["cpu"]) | @csv' >> nodemon.csv

  # Memory usage per node
  queryprom '100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)* on(instance) group_left(nodename) node_uname_info' |
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.nodename] + ["memory"]) | @csv' >> nodemon.csv

  # Gateway memory usage
  queryprom 'envoy_server_memory_allocated{job="gateway"}' | \
    jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.pod]) | @csv' >> gatewaystats.csv

  # Envoy clusters
  queryprom 'envoy_cluster_manager_active_clusters' | \
    jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1])]) + [.metric.node, .metric.pod]) | @csv' >> envoyclusters.csv

  # Mapping of nodes to pods
  echo "stamp,node,pod" > nodes4pods.csv
  queryprom 'sum(node_namespace_pod:kube_pod_info:) by (node, pod)' | \
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber)]) + [.metric.node, .metric.pod]) | @csv' >> nodes4pods.csv

  queryprom 'envoy_cluster_update_attempt{envoy_cluster_name=~"service_.*"}' | \
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber)]) + [.metric.envoy_cluster_name]) | @csv' >> envoy_cluster_update_attempts.csv

  queryprom 'envoy_cluster_update_success{envoy_cluster_name=~"service_.*"}' | \
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber)]) + [.metric.envoy_cluster_name]) | @csv' >> envoy_cluster_update_successes.csv

  echo "Prometheus data collected"
  START=$END
done

