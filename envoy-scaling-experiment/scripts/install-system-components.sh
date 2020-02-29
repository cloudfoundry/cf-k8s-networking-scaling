#!/bin/bash

# set -ex

kubectl -n system -f ../yaml/jaeger-all-in-one-template.yml -f ../yaml/gateway.yaml
