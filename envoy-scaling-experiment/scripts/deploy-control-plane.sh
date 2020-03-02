#!/bin/bash

# set -ex

source ../vars.sh

kubetpl render ../yaml/navigator.yaml | kubectl apply -n system -f -
