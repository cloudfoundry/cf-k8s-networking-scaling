#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

echo "$(udate),$1,STARTED"

if ["$NAMESPACES" = "1"]; then
  kubetpl render ../yaml/namespace/httpbin-gateway.yaml -s NAME=httpbin-0-$1 -s NAMESPACE=ns-0 | kubectl apply -f -
  kubetpl render ../yaml/namespace/httpbin-virtualservice.yaml -s NAME=httpbin-0-$1 -s NAMESPACE=ns-0 | kubectl apply -f -
else
  kubetpl render ../yaml/httpbin-gateway.yaml -s NAME=httpbin-$1 -s NAMESPACE=default | kubectl apply -f -
  kubetpl render ../yaml/httpbin-virtualservice.yaml -s NAME=httpbin-$1 -s NAMESPACE=default | kubectl apply -f -
fi

until [ $(curl -s -o /dev/null -w "%{http_code}" -HHost:httpbin-0-$1.example.com http://$INGRESS_HOST:$INGRESS_PORT/status/200) -eq 200 ]; do true; done

echo "$(udate),$1,SUCCESS"

lastfail=$(udate)
for ((i=60; i>0; i--)); do
  sleep 1 &
  if [ $(curl -s -o /dev/null -w "%{http_code}" -HHost:httpbin-0-$1.example.com http://$INGRESS_HOST:$INGRESS_PORT/status/200) -ne 200 ]; then
    lastfail=$(udate)
  fi
  wait
done

echo "$lastfail,$1,COMPLETED"

