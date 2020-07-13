#!/bin/bash

set -ex

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

CLUSTER_NAME=$1
EXPERIMENT_FOLDER=$2

start_stamp="$(sed -n '2p' ${EXPERIMENT_FOLDER}/importanttimes.csv | awk -F, '{ print $1 }')"

pushd gke_logs > /dev/null
  gsutil -m rsync -r gs://scalerslogs .
  jq -jr 'select(.resource.labels.cluster_name == "'${CLUSTER_NAME}'") | "\(.resource.labels.pod_name) \(.timestamp) \(.textPayload)"' \
    $(grep -Rl ${CLUSTER_NAME} | tr '\0' '  ') > istio-logs.jsonl

  awk '{
    cmd = "date -d " $2 " +%s%N"
    while ( ( cmd | getline fmtDate) > 0 ) {
      $2 = (fmtDate - '${start_stamp}') / 1000 / 1000 / 1000
    }
    close(cmd);
    print $0
  }1' < istio-logs.jsonl > istio-logs-with-delta.log

popd
