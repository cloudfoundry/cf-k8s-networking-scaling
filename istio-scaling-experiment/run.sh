#!/bin/bash

source vars.sh
source scripts/utils.sh

# check dependencies
if [[ "$(helm version | grep -Po "(v\d)(?=\.\d\.\d)")" != "v3" ]]; then
  wlog "Istio experiment requires Helm >=v3. Please download or upgrade your Helm"
  exit 1
fi

if grep -vq "${ISTIO_FOLDER}" <<< "${PATH}"; then
  export PATH="${ISTIO_FOLDER}/bin:${PATH}"
fi

CLUSTER_NAME=$1

COUNT=${2:-3}

# make sure we always have current builds of rust programs
pushd combine
  cargo build
popd

pushd interpret
  cargo build
popd

pushd jaegerscrapper
  make
popd

# trap "exit" INT TERM ERR
# trap "kill 0" EXIT

for ((i=0;i<$COUNT;i++)); do
  filename="$1-$i"
  mkdir $filename

  cp vars.sh $filename/
  # if [ "$ISTIO_USE_OPERATOR" -eq 1 ]; then
  #   cp istio-operator-values.yaml $filename/values.yaml
  # else
  #   cp values.yaml $filename/
  # fi

  pushd $filename

    time ../scripts/experiment.sh $1-$i 2>&1 | tee experiment.log

  popd

  if [[ $i < $(expr $COUNT - 1) ]]; then
    sleep 600 # sleep for 10min to give the other cluster time to get out of the way
  fi
done

mkdir $1
mv $1-* $1/

pushd $1
  ./../combine/target/debug/combine .
  Rscript ../graphManyToo.R
popd

mv $1 experiments/

# pushd experiments/$1
#   ruby ../../minmax.rb
# popd
