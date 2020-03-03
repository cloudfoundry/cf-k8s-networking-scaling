package client

type Event struct {
	Version   string
	Timestamp int64
	Type      string // Cluster Route ClusterLoadAssignment Endpoints
	Routes    []int  // which routes did we configure on Envoy
}

func ProduceEvents(traces []*Trace) []Event {
	return []Event{{}}
}
