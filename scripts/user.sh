#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

echo "$(udate),$1,STARTED"
TARGET_URL=httpbin-$1.example.com

if [ "$NAMESPACES" = "1" ]; then
  TARGET_URL=httpbin-0-$1.example.com
  kubetpl render ../yaml/namespace/httpbin-gateway.yaml -s NAME=httpbin-0-$1 -s NAMESPACE=ns-0 | kubectl apply -f -
  kubetpl render ../yaml/namespace/httpbin-virtualservice.yaml -s NAME=httpbin-0-$1 -s NAMESPACE=ns-0 | kubectl apply -f -
else
  kubetpl render ../yaml/httpbin-gateway.yaml -s NAME=httpbin-$1 -s NAMESPACE=default | kubectl apply -f -
  kubetpl render ../yaml/httpbin-virtualservice.yaml -s NAME=httpbin-$1 -s NAMESPACE=default | kubectl apply -f -
fi

until [ $(curl -s -o /dev/null -w "%{http_code}" -HHost:$TARGET_URL http://$INGRESS_HOST:$INGRESS_PORT/status/200) -eq 200 ]; do true; done

echo "$(udate),$1,SUCCESS"
>&2 wlog "SUCCESS $1"

lastfail=$(udate)
secondsToWait=120
for ((i=$secondsToWait; i>0; i--)); do
  sleep 1 &
  if [ $(curl -s -o /dev/null -w "%{http_code}" -HHost:$TARGET_URL http://$INGRESS_HOST:$INGRESS_PORT/status/200) -ne 200 ]; then
    lastfail=$(udate)
    echo "$(udate),$1,FAILURE"
  fi
  wait
done

echo "$lastfail,$1,COMPLETED"
>&2 wlog "Completed $1"

