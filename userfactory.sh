#!/bin/bash

source ../vars.sh
source ../utils.sh

for ((n=0;n<$NUM_USERS;n++))
do
  ./../user.sh $n &
  sleep $USER_DELAY
done
