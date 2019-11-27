#!/bin/bash

start=$1

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

sleep 5 # let the portforward start working

INGRESS_IP=$(kubectl get svc -n istio-system istio-ingressgateway | awk 'NR>1 {print $4}')
START=$1
END=$(date +%s)

queryprom ()
{
  shift

  curl -s -G \
    --data-urlencode "query=$@" \
    --data-urlencode "start=$START" \
    --data-urlencode "end=$END" \
    --data-urlencode "step=15" \
    http://$INGRESS_IP:15030/api/v1/query_range
}


echo "Querying prometheus"

# CPU usage per node
queryprom $start 'sum (rate (container_cpu_usage_seconds_total[1m])) by (instance) / sum (machine_cpu_cores) by (instance) * 100' | \
  jq -r '["timestamp", "cpupercent", "nodename"], (.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.instance]) | @csv' > nodemon.csv

# Number of pilots
queryprom $start "sum(pilot_info)" | \
  jq -r '["stamp", "count"], (.data.result[] | .values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) | @csv' > howmanypilots.csv

# Gateway memory usage
queryprom $start 'envoy_server_memory_allocated{app="istio-ingressgateway"}' | \
  jq -r '["timestamp","memory","podname"], (.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.pod_name]) | @csv' > gatewaystats.csv

# Sidecar memory usage
queryprom $start 'envoy_server_memory_allocated{app=~"httpbin.*"}' | \
  jq -r '["timestamp","memory","podname"], (.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.pod_name]) | @csv' > sidecarstats.csv

# Proxy convergence
queryprom $start "pilot_proxy_convergence_time_bucket" | \
  jq -r '["timestamp","value","bucket"], (.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber), (.[1]|tonumber)]) + [.metric.le]) | @csv' > proxy_convergence.csv

# Mapping of nodes to pods
queryprom $start 'sum(container_tasks_state{pod_name!=""}) by (instance,pod_name)' | \
   jq -r '["stamp","node","pod"], (.data.result[] | (.values[] | [((.[0]|tostring) + "000000000"|tonumber)]) + [.metric.instance, .metric.pod_name]) | @csv' > nodes4pods.csv

echo "Prometheus data collected"
