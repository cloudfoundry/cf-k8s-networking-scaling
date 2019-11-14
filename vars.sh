CLUSTER_VERSION=1.14.8-gke.12
NUM_NODES=60
MACHINE_TYPE=n1-standard-8
AVAILABILITY_ZONE=us-central1-a
DATAPLANE_NUM_CONNECTIONS=10

ISTIO_FOLDER=/home/pivotal/istio-1.3.5-soft-affinity
ISTIO_TAINT=1

NUM_APPS=1000 # must be equal to or larger than NUM_USERS
NUM_USERS=100
USER_DELAY=1

NAMESPACES=1 # NUM_APPS will be overridden when this is true (with 1000)
