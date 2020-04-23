#!/bin/bash

set -u

find_runs() {
  local path=${1}
  find ${path} -maxdepth 1 -type d | grep -Ev "^${path}$" # dont include current folder
}

find_csv_files_with_timestamps() {
  local run_dir=${1}

  local csv_files=$(find ${run_dir} -name "*.csv")
  for file in ${csv_files}; do
    has_headers=$(head -1 $file | grep -i stamp)
    if [ -n ${has_headers} ]; then
      echo ${file}
    fi
  done
}

setup_headers() {
  local csv_file=${1}
  local headers=$(head -n1 ${csv_file})
  echo "runID,${headers}"
}

find_start_time() {
  local run_dir=${1}
  local first_event=$(head -2 "${1}/importanttimes.csv" | tail -1) # read second line of importanttimes.csv
  if [[ -z ${first_event} ]]; then
    echo "importanttimes.csv is empty for run $(basename ${run_dir})"
    return 1
  fi
  echo ${first_event} | parse_stamp
}

append_runid() {
  local csv_file=${1}
  local start_time=${2}
  local runID=${3}

  set +e
  tail -n+2 ${csv_file} | awk \
    'BEGIN {
      FS = ","
    };

      $1 < '${start_time}' { EARLY=1 } { print "'${runID}',"$0 };

    END {
      if (EARLY)
        exit 1
    }'

  if [[ "$?" != 0 ]]; then
    echo "Warning: timestamp in ${csv_file} is less than the start time" >&2
  fi

  set -e
}

parse_stamp() {
  awk 'BEGIN { FS = "," }; { print $1 }' # separte by "," and read the first field, (FS stands for Field Separator)
}

ms_to_ns() {
  local csv_file=${1}

  awk 'BEGIN { FS = ","; OFS = "," }; $1 == "stamp" { print $0; next } { $1=$1"000000"; print $0 }' ${csv_file}
}
