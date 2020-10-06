#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source $DIR/../../vars.sh
source $DIR/../utils.sh

echo "$(udate),$1,$2,STARTED,"
TARGET_URL=app-$1-g$2.example.com

if [ $NAMESPACES -eq 1 ]; then namespace=group-$2; else namespace=default; fi

# if [ $STEADY_STATE -eq 1 ]; then
#   offset=$(expr $NUM_APPS / $NUM_GROUPS / 2)
#   kubetpl render $DIR/../yaml/gateway.yaml $DIR/../yaml/virtualservice.yaml -s NAME=httpbin-$(expr $1 + $offset)-g$2 -s NAMESPACE=$namespace | kubectl delete -f -
# fi

# kubetpl render $DIR/../yaml/gateway.yaml $DIR/../yaml/virtualservice.yaml -s NAME=httpbin-$1-g$2 -s NAMESPACE=$namespace | kubectl apply -f -

NAME=app-$1-g$2 NAMESPACE=$namespace $DIR/../../yaml/rollout/route.sh
echo "$(udate),$1,$2,DEPLOYED,"

until [[ "$(curl -s -HHost:$TARGET_URL http://$GATEWAY_URL | grep -o "Name: v1")" == "Name: v1" ]]; do true; done

echo "$(udate),$1,$2,SUCCESS,"
# >&2 wlog "SUCCESS $1-g$2"

lastfail=$(udate)
timesToPoll=$(echo "120 / $USER_POLL_DELAY" | bc)
for ((i=$timesToPoll; i>0; i--)); do
  sleep $USER_POLL_DELAY &
  out=$(curl -sS -w "\\n%{http_code},$GATEWAY_URL-$1g$2-$i.curl" -HHost:$TARGET_URL http://$GATEWAY_URL 2>"curlstuff/$INGRESS_HOST:$INGRESS_PORT-$1g$2-$i.curl")
  status=$(echo "${out}" | tail -n1) # curl's -w adds text to the last line
  version=$(echo "${out}" | grep -o "Name: .*") # we set version in the app name

  if [[ "$(echo $status | cut -d, -f1)" != "200" || "${version}" != "Name: v1" ]]; then
    lastfail=$(udate)
    echo "$(udate),$1,$2,FAILURE,$status"
  fi
  wait
done

echo "$lastfail,$1,$2,COMPLETED,"
>&2 wlog "Completed $1-g$2"

