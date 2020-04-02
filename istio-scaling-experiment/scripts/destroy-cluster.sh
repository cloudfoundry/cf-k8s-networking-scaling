#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

CLUSTER_NAME=$1
AVAILABILITY_ZONE=$(gcloud compute instances list | grep "$(hostname) " | awk '{print $2}')

gcloud -q container clusters delete $CLUSTER_NAME --zone $AVAILABILITY_ZONE
