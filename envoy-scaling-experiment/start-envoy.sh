/usr/local/bin/envoy \
  -c "/etc/envoy/config/envoy-bootstrap.yaml" \
  --service-cluster \
  ingressgateway \
  --service-node \
  "$POD_NAME" \
  --restart-epoch \
  "0" \
  --drain-time-s \
  "45" \
  --parent-shutdown-time-s \
  "60" \
  --max-obj-name-len \
  "189" \
  --local-address-ip-version \
  "v4" \
  --log-format \
  "[Envoy (Epoch 0)] [%Y-%m-%d %T.%e][%t][%l][%n] %v" \
  -l \
  "warning" \
  --component-log-level \
  "misc:error"
