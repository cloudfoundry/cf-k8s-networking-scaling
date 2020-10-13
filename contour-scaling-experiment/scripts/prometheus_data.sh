#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo "Exposing prometheus for data collection"

# expose prometheus through istio's ingress gateway
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: prometheus-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http-prom
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: prometheus-vs
  namespace: istio-system
spec:
  hosts:
  - "prometheus.local"
  gateways:
  - prometheus-gateway
  http:
  - match:
    - port: 80
    route:
    - destination:
        host: prometheus
        port:
          number: 9090
---
EOF

rm -f prometheus_errors.txt

INGRESS_IP=$(kubectl get svc -n istio-system istio-ingressgateway | awk 'NR>1 {print $4}')
START=$(date +%s)
STEP=15

until [ $(curl -s -o /dev/null -w "%{http_code}" -H "Host: prometheus.local" http://$INGRESS_IP/graph) -eq 200 ]; do sleep 1; done

echo $INGRESS_IP

echo "Step size: $STEP"

queryprom ()
{
  data=$(curl -s -G \
    -H "Host: prometheus.local" \
    --data-urlencode "query=$@" \
    --data-urlencode "start=$START" \
    --data-urlencode "end=$END" \
    --data-urlencode "step=$STEP" \
    http://${INGRESS_IP}/api/v1/query_range)

  printf "=========\nquery: $@\nstart: $START end: $END step: $STEP\nresult: $data\n" >> prometheus_errors.txt

  if [ -z "$data" ]; then
    printf "Blank, trying again\n" >> prometheus_errors.txt
    data=$(queryprom "$@")
  fi

  echo $data
}

echo "timestamp,percent,nodename,type" > nodemon.csv
echo "stamp,count" > howmanypilots.csv
echo "timestamp,memory,podname" > gatewaystats.csv
echo "timestamp,memory,podname" > sidecarstats.csv
echo "stamp,count" > 68convergence.csv
echo "stamp,count" > 90convergence.csv
echo "stamp,count" > 99convergence.csv
echo "stamp,count" > 100convergence.csv
echo "stamp,count,instance,pod" > envoyclusters.csv
echo "stamp,count,instance" > pilot_xds.csv
echo "stamp,node,pod" > nodes4pods.csv
echo "stamp,count,passfail,instance,resource,version" > galley_validation.csv
echo "stamp,count,instance" > galley_runtime_psp.csv
echo "stamp,count,instance" > galley_runtime_strat.csv

while true
do
  echo "Querying prometheus"
  sleep 180

  END=$(date +%s)

  # CPU usage per node
  queryprom '(100 - (sum by (instance) (irate(node_cpu_seconds_total{mode="idle"}[24h])) * 12.5)) * on(instance) group_left(nodename) node_uname_info' |
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.nodename] + ["cpu"]) | @csv' >> nodemon.csv

  # Memory usage per node
  queryprom '100 - (node_memory_MemFree_bytes / node_memory_MemTotal_bytes * 100)* on(instance) group_left(nodename) node_uname_info' |
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.nodename] + ["memory"]) | @csv' >> nodemon.csv

  # Gateway memory usage
  queryprom 'envoy_server_memory_allocated{app="istio-ingressgateway"}' | \
    jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.pod_name]) | @csv' >> gatewaystats.csv

  # Envoy clusters
  queryprom 'envoy_cluster_manager_active_clusters' | \
    jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1])]) + [.metric.instance, .metric.app]) | @csv' >> envoyclusters.csv

  # Mapping of nodes to pods
  echo "stamp,node,pod" > nodes4pods.csv
  queryprom 'sum(container_tasks_state{pod_name!=""}) by (instance,pod_name)' | \
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber)]) + [.metric.instance, .metric.pod_name]) | @csv' >> nodes4pods.csv

  echo "Prometheus data collected"
  START=$END
done

