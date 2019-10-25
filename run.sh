#!/bin/bash

source vars.sh
source utils.sh

CLUSTER_NAME=$1

trap "exit" INT TERM ERR
trap "kill 0" EXIT

# ====== UTILITIES =====

# rm -rf tmp
filename="$1-$(udate)"
mkdir $filename

cp vars.sh $filename/

pushd $filename

time ../experiment.sh $1 | tee experiment.log

popd
