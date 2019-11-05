#!/bin/bash

source vars.sh
source scripts/utils.sh

CLUSTER_NAME=$1

COUNT=${2:-1}

trap "exit" INT TERM ERR
trap "kill 0" EXIT

for ((i=0;i<$COUNT;i++)); do
  filename="$1-$i"
  mkdir $filename

  cp vars.sh $filename/

  pushd $filename

    time ../scripts/experiment.sh $1-$i 2>&1 | tee experiment.log

  popd
done

mkdir $1
mv $1-* $1/

pushd $1
  ./../combine/target/debug/combine .
  Rscript ../graphManyToo.R
popd
