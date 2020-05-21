CLUSTER_VERSION=1.14.10-gke.32
ISTIO_USE_OPERATOR=1
MIXERLESS_TELEMETRY=0

ISTIO_NO_EDS_DEBOUNCE=0 # don't debounce Pilot push requests to Envoy for endpoints

ENABLE_GALLEY=true
ENABLE_MTLS=false
ENABLE_TELEMETRY=false
PILOT_REPLICAS=20
GATEWAY_REPLICAS=20
GALLEY_REPLICAS=10

ISTIO_USE_OPERATOR=1 # use istio-operator-values.yaml to configure Istio


NUM_APPS=2000 # NUM_APPS >= NUM_USERS * NUM_GROUPS && NUM_APPS % NUM_GROUPS == 0
NUM_USERS=1000
USER_DELAY=1 # in seconds
USER_POLL_DELAY=2 # how often to poll for upness of a route, 1 is fine for USER_DELAY > 10

NAMESPACES=0 # if 0, groups within the default namespace will be used
NUM_GROUPS=1000 # set to 1 for everything in one group or namespace

# steady state experiment where the number of virtualservices and gateways (routes) is constant
#   through the test, every time a user creates a route they also delete another one
STEADY_STATE=1
