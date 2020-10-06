#!/bin/bash

# trap "exit" INT TERM
# trap "kill 0" EXIT

mkdir -p finished_experiment_vars

for filename in ./experiment_vars/*; do
  [ -e "$filename" ] || continue
  experiment=$(basename $filename)
  echo "Running: $experiment"
  cp $filename/* .
  ./run.sh "$experiment" 1
  status=$?
  [ $status -eq 0 ] && mv $filename finished_experiment_vars/$experiment
done
