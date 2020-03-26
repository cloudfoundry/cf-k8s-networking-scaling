#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

PATH_TO_VALUES=$(pwd)/../istio-operator-values.yaml

pushd $ISTIO_FOLDER
  kubectl apply -f install/kubernetes/helm/helm-service-account.yaml
  helm init --service-account tiller --wait

  bin/istioctl manifest apply -f $PATH_TO_VALUES
  kubectl label namespace default istio-injection=enabled --overwrite=true

  helm install --name node-exporter stable/prometheus-node-exporter
popd

