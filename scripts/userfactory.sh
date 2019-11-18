#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

echo "stamp,usernum,event"

for ((n=0;n<$NUM_USERS;n++))
do
  ./../scripts/user.sh $n &
  sleep $USER_DELAY
done

>&2 wlog "user factory closing"
wait
>&2 wlog "user factory done waiting"
