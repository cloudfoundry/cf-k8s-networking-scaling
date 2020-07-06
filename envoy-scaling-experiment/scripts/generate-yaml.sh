#!/bin/bash

source ../vars.sh

# produce test pods!
for ((count = 0; count < $NUM_APPS; count++)); do
  kubetpl render ../yaml/whoami.yaml \
    -s NAME=httpbin-$count \
    -s NAMESPACE=default
done
