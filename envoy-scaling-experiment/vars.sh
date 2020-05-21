CLUSTER_VERSION=1.14.10-gke.37
NUM_NODES=100
MACHINE_TYPE=n1-standard-8

NUM_APPS=2000 # NUM_APPS >= NUM_USERS * NUM_GROUPS && NUM_APPS % NUM_GROUPS == 0
NUM_USERS=1000 # number of routes to create during experiment
USER_DELAY=5 # delay between route creations, in seconds
USER_POLL_DELAY=2 # will poll all routes in parallel, then wait this many seconds, then poll again
GATEWAY_NUM=1 # number of Ingress Gateway Envoys
NODES_FOR_CP=1

# steady state experiment where the number of virtualservices and gateways (routes) is constant
#   through the test, every time a user creates a route they also delete another one
STEADY_STATE=1
