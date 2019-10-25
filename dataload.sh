#!/bin/bash

source ../utils.sh

apib -T https://astandke.com

while True; do
  apib -N $(udate) -c 50 -d 5 -S $1
done
