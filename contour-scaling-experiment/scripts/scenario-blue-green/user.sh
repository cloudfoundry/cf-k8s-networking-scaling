#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source $DIR/../../vars.sh
source $DIR/../utils.sh

echo "$(udate),$1,$2,PREPARING,"

# cf create-route
kubetpl render -s NAME="app-$1-g$2-green" -s HOSTNAME="app-$1-g$2-green" \
  $DIR/../../yaml/blue-green/httpproxy.yaml | kubectl apply -f -
echo "$(udate),$1,$2,GREEN_ROUTED,"

TARGET_URL=app-$1-g$2-green.example.com
until [[ "$(curl -s -o=/dev/null -w "%{http_code}" -HHost:$TARGET_URL http://$GATEWAY_URL)" == "200" ]]; do true; done
echo "$(udate),$1,$2,GREEN_SUCCESS,"

# cf map-route
echo "$(udate),$1,$2,STARTED,"
kubetpl render -s NAME="app-$1-g$2-blue" \
  -s NAMEBLUE="app-$1-g$2-blue" \
  -s NAMEGREEN="app-$1-g$2-green" \
  $DIR/../../yaml/blue-green/httpproxy-two-apps.yaml | kubectl apply -f -

# pretending to be cf CLI
sleep 1

# cf map-route
kubetpl render -s NAME="app-$1-g$2-blue" -s HOSTNAME="app-$1-g$2-green" \
  $DIR/../../yaml/blue-green/httpproxy.yaml | kubectl apply -f -
echo "$(udate),$1,$2,BLUE_REMOVED,"

TARGET_URL=app-$1-g$2-blue.example.com
until [[ -n "$(curl -s -HHost:$TARGET_URL http://$GATEWAY_URL | grep -o "Hostname: app-$1-g$2-green.*")" ]]; do true; done
echo "$(udate),$1,$2,SUCCESS,"

# remove green route
kubectl delete httpproxy "app-$1-g$2-green" > /dev/null &

lastfail=$(udate)
timesToPoll=$(echo "120 / $USER_POLL_DELAY" | bc)
for ((i=$timesToPoll; i>0; i--)); do
  sleep $USER_POLL_DELAY &
  out=$(curl -sS -w "\\n%{http_code},$GATEWAY_URL-$1g$2-$i.curl" -HHost:$TARGET_URL http://$GATEWAY_URL 2>"curlstuff/$INGRESS_HOST:$INGRESS_PORT-$1g$2-$i.curl")
  status=$(echo "${out}" | tail -n1) # curl's -w adds text to the last line
  hname=$(echo "${out}" | grep -o "Hostname: app-$1-g$2-green.*")

  if [[ "$(echo $status | cut -d, -f1)" != "200" || "${hname}" == "" ]]; then
    lastfail=$(udate)
    echo "$(udate),$1,$2,FAILURE,$status"
  fi
  wait
done

echo "$lastfail,$1,$2,COMPLETED,"
>&2 wlog "Completed $1-g$2"

