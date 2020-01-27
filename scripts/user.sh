#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

echo "$(udate),$1,$2,STARTED,"
TARGET_URL=httpbin-$1-g$2.example.com

if [ $NAMESPACES -eq 1 ]; then namespace=ns-$2; else namespace=default; fi

kubetpl render ../yaml/gateway.yaml ../yaml/virtualservice.yaml -s NAME=httpbin-$1-g$2 -s NAMESPACE=$namespace | kubectl apply -f -

until [ $(curl -s -o /dev/null -w "%{http_code}" -HHost:$TARGET_URL http://$INGRESS_HOST:$INGRESS_PORT/status/200) -eq 200 ]; do true; done

echo "$(udate),$1,$2,SUCCESS,"
>&2 wlog "SUCCESS $1-g$2"

lastfail=$(udate)
timesToPoll=$(expr 120 / $USER_POLL_DELAY)
for ((i=$timesToPoll; i>0; i--)); do
  sleep $USER_POLL_DELAY &
  status=$(curl -vvv -o /dev/null -w "%{http_code},$INGRESS_HOST:$INGRESS_PORT-$1g$2-$i.curl" -HHost:$TARGET_URL http://$INGRESS_HOST:$INGRESS_PORT/status/200 2>"curlstuff/$INGRESS_HOST:$INGRESS_PORT-$1g$2-$i.curl")
  if [ $(echo $status | cut -d, -f1) -ne 200 ]; then
    lastfail=$(udate)
    echo "$(udate),$1,$2,FAILURE,$status"
  fi
  wait
done

echo "$lastfail,$1,$2,COMPLETED,"
>&2 wlog "Completed $1-g$2"

