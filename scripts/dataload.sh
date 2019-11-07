#!/bin/bash

source ../scripts/utils.sh
source ../vars.sh

apib -T https://astandke.com

echo "latency" > rawlatencies.txt

while true; do
  apib -N $(udate) -c $DATAPLANE_NUM_CONNECTIONS -d 5 -S $1
done
