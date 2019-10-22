#!/bin/bash

set -ex

CLUSTER_NAME=scalexperiment

CLUSTER_VERSION=latest
NUM_NODES=5
MACHINE_TYPE=n1-standard-4

ISTIO_VERSION=1.3.3

gcloud container clusters create $CLUSTER_NAME \
  --cluster-version $CLUSTER_VERSION \
  --num-nodes $NUM_NODES \
  --machine-type=$MACHINE_TYPE \
  --zone us-central1-f \
  --project cf-routing-desserts

gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone us-central1-f \
    --project cf-routing-desserts

kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account)

kubectl create namespace istio-system

curl -L https://git.io/getLatestIstio | sh -

pushd istio-$ISTIO_VERSION
  helm template install/kubernetes/helm/istio-init --name istio-init --namespace istio-system | kubectl apply -f -

  until [ $(kubectl get crds | grep -c 'istio.io') -ge "23" ]; do true; done

  helm template install/kubernetes/helm/istio \
    --name istio --namespace istio-system | kubectl apply -f -

  kubectl wait --for=condition=available --timeout=600s -n istio-system \
    deployments/istio-citadel deployments/istio-galley deployments/istio-ingressgateway deployments/istio-pilot \
    deployments/istio-policy deployments/istio-sidecar-injector deployments/istio-telemetry deployments/prometheus
popd

