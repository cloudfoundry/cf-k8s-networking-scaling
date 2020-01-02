CLUSTER_VERSION=1.14.8-gke.12
NUM_NODES=240
MACHINE_TYPE=n1-standard-8
AVAILABILITY_ZONE=$(gcloud compute instances list | grep "$(hostname) " | awk '{print $2}')
DATAPLANE_NUM_CONNECTIONS=10

ISTIO_FOLDER=/home/pivotal/istio-1.4.2
ISTIO_TAINT=1
NODES_FOR_ISTIO=80

MIXERLESS_TELEMETRY=0

NUM_APPS=4000 # NUM_APPS >= NUM_USERS * NUM_GROUPS && NUM_APPS % NUM_GROUPS == 0
NUM_USERS=1000
USER_DELAY=10 # in seconds

NAMESPACES=1 # if 0, groups within the default namespace will be used
NUM_GROUPS=4 # set to 1 for everything in one group or namespace

