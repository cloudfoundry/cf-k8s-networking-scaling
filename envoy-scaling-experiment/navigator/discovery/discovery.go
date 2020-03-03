package discovery

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/davecgh/go-spew/spew"
	xdspb "github.com/envoyproxy/go-control-plane/envoy/api/v2"
	corepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/core"
	lispb "github.com/envoyproxy/go-control-plane/envoy/api/v2/listener"
	routepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/route"
	hcmpb "github.com/envoyproxy/go-control-plane/envoy/config/filter/network/http_connection_manager/v2"
	"github.com/envoyproxy/go-control-plane/pkg/cache"
	xds "github.com/envoyproxy/go-control-plane/pkg/server"
	"github.com/envoyproxy/go-control-plane/pkg/wellknown"
	"github.com/golang/protobuf/ptypes"
	wrappers "github.com/golang/protobuf/ptypes/wrappers"
	opentracing "github.com/opentracing/opentracing-go"
	"github.com/pkg/errors"
)

type DiscoverServer struct {
	xds.Server
	cache       cache.SnapshotCache
	configSpan  opentracing.Span
	ingressPort uint32
}

func NewDiscoveryServer(ingressPort uint32) *DiscoverServer {
	snapshotCache := cache.NewSnapshotCache(true, cache.IDHash{}, &logger{})

	ds := &DiscoverServer{
		ingressPort: ingressPort,
		cache:       snapshotCache,
	}
	ds.Server = xds.NewServer(context.Background(), snapshotCache, newCallbacks(ds))
	_ = ds.UpdateRoutes(nil, nil, nil)
	return ds
}

type discoveryServerCallbacks struct {
	discoverServer *DiscoverServer
}

func newCallbacks(ds *DiscoverServer) *discoveryServerCallbacks {
	return &discoveryServerCallbacks{
		discoverServer: ds,
	}
}

func (d *discoveryServerCallbacks) OnStreamOpen(ctx context.Context, streamID int64, url string) error {
	log.Printf("Callback: OnStreamOpen: streamId = %d, url = %s\n\n", streamID, url)
	return nil
}

func (d *discoveryServerCallbacks) OnStreamClosed(streamID int64) {
	log.Printf("Callback: OnStreamClosed: streamId = %d\n\n", streamID)
}

func (d *discoveryServerCallbacks) OnStreamRequest(streamID int64, req *xdspb.DiscoveryRequest) error {
	log.Printf("Callback: OnStreamRequest: streamId = %d\nreq = %s\n\n", streamID, spew.Sdump(*req))
	return nil
}

func (d *discoveryServerCallbacks) OnStreamResponse(streamID int64, req *xdspb.DiscoveryRequest, out *xdspb.DiscoveryResponse) {
	log.Printf("Callback: OnStreamResponse: streamId = %d\nreq = %s\nout = %s\n\n", streamID, spew.Sdump(*req), spew.Sdump(*out))
	typename := out.TypeUrl[strings.LastIndex(out.TypeUrl, ".")+1:]
	if typename == "Listener" {
		return
	}

	resourceNames := parseResourcesNames(out.Resources, out.TypeUrl)
	routeNumbers := parseRouteNumbers(resourceNames)

	d.discoverServer.configSpan.LogKV(
		"event", fmt.Sprintf("Sending %s", typename),
		"type", typename,
		"typeurl", out.TypeUrl,
		"version", out.VersionInfo,
		"full_response", out.String(),
		"routes", routeNumbers,
	)
	// This will cause duplicate span ID warning in Jaeger but it will merge all logs together for the last span
	d.discoverServer.configSpan.Finish()
}

func (d *discoveryServerCallbacks) OnFetchRequest(ctx context.Context, req *xdspb.DiscoveryRequest) error {
	log.Printf("Callback: OnFetchRequest: \nreq = %s\n\n", spew.Sdump(*req))
	return nil
}

func (d *discoveryServerCallbacks) OnFetchResponse(req *xdspb.DiscoveryRequest, res *xdspb.DiscoveryResponse) {
	log.Printf("Callback: OnFetchResponse: \nreq = %s\nres = %s\n\n", spew.Sdump(*req), spew.Sdump(*res))
}

type logger struct {
}

func (l logger) Debugf(format string, args ...interface{}) { log.Printf("snapshot: "+format, args...) }
func (l logger) Infof(format string, args ...interface{})  { log.Printf("snapshot: "+format, args...) }
func (l logger) Warnf(format string, args ...interface{})  { log.Printf("snapshot: "+format, args...) }
func (l logger) Errorf(format string, args ...interface{}) { log.Printf("snapshot: "+format, args...) }

func (ds *DiscoverServer) UpdateRoutes(clusters []*xdspb.Cluster, loadAssignments []*xdspb.ClusterLoadAssignment, virtualHosts []*routepb.VirtualHost) error {
	var clustersCache, endpointsCache, routesCache, listenersCache, runtimesCache []cache.Resource

	// RDS
	routesCache = []cache.Resource{
		&xdspb.RouteConfiguration{
			Name:         "ingress_80",
			VirtualHosts: virtualHosts,
		},
	}

	// HTTP filter configuration
	manager := &hcmpb.HttpConnectionManager{
		CodecType:         hcmpb.HttpConnectionManager_AUTO,
		StatPrefix:        "ingress_http",
		GenerateRequestId: &wrappers.BoolValue{Value: true},
		RouteSpecifier: &hcmpb.HttpConnectionManager_Rds{
			Rds: &hcmpb.Rds{
				ConfigSource: &corepb.ConfigSource{
					ConfigSourceSpecifier: &corepb.ConfigSource_Ads{
						Ads: &corepb.AggregatedConfigSource{},
					},
				},
				RouteConfigName: "ingress_80",
			},
		},
		HttpFilters: []*hcmpb.HttpFilter{{
			Name: wellknown.Router,
		}},
	}
	pbst, err := ptypes.MarshalAny(manager)
	if err != nil {
		return errors.Wrap(err, "cannot create HttpConnectionManager")
	}

	listenersCache = []cache.Resource{
		&xdspb.Listener{
			Address: &corepb.Address{
				Address: &corepb.Address_SocketAddress{
					SocketAddress: &corepb.SocketAddress{
						Address: "0.0.0.0",
						PortSpecifier: &corepb.SocketAddress_PortValue{
							PortValue: ds.ingressPort,
						},
					},
				},
			},
			FilterChains: []*lispb.FilterChain{{
				Filters: []*lispb.Filter{{
					Name: wellknown.HTTPConnectionManager,
					ConfigType: &lispb.Filter_TypedConfig{
						TypedConfig: pbst,
					},
				}},
			}},
		},
	}

	// EDS
	endpointsCache = make([]cache.Resource, len(loadAssignments))
	for i := range loadAssignments {
		endpointsCache[i] = cache.Resource(loadAssignments[i])
	}

	// EDS
	clustersCache = make([]cache.Resource, len(clusters))
	for i := range clusters {
		clustersCache[i] = cache.Resource(clusters[i])
	}

	version := getVersion()
	snapshot := cache.NewSnapshot(version, endpointsCache, clustersCache, routesCache, listenersCache, runtimesCache)

	// Tell Jaeger that we are serving a new config version
	if ds.configSpan != nil {
		ds.configSpan.Finish()
	}
	ds.configSpan = opentracing.GlobalTracer().StartSpan("createSnapshot")
	ds.configSpan.SetTag("version", version)
	err = ds.cache.SetSnapshot("ingressgateway", snapshot) // never returns an error

	return err

}

func getVersion() string {
	return fmt.Sprintf("%d", time.Now().Unix())
}
