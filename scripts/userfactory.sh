#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

for ((n=0;n<$NUM_USERS;n++))
do
  ./../scripts/user.sh $n &
  sleep $USER_DELAY
done

wait
