#!/bin/bash

source vars.sh
source scripts/utils.sh

EXPERIMENT_NAME=$1
CLUSTER_NAME=${EXPERIMENT_NAME}

COUNT=${2:-3}

# make sure we always have current builds
make navigator gateway
make combine combinev2
make ../shared

trap "exit" INT TERM ERR
trap "kill 0" EXIT

for ((i=0;i<$COUNT;i++)); do
  filename="$EXPERIMENT_NAME-$i"
  mkdir $filename

  cp vars.sh $filename/

  pushd $filename
    time ../scripts/experiment.sh $EXPERIMENT_NAME-$i 2>&1 | tee experiment.log
  popd

  if [[ $i < $(($COUNT - 1)) ]]; then
    sleep 600 # sleep for 10min to give the other cluster time to get out of the way
  fi
done

mkdir $EXPERIMENT_NAME
mv $EXPERIMENT_NAME-* $EXPERIMENT_NAME/

pushd $EXPERIMENT_NAME
  ./../combine/target/debug/combine . # for html files
  ./../combinev2/combine .
  Rscript ../graphMany.R
popd

mv $EXPERIMENT_NAME experiments/

