#!/bin/bash

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
      number: 15030
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
  - "*"
  gateways:
  - prometheus-gateway
  http:
  - match:
    - port: 15030
    route:
    - destination:
        host: prometheus
        port:
          number: 9090
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: prometheus
  namespace: istio-system
spec:
  host: prometheus
  trafficPolicy:
    tls:
      mode: DISABLE
---
EOF

rm prometheus_errors.txt

INGRESS_IP=$(kubectl get svc -n istio-system istio-ingressgateway | awk 'NR>1 {print $4}')
START=$(date +%s)
STEP=15

until [ $(curl -s -o /dev/null -w "%{http_code}" http://$INGRESS_IP:15030/graph) -eq 200 ]; do sleep 1; done

echo $INGRESS_IP

echo "Step size: $STEP"

queryprom ()
{
  data=$(curl -s -G \
    --data-urlencode "query=$@" \
    --data-urlencode "start=$START" \
    --data-urlencode "end=$END" \
    --data-urlencode "step=$STEP" \
    http://$INGRESS_IP:15030/api/v1/query_range)

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
echo "stamp,node,pod" > nodes4pods.csv


while true
do
  echo "Querying prometheus"
  sleep 30

  END=$(date +%s)

  # CPU usage per node
  queryprom '(100 - (sum by (instance) (irate(node_cpu_seconds_total{mode="idle"}[24h])) * 12.5)) * on(instance) group_left(nodename) node_uname_info' |
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.nodename] + ["cpu"]) | @csv' >> nodemon.csv

  # Memory usage per node
  queryprom '100 - (node_memory_MemFree_bytes / node_memory_MemTotal_bytes * 100)* on(instance) group_left(nodename) node_uname_info' |
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.nodename] + ["memory"]) | @csv' >> nodemon.csv

  # Number of pilots
  queryprom "sum(pilot_info)" | \
    jq -r '(.data.result[] | .values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) | @csv' >> howmanypilots.csv

  # Gateway memory usage
  queryprom 'envoy_server_memory_allocated{app="istio-ingressgateway"}' | \
    jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.pod_name]) | @csv' >> gatewaystats.csv

  # Sidecar memory usage (sample 20 sidecars)
  for ((i=1;i<=20;i++));
  do
    app=$(kubectl get deployments --all-namespaces | sort -R | head -n1 | awk '{print $2}')
    queryprom "envoy_server_memory_allocated{app=\"$app\"}" | \
      jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.pod_name]) | @csv' >> sidecarstats.csv
  done

  # Proxy convergence
  queryprom "histogram_quantile(0.68, sum(rate(pilot_proxy_convergence_time_bucket[1m])) by (le))" | \
     jq -r '(.data.result[] | .values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) | @csv' >> 68convergence.csv

  queryprom "histogram_quantile(0.90, sum(rate(pilot_proxy_convergence_time_bucket[1m])) by (le))" | \
     jq -r '(.data.result[] | .values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) | @csv' >> 90convergence.csv

  queryprom "histogram_quantile(0.99, sum(rate(pilot_proxy_convergence_time_bucket[1m])) by (le))" | \
     jq -r '(.data.result[] | .values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) | @csv' >> 99convergence.csv

  queryprom "histogram_quantile(1, sum(rate(pilot_proxy_convergence_time_bucket[1m])) by (le))" | \
     jq -r '(.data.result[] | .values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) | @csv' >> 100convergence.csv

  # Envoy clusters
  queryprom 'envoy_cluster_manager_active_clusters' | \
    jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1])]) + [.metric.instance, .metric.app]) | @csv' >> envoyclusters.csv

  # Mapping of nodes to pods
  queryprom 'sum(container_tasks_state{pod_name!=""}) by (instance,pod_name)' | \
     jq -r '(.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber)]) + [.metric.instance, .metric.pod_name]) | @csv' >> nodes4pods.csv

  echo "Prometheus data collected"
  START=$END
done

