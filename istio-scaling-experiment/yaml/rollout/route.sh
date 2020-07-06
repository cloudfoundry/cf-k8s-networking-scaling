#!/bin/bash

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

kubectl -n ${NAMESPACE} label --overwrite pods -l "app=${NAME},version=v1" target=live
kubectl -n ${NAMESPACE} label --overwrite pods -l "app=${NAME},version=v0" target=canary
