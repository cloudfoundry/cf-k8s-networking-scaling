#!/bin/bash

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "${DIR}/lib.sh"

main() {
  if [[ "${#}" != "1" ]]; then
    echo "You must path to the experiment folder with runs!"
    exit 1
  fi

  local path="${1}"
  local run_dirs=$(find_runs ${path} | sort -n)
  if [[ "${#run_dirs}" == 0 ]]; then
    echo "No run dirs, aborting"
    exit 1
  fi

  local csv_files=$(find_csv_files_with_timestamps ${run_dirs[0]})
  for f in ${csv_files}; do
    setup_headers ${f} > "${path}/$(basename ${f})"
  done

  for dir in ${run_dirs[@]}; do
    local files=$(find_csv_files_with_timestamps ${dir})
    local start_stamp=$(find_start_time ${dir})
    if [ -z "${start_stamp}" ]; then
      echo "start time for is empty for run $(basename ${run_dir})"
      exit 1
    fi

    local runID=$(echo ${dir} | grep -Po "\d+$")

    for f in ${files}; do
      echo "Processing run ${runID} - $(basename ${f})"
      append_runid ${f} ${start_stamp} ${runID} >> "${path}/$(basename ${f})"
      # combine ${f} ${start_stamp} ${runID}
    done
  done

  # cp "${DIR}/../combine/templates/index.html" "${path}/index.html"
}

main "${@}"
