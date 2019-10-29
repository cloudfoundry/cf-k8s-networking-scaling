#!/bin/bash

source ../scripts/utils.sh

apib -T https://astandke.com

while True; do
  apib -N $(udate) -c 10 -d 5 -S $1
done
