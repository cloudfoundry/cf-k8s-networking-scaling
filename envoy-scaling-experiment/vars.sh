CLUSTER_VERSION=1.14.8-gke.33
NUM_NODES=2
MACHINE_TYPE=n1-standard-8

DATAPLANE_NUM_CONNECTIONS=10

NUM_APPS=20 # NUM_APPS >= NUM_USERS * NUM_GROUPS && NUM_APPS % NUM_GROUPS == 0
NUM_USERS=$NUM_APPS
USER_DELAY=1 # in seconds
USER_POLL_DELAY=3 # how often to poll for upness of a route, 1 is fine for USER_DELAY > 10

# steady state experiment where the number of virtualservices and gateways (routes) is constant
#   through the test, every time a user creates a route they also delete another one
STEADY_STATE=0
