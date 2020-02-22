package discovery

import (
	"context"
	"github.com/davecgh/go-spew/spew"
	xdspb "github.com/envoyproxy/go-control-plane/envoy/api/v2"
	corepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/core"
	"github.com/envoyproxy/go-control-plane/pkg/cache"
	xds "github.com/envoyproxy/go-control-plane/pkg/server"
	"github.com/golang/protobuf/ptypes/duration"
	"log"
)

type discoveryServerCallbacks struct {
}

func (d discoveryServerCallbacks) OnStreamOpen(ctx context.Context, streamID int64, url string) error {
	log.Printf("Callback: OnStreamOpen: streamId = %d, url = %s\n\n", streamID, url)
	return nil
}

func (d discoveryServerCallbacks) OnStreamClosed(streamID int64) {
	log.Printf("Callback: OnStreamClosed: streamId = %d\n\n", streamID)
}

func (d discoveryServerCallbacks) OnStreamRequest(streamID int64, req *xdspb.DiscoveryRequest) error {
	log.Printf("Callback: OnStreamRequest: streamId = %d\nreq = %s\n\n", streamID, spew.Sdump(*req))
	return nil
}

func (d discoveryServerCallbacks) OnStreamResponse(streamID int64, req *xdspb.DiscoveryRequest, out *xdspb.DiscoveryResponse) {
	log.Printf("Callback: OnStreamResponse: streamId = %d\nreq = %s\nout = %s\n\n", streamID, spew.Sdump(*req), spew.Sdump(*out))
}

func (d discoveryServerCallbacks) OnFetchRequest(ctx context.Context, req *xdspb.DiscoveryRequest) error {
	log.Printf("Callback: OnFetchRequest: \nreq = %s\n\n", spew.Sdump(*req))
	return nil
}

func (d discoveryServerCallbacks) OnFetchResponse(req *xdspb.DiscoveryRequest, res *xdspb.DiscoveryResponse) {
	log.Printf("Callback: OnFetchResponse: \nreq = %s\nres = %s\n\n", spew.Sdump(*req), spew.Sdump(*res))
}

type logger struct {
}

func (l logger) Debugf(format string, args ...interface{}) { log.Printf(format, args...) }
func (l logger) Infof(format string, args ...interface{})  { log.Printf(format, args...) }
func (l logger) Warnf(format string, args ...interface{})  { log.Printf(format, args...) }
func (l logger) Errorf(format string, args ...interface{}) { log.Printf(format, args...) }

func NewDiscoveryServer() xds.Server {
	var clusters, endpoints, routes, listeners, runtimes []cache.Resource

	//   - name: service1
	//    connect_timeout: 0.25s
	//    type: strict_dns
	//    lb_policy: round_robin
	//    http2_protocol_options: {}
	//    load_assignment:
	//      cluster_name: service1
	//      endpoints:
	//      - lb_endpoints:
	//        - endpoint:
	//            address:
	//              socket_address:
	//                address: service1
	//                port_value: 80
	clusters = []cache.Resource{
		&xdspb.Cluster{
			Name: "service1",
			ConnectTimeout: &duration.Duration{
				Seconds: 1,
			},
			ClusterDiscoveryType: &xdspb.Cluster_Type{Type: xdspb.Cluster_STRICT_DNS},
			LbPolicy:             xdspb.Cluster_ROUND_ROBIN,
			Http2ProtocolOptions: &corepb.Http2ProtocolOptions{},
			LoadAssignment: &xdspb.ClusterLoadAssignment{
				ClusterName: "service1",
			},
		},
	}

	snapshotCache := cache.NewSnapshotCache(false, cache.IDHash{}, &logger{})
	snapshot := cache.NewSnapshot("1.0", endpoints, clusters, routes, listeners, runtimes)
	_ = snapshotCache.SetSnapshot("node1", snapshot)

	server := xds.NewServer(context.Background(), snapshotCache, newCallbacks())

	return server
}

func newCallbacks() *discoveryServerCallbacks {
	return &discoveryServerCallbacks{}
}
