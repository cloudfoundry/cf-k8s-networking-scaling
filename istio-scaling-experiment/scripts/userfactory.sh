#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source $DIR/../vars.sh
source $DIR/utils.sh
source ${DIR}/../../shared/scripts/progressbar.sh

mkdir -p curlstuff
echo "stamp,usernum,groupnum,event,status,logfile"

let group_size="${NUM_USERS} / ${NUM_GROUPS}"
let num_users_minus_one="${NUM_USERS} - 1"

for ((group = 0 ; group < $NUM_GROUPS ; group++)); do
  for ((count = 0; count < $group_size; count++)); do
    let i="$group * $group_size + $count"
    draw_progress_bar "${i}" "${num_users_minus_one}" "users" >&2

    $DIR/user.sh $count $group &
    sleep $USER_DELAY
  done
done

>&2 wlog "user factory closing"
wait
>&2 wlog "user factory done waiting"
