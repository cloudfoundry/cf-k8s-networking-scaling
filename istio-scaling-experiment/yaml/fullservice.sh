#!/bin/bash

kubetpl render -s NAME=$1 httpbin.yaml service.yaml gateway.yaml virtualservice.yaml | kubectl apply -f -

