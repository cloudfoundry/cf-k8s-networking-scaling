#!/bin/bash

source ../vars.sh
source ../utils.sh

wlog "USER $1 STARTED"

kubetpl render ../yaml/httpbin-gateway.yaml -s NAME=httpbin-$1 | kubectl apply -f -
kubetpl render ../yaml/httpbin-virtualservice.yaml -s NAME=httpbin-$1 | kubectl apply -f -

until [ $(curl -s -o /dev/null -w "%{http_code}" -HHost:httpbin-$1.example.com http://$INGRESS_HOST:$INGRESS_PORT/status/200) -eq 200 ]; do true; done

wlog "USER $1 COMPLETED"
