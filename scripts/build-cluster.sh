#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

CLUSTER_NAME=$1

gcloud container clusters create $CLUSTER_NAME \
  --cluster-version $CLUSTER_VERSION \
  --num-nodes $NUM_NODES \
  --machine-type=$MACHINE_TYPE \
  --zone $AVAILABILITY_ZONE \
  --enable-ip-alias \
  # --create-subnetwork name=$CLUSTER_NAME-network,range=10.5.0.0/16 \
  # --cluster-ipv4-cidr=10.0.0.0/14 \
  # --services-ipv4-cidr=10.4.0.0/16 \
  --project cf-routing-desserts

gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone $AVAILABILITY_ZONE \
    --project cf-routing-desserts

kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account)

kubectl create namespace istio-system

helm repo add istio.io https://storage.googleapis.com/istio-release/releases/$ISTIO_VERSION/charts/
