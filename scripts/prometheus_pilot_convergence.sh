#!/bin/bash

1>&2 1>/dev/null kubectl port-forward -n istio-system service/prometheus 9090 &
KPF_PID=$!
sleep 2 # let the portforward start working

JSON=$(2>/dev/null curl 'http://localhost:9090/api/v1/query?query=pilot_proxy_convergence_time_bucket[24h]')
echo "$JSON" | jq -r '["bucket", "timestamp", "value"], (.data.result[] | [.metric.le] + .values[]) | @csv'


kill $KPF_PID # gotta clean up
