CLUSTER_VERSION=1.14.8-gke.12
NUM_NODES=60
MACHINE_TYPE=n1-standard-8
AVAILABILITY_ZONE=us-central1-a
DATAPLANE_NUM_CONNECTIONS=10

ISTIO_FOLDER=/home/pivotal/istio-1.3.5-soft-affinity-20-pilots-10-gateways
ISTIO_TAINT=1
NODES_FOR_ISTIO=20

NUM_APPS=100 # must be equal to or larger than NUM_USERS
NUM_USERS=10
USER_DELAY=10

NAMESPACES=0 # NUM_APPS will be overridden when this is true (with 1000)

ISOLATE_DATAPLANE=0
