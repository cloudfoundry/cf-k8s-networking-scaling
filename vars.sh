CLUSTER_VERSION=1.14.8-gke.33
NUM_NODES=120
MACHINE_TYPE=n1-standard-8
AVAILABILITY_ZONE=$(gcloud compute instances list | grep "$(hostname) " | awk '{print $2}')
DATAPLANE_NUM_CONNECTIONS=10

ISTIO_FOLDER=/home/pivotal/istio-1.4.2
ISTIO_TAINT=1
NODES_FOR_ISTIO=40

MIXERLESS_TELEMETRY=0

NUM_APPS=10 # NUM_APPS >= NUM_USERS * NUM_GROUPS && NUM_APPS % NUM_GROUPS == 0
NUM_USERS=$NUM_APPS
USER_DELAY=1 # in seconds
USER_POLL_DELAY=3 # how often to poll for upness of a route, 1 is fine for USER_DELAY > 10

NAMESPACES=0 # if 0, groups within the default namespace will be used
NUM_GROUPS=1 # set to 1 for everything in one group or namespace

# steady state experiment where the number of virtualservices and gateways (routes) is constant
#   through the test, every time a user creates a route they also delete another one
STEADY_STATE=0
