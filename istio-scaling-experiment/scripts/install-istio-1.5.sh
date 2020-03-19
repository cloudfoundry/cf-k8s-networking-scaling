#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

PATH_TO_VALUES=$(pwd)/../istio-operator-values.yaml

pushd $ISTIO_FOLDER
  bin/istioctl manifest apply -f $PATH_TO_VALUES
  kubectl label namespace default istio-injection=enabled --overwrite=true
popd

