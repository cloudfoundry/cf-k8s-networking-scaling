#!/bin/bash

touch "$2"
while true; do
  kubectl logs -f $1 >> "$2"
done
