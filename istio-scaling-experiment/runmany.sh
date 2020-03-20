#!/bin/bash

for filename in ./experiment_vars/*; do
  [ -e "$filename" ] || continue
  experiment=$(basename $filename)
  echo "Running: $experiment"
  cp $filename/* .
  ./run.sh "$experiment"
done
