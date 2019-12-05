CLUSTER_VERSION=1.14.8-gke.12
NUM_NODES=60
MACHINE_TYPE=n1-standard-8
AVAILABILITY_ZONE=$(gcloud compute instances list | grep "$(hostname) " | awk '{print $2}')
DATAPLANE_NUM_CONNECTIONS=10

ISTIO_FOLDER=/home/pivotal/istio-1.4.0
ISTIO_TAINT=1
NODES_FOR_ISTIO=20

MIXERLESS_TELEMETRY=0

NUM_APPS=1000 # must be equal to or larger than NUM_USERS
NUM_USERS=100
USER_DELAY=10

NAMESPACES=0 # NUM_APPS will be overridden when this is true (with 1000)

ISOLATE_DATAPLANE=0
