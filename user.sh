#!/bin/bash

source ../vars.sh
source ../utils.sh

wlog "I am user $1 and I exist!"

kubectl apply -f ../yaml/httpbin-gateway.yaml
kubectl apply -f ../yaml/httpbin-virtualservice.yaml

until [ $(curl -s -o /dev/null -w "%{http_code}" -HHost:httpbin.example.com http://$INGRESS_HOST:$INGRESS_PORT/status/200) -eq 200 ]; do true; done

wlog "Got a success!"
