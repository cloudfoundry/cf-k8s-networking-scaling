#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source $DIR/utils.sh
source $DIR/../vars.sh

apib -T https://astandke.com

echo "latency" > rawlatencies.txt

while true; do
  apib -N $(udate) -c $DATAPLANE_NUM_CONNECTIONS -d 5 -S $1
done
