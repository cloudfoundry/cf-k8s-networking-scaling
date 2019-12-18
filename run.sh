#!/bin/bash

source vars.sh
source scripts/utils.sh

CLUSTER_NAME=$1

COUNT=${2:-3}

# make sure we always have current builds of rust programs
pushd combine
  cargo build
popd

pushd interpret
  cargo build
popd

trap "exit" INT TERM ERR
trap "kill 0" EXIT

for ((i=0;i<$COUNT;i++)); do
  filename="$1-$i"
  mkdir $filename

  cp vars.sh $filename/
  cp values.yaml $filename/

  pushd $filename

    time ../scripts/experiment.sh $1-$i 2>&1 | tee experiment.log

  popd

  sleep 600 # sleep for 10min to give the other cluster time to get out of the way
done

mkdir $1
mv $1-* $1/

pushd $1
  ./../combine/target/debug/combine .
  Rscript ../graphManyToo.R
popd

mv $1 experiments/
