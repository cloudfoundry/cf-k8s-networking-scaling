#!/bin/bash

source vars.sh
source scripts/utils.sh

CLUSTER_NAME=$1

trap "exit" INT TERM ERR
trap "kill 0" EXIT

filename="$1-$(udate)"
mkdir $filename

cp vars.sh $filename/

pushd $filename

time ../scripts/experiment.sh $1 2>&1 | tee experiment.log

popd

