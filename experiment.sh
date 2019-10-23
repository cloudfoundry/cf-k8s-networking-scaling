#!/bin/bash

# set -ex

source vars.sh

trap "exit" INT TERM ERR
trap "kill 0" EXIT

# ====== UTILITIES =====
udate ()
{
  date -u +%s
}

wlog ()
{
  echo "$(udate): $1"
}

forever ()
{
    wlog "Started loop"
    while true; do
        $@;
        sleep 0.5;
    done
}

monpods ()
{
    pods=$(kubectl get pods -n "$1" --field-selector="status.phase!=Running" -o json)
    if [ $(echo "$pods" | jq '.items | length') -ne 0 ]; then
        wlog "Pod failure event!"
        wlog "$pods"
    fi
}

# rm -rf tmp
filename="$(udate)-$DATAPLANE_RPS-$USER_RPS"
mkdir $filename

cp vars.sh $filename/

pushd $filename
  wlog "====== SETUP ======"

  gcloud container clusters create $CLUSTER_NAME \
    --cluster-version $CLUSTER_VERSION \
    --num-nodes $NUM_NODES \
    --machine-type=$MACHINE_TYPE \
    --zone us-central1-f \
    --project cf-routing-desserts

  gcloud container clusters get-credentials $CLUSTER_NAME \
      --zone us-central1-f \
      --project cf-routing-desserts

  kubectl create clusterrolebinding cluster-admin-binding \
      --clusterrole=cluster-admin \
      --user=$(gcloud config get-value core/account)

  kubectl create namespace istio-system

  helm repo add istio.io https://storage.googleapis.com/istio-release/releases/$ISTIO_VERSION/charts/

  # download istio at $ISTIO_VERSION
  curl -L https://git.io/getLatestIstio | sh -

  pushd istio-$ISTIO_VERSION
    kubectl apply -f install/kubernetes/helm/helm-service-account.yaml

    helm template install/kubernetes/helm/istio-init --name istio-init --namespace istio-system | kubectl apply -f -

    # wait until istio CRDs are loaded
    until [ $(kubectl get crds | grep -c 'istio.io') -ge "23" ]; do true; done

    helm template install/kubernetes/helm/istio \
      --name istio --namespace istio-system | kubectl apply -f -

    # wait until Istio is reporting live and healthy
    kubectl wait --for=condition=available --timeout=600s -n istio-system \
      deployments/istio-citadel deployments/istio-galley deployments/istio-ingressgateway deployments/istio-pilot \
      deployments/istio-policy deployments/istio-sidecar-injector deployments/istio-telemetry deployments/prometheus

    # clean up setup pods
    kubectl delete pod --all-namespaces --field-selector=status.phase==Succeeded

    # install test workloads
    kubectl label namespace default istio-injection=enabled --overwrite=true
    kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml

    kubectl wait --for=condition=available --timeout=600s deployment/{details-v1,productpage-v1,ratings-v1,reviews-v1,reviews-v2,reviews-v3}
    kubectl exec -it $(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}') -c ratings -- curl productpage:9080/productpage | grep -o "<title>.*</title>"

    kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml

    sleep 3

    export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
    export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
    export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

    curl -s http://${GATEWAY_URL}/productpage | grep -o "<title>.*</title>"
    open http://${GATEWAY_URL}/productpage
    kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml
  popd

  wlog "====== POD MONITORING ======"

  forever monpods default > default_pods.log &
  forever monpods istio-system > istio_pods.log &
  forever monpods kube-system > system_pods.log &

  wlog "====== GENERATE LOAD ======"

  # create data plane load with fortio
  docker run fortio/fortio load -qps $DATAPLANE_RPS -t 0 http://${GATEWAY_URL}/productpage > fortio.log &

  # ./userfactory.sh > user.log &

  sleep 30

  wlog "====== COLLECT RESULTS ======"
  # stop monitoring jobs
  kill $(jobs -p)

  # go/rust run collate program

  wlog "Default Pod failure event count: $(cat default_pods.log | grep "Pod failure event" | wc -l)"
  wlog "Istio Pod failure event count: $(cat istio_pods.log | grep "Pod failure event" | wc -l)"
  wlog "System Pod failure event count: $(cat istio_pods.log | grep "Pod failure event" | wc -l)"

  wlog "====== TEARDOWN ======"

  # gcloud container clusters delete $CLUSTER_NAME --zone us-central1-f
popd

wait
