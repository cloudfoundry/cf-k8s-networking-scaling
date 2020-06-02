#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

PATH_TO_VALUES_TPL=$(pwd)/../istio-operator-values.yaml
PATH_TO_VALUES=$(pwd)/values.yaml

kubetpl render ${PATH_TO_VALUES_TPL} \
  -s ENABLE_GALLEY=${ENABLE_GALLEY} \
  -s ENABLE_MTLS=${ENABLE_MTLS} \
  -s ENABLE_TELEMETRY=${ENABLE_TELEMETRY} \
  -s PILOT_REPLICAS=${PILOT_REPLICAS} \
  -s GATEWAY_REPLICAS=${GATEWAY_REPLICAS} \
  -s GALLEY_REPLICAS=${GALLEY_REPLICAS} \
  > ${PATH_TO_VALUES}

pushd $ISTIO_FOLDER
  bin/istioctl manifest apply -f ${PATH_TO_VALUES}
  kubectl label namespace default istio-injection=enabled --overwrite=true
popd

