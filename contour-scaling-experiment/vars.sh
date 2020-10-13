CLUSTER_VERSION=1.17.12-gke.500
NUM_NODES=100
MACHINE_TYPE=n1-standard-8
DATAPLANE_NUM_CONNECTIONS=10

ENVOY_REPLICAS=10

NUM_APPS=1000 # == NUM_USERS; actual pods will be 2 * NUM_APPS * PODS_PER_APP
NUM_USERS=1000
PODS_PER_APP=1
USER_DELAY=10 # in seconds
USER_POLL_DELAY=1 # how often to poll for upness of a route, 1 is fine for USER_DELAY > 10

NAMESPACES=0 # if 0, groups within the default namespace will be used
NUM_GROUPS=1000 # set to 1 for everything in one group or namespace

# steady state experiment where the number of virtualservices and gateways (routes) is constant
#   through the test, every time a user creates a route they also delete another one
STEADY_STATE=1

# blue-green or rolling
SCENARIO="blue-green"
