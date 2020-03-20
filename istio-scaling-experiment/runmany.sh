#!/bin/bash

for filename in ./experiment_vars/*; do
  [ -e "$filename" ] || continue
  experiment=$(basename $filename)
  echo "Running: $experiment"
  echo cp "$filename/*" .
  echo ./run.sh "$experiment"
done
