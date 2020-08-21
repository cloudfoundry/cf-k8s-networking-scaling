#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source $DIR/../vars.sh
source $DIR/utils.sh

CLUSTER_NAME=$1
AVAILABILITY_ZONE=$(gcloud compute instances list | grep "$(hostname) " | awk '{print $2}')
AVAILABILITY_REGION=$(echo ${AVAILABILITY_ZONE} | cut -d- -f1,2)

gcloud container clusters create $CLUSTER_NAME \
  --cluster-version $CLUSTER_VERSION \
  --num-nodes $NUM_NODES \
  --machine-type=$MACHINE_TYPE \
  --zone=${AVAILABILITY_ZONE} \
  --enable-ip-alias
  # --create-subnetwork name=$CLUSTER_NAME-network,range=10.12.0.0/16 \
  # --cluster-ipv4-cidr=/14 \
  # --services-ipv4-cidr=/16

gcloud container node-pools create prometheus-pool \
  --cluster=$CLUSTER_NAME \
  --zone ${AVAILABILITY_ZONE} \
  --num-nodes=1 \
  --machine-type "e2-highmem-16" \
  --node-labels="scalers.istio=prometheus" \
  --node-taints="scalers.istio=prometheus:NoSchedule" \
  --metadata disable-legacy-endpoints=true \
  --no-enable-autoupgrade

gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone $AVAILABILITY_ZONE

wlog "Waiting for GKE cluster"
while true; do
  if [[ "$(gcloud container clusters list | grep ${CLUSTER_NAME} | awk '{print $8}')" == "RUNNING" \
    && "$(kubectl get nodes | tail +2 | wc -l)" > 0 \
    && "$(kubectl get nodes | tail +2 | awk '{print $2}' | grep -v 'Ready')" == ""
  ]]; then
    break
  fi

  echo "Still waiting..."
  sleep 10
done

kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account)

kubectl create namespace istio-system
