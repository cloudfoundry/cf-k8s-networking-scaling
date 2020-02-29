#!/bin/bash

# set -ex

source ../vars.sh

kubetpl -s NUM_APPS=$NUM_APPS -f ../yaml/navigator.yaml | kubectl -n system -f -
