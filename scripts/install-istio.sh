#!/bin/bash

source ../vars.sh
source ../scripts/utils.sh

# download istio at $ISTIO_VERSION
# curl -L https://git.io/getLatestIstio | ISTIO_VERSION=$ISTIO_VERSION sh -

# pushd istio-$ISTIO_VERSION

pushd $ISTIO_FOLDER
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
  # kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml

  # kubectl wait --for=condition=available --timeout=600s deployment/{details-v1,productpage-v1,ratings-v1,reviews-v1,reviews-v2,reviews-v3}
  # kubectl exec -it $(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}') -c ratings -- curl productpage:9080/productpage | grep -o "<title>.*</title>"

  # kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml

  # sleep 3

  # export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  # export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
  # export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
  # export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

  # curl -s http://${GATEWAY_URL}/productpage | grep -o "<title>.*</title>"
  # # open http://${GATEWAY_URL}/productpage
  # kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml

popd
