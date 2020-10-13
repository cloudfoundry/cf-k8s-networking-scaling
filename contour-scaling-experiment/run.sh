#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source $DIR/vars.sh
source $DIR/scripts/utils.sh

CLUSTER_NAME=$1

COUNT=${2:-3}

# make sure we always have current builds of rust programs
pushd $DIR/combine
  cargo build
popd

pushd $DIR/interpret
  cargo build
popd

for ((i=0;i<$COUNT;i++)); do
  filename="$1-$i"
  mkdir $filename

  cp $DIR/vars.sh $DIR/$filename/

  pushd $DIR/$filename
    time ../scripts/experiment.sh $1-$i 2>&1 | tee experiment.log
  popd

  # if [[ $i < $(expr $COUNT - 1) ]]; then
  #   ../shared/scripts/pause.sh 600 # sleep for 10min to give the other cluster time to get out of the way
  # fi
done

mkdir $DIR/$1
mv $DIR/$1-* $DIR/$1

pushd $DIR/$1
  $DIR/combine/target/debug/combine .
  Rscript $DIR/graphManyToo.R
popd

mv $DIR/$1 experiments/
