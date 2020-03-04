.PHONY: all build push

all: build push
build: VERSION=$(shell git rev-parse HEAD)
build:
	docker build . -f Dockerfile-gateway -t "gcr.io/cf-routing-desserts/envoy:${VERSION}"
	docker tag "gcr.io/cf-routing-desserts/envoy:${VERSION}" "gcr.io/cf-routing-desserts/envoy:latest"

# Tag with full GCR url
#   We'll use the cf-Routing-desserts project on GCR
# Docker configured to talk to gcloud
push:	VERSION=$(shell git rev-parse HEAD)
push:
	docker push "gcr.io/cf-routing-desserts/envoy"

