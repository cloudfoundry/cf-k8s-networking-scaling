CLUSTER_VERSION=1.14.10-gke.45
NUM_NODES=100
MACHINE_TYPE=n1-standard-8
DATAPLANE_NUM_CONNECTIONS=10

ISTIO_FOLDER=/home/pivotal/istio-1.6.4
ISTIO_TAINT=1
NODES_FOR_ISTIO=20
ISTIO_USE_OPERATOR=1
MIXERLESS_TELEMETRY=0

ENABLE_GALLEY=false
ENABLE_MTLS=false
ENABLE_TELEMETRY=false
PILOT_REPLICAS=20
GATEWAY_REPLICAS=20
GALLEY_REPLICAS=0

NUM_APPS=1000 # NUM_APPS >= NUM_USERS * NUM_GROUPS && NUM_APPS % NUM_GROUPS == 0
NUM_USERS=1000
USER_DELAY=0.5 # in seconds
USER_POLL_DELAY=1 # how often to poll for upness of a route, 1 is fine for USER_DELAY > 10

NAMESPACES=0 # if 0, groups within the default namespace will be used
NUM_GROUPS=1000 # set to 1 for everything in one group or namespace

# steady state experiment where the number of virtualservices and gateways (routes) is constant
#   through the test, every time a user creates a route they also delete another one
STEADY_STATE=1

# blue-green or rolling
SCENARIO="blue-green"
