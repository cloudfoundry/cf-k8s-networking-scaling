package discovery

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	xdspb "github.com/envoyproxy/go-control-plane/envoy/api/v2"
	corepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/core"
	lispb "github.com/envoyproxy/go-control-plane/envoy/api/v2/listener"
	routepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/route"
	hcmpb "github.com/envoyproxy/go-control-plane/envoy/config/filter/network/http_connection_manager/v2"
	"github.com/envoyproxy/go-control-plane/pkg/cache"
	xds "github.com/envoyproxy/go-control-plane/pkg/server"
	"github.com/envoyproxy/go-control-plane/pkg/wellknown"
	"github.com/golang/protobuf/ptypes"
	anypb "github.com/golang/protobuf/ptypes/any"
	wrappers "github.com/golang/protobuf/ptypes/wrappers"
	opentracing "github.com/opentracing/opentracing-go"
	"github.com/pkg/errors"
)

type DiscoverServer struct {
	xds.Server
	cache       cache.SnapshotCache
	configSpan  opentracing.Span
	ingressPort uint32
	nodes       map[string]int64
	spans       map[int64]map[string]opentracing.Span
}

func NewDiscoveryServer(ingressPort uint32) *DiscoverServer {
	snapshotCache := cache.NewSnapshotCache(true, cache.IDHash{}, &logger{})

	ds := &DiscoverServer{
		ingressPort: ingressPort,
		cache:       snapshotCache,
		nodes:       map[string]int64{},
		spans:       map[int64]map[string]opentracing.Span{},
	}
	ds.Server = xds.NewServer(context.Background(), snapshotCache, newCallbacks(ds))
	// _ = ds.UpdateRoutes(nil, nil, nil)
	return ds
}

func (ds *DiscoverServer) RegisterNode(nodeId string, streamID int64) bool {
	_, ok := ds.nodes[nodeId]
	if !ok {
		log.Printf("Registering node %s", nodeId)
		ds.nodes[nodeId] = streamID
		_ = ds.UpdateNodeRoutes(nodeId, nil, nil, nil)
	}
	return ok
}

func (ds *DiscoverServer) DeregisterNodeByStreamID(streamID int64) {
	for nodeId, sID := range ds.nodes {
		if sID == streamID {
			delete(ds.nodes, nodeId)
			ds.cache.ClearSnapshot(nodeId)
		}
	}
}

func (ds *DiscoverServer) UpdateRoutes(clusters []*xdspb.Cluster, loadAssignments []*xdspb.ClusterLoadAssignment, virtualHosts []*routepb.VirtualHost) (int, error) {
	updatedNodes := 0
	for nodeId := range ds.nodes {
		err := ds.UpdateNodeRoutes(nodeId, clusters, loadAssignments, virtualHosts)
		if err != nil {
			return updatedNodes, err
		}
		updatedNodes++
	}

	return updatedNodes, nil
}

func (ds *DiscoverServer) UpdateNodeRoutes(nodeName string, clusters []*xdspb.Cluster, loadAssignments []*xdspb.ClusterLoadAssignment, virtualHosts []*routepb.VirtualHost) error {
	var clustersCache, endpointsCache, routesCache, runtimesCache []cache.Resource

	// RDS
	routesCache = []cache.Resource{
		&xdspb.RouteConfiguration{
			Name:         "ingress_80",
			VirtualHosts: virtualHosts,
		},
	}

	// EDS
	endpointsCache = make([]cache.Resource, len(loadAssignments))
	for i := range loadAssignments {
		endpointsCache[i] = cache.Resource(loadAssignments[i])
	}

	// CDS
	clustersCache = make([]cache.Resource, len(clusters))
	for i := range clusters {
		clustersCache[i] = cache.Resource(clusters[i])
	}

	version := getVersion()
	var snapshot cache.Snapshot
	prevSnapshot, err := ds.cache.GetSnapshot(nodeName)
	if err != nil { // No prevous snapshot -> create new listeners
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

		listenersCache := []cache.Resource{
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
		snapshot = cache.NewSnapshot(version, endpointsCache, clustersCache, routesCache, listenersCache, runtimesCache)
	} else { // Previous snapshot; preserve listeners
		snapshot = cache.NewSnapshot(version, endpointsCache, clustersCache, routesCache, nil, runtimesCache)
		snapshot.Resources[cache.Listener] = prevSnapshot.Resources[cache.Listener]
	}

	// Tell Jaeger that we are serving a new config version
	if ds.configSpan != nil {
		ds.configSpan.Finish()
	}
	ds.configSpan = opentracing.GlobalTracer().StartSpan("createSnapshot")
	ds.configSpan.SetTag("version", version)
	err = ds.cache.SetSnapshot(nodeName, snapshot) // never returns an error

	return err
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
	log.Printf("Callback: OnStreamOpen: streamID = %d, url = %s\n\n", streamID, url)
	d.discoverServer.spans[streamID] = map[string]opentracing.Span{}
	return nil
}

func (d *discoveryServerCallbacks) OnStreamClosed(streamID int64) {
	log.Printf("Callback: OnStreamClosed: streamID = %d\n\n", streamID)
	d.discoverServer.DeregisterNodeByStreamID(streamID)
	delete(d.discoverServer.spans, streamID)
}

func (d *discoveryServerCallbacks) OnStreamRequest(streamID int64, req *xdspb.DiscoveryRequest) error {
	log.Printf("Callback: OnStreamRequest: streamID = %d\nreq = %s\n\n", streamID, req.ResponseNonce)
	d.discoverServer.RegisterNode(req.Node.Id, streamID)

	if spans, ok := d.discoverServer.spans[streamID]; ok {
		if span, ok := spans[req.ResponseNonce]; ok {
			span.SetTag("timeout", false)
			span.SetTag("nonce", req.ResponseNonce)
			span.Finish()
			delete(d.discoverServer.spans[streamID], req.ResponseNonce)
		}
	}

	return nil
}

func (d *discoveryServerCallbacks) OnStreamResponse(streamID int64, req *xdspb.DiscoveryRequest, out *xdspb.DiscoveryResponse) {
	log.Printf("Callback: OnStreamResponse: streamID = %d\nreq = %s\nout = %s\n\n", streamID, req.ResponseNonce, out.Nonce)
	typename := out.TypeUrl[strings.LastIndex(out.TypeUrl, ".")+1:]
	if typename == "Listener" {
		return
	}

	resourceNames, err := parseResourcesNames(out.Resources, out.TypeUrl)
	if err != nil {
		log.Fatalf("cannot parse resource names, err: %s", err)
	}

	routeNumbers, err := parseRouteNumbers(resourceNames)
	if err != nil {
		log.Fatalf("cannot parse resource number, err: %s", err)
	}

	routeNumbersStr := serializeRouteNumbers(routeNumbers)
	d.discoverServer.configSpan.LogKV(
		"event", fmt.Sprintf("Sending %s", typename),
		"type", typename,
		"typeurl", out.TypeUrl,
		"version", out.VersionInfo,
		"routes", routeNumbersStr,
		"node", req.Node.Id,
	)
	// This will cause duplicate span ID warning in Jaeger but it will merge all logs together for the last span
	d.discoverServer.configSpan.Finish()

	requestSpan := opentracing.GlobalTracer().StartSpan("sendConfig")
	requestSpan.LogKV(
		"event", fmt.Sprintf("Sending %s", typename),
		"type", typename,
		"typeurl", out.TypeUrl,
		"version", out.VersionInfo,
		"routes", routeNumbersStr,
		"node", req.Node.Id,
	)
	d.discoverServer.spans[streamID][out.Nonce] = requestSpan

	go func(streamID int64, nonce string) {
		for range time.After(2 * time.Minute) {
			if spans, ok := d.discoverServer.spans[streamID]; ok {
				if span, ok := spans[nonce]; ok {
					span.SetTag("timeout", true)
					span.Finish()
					delete(spans, nonce)
				}
			}
		}
	}(streamID, out.Nonce)
}

func (d *discoveryServerCallbacks) OnFetchRequest(ctx context.Context, req *xdspb.DiscoveryRequest) error {
	log.Printf("Callback: OnFetchRequest: \nreq = %s\n\n", req.ResponseNonce)
	return nil
}

func (d *discoveryServerCallbacks) OnFetchResponse(req *xdspb.DiscoveryRequest, res *xdspb.DiscoveryResponse) {
	log.Printf("Callback: OnFetchResponse: \nreq = %s\nres = %s\n\n", req.ResponseNonce, res.Nonce)
}

type logger struct {
}

func (l logger) Debugf(format string, args ...interface{}) { log.Printf("snapshot: "+format, args...) }
func (l logger) Infof(format string, args ...interface{})  { log.Printf("snapshot: "+format, args...) }
func (l logger) Warnf(format string, args ...interface{})  { log.Printf("snapshot: "+format, args...) }
func (l logger) Errorf(format string, args ...interface{}) { log.Printf("snapshot: "+format, args...) }

func getVersion() string {
	return fmt.Sprintf("%d", time.Now().Unix())
}

func parseResourcesNames(marshaledResources []*anypb.Any, typeURL string) ([]string, error) {
	names := make([]string, len(marshaledResources))

	for i, marshaledResource := range marshaledResources {
		// TODO: create ones
		resource, err := createResource(typeURL)
		if err != nil {
			return nil, err
		}
		err = ptypes.UnmarshalAny(marshaledResource, resource)
		if err != nil {
			return nil, err
		}

		// For Route we don't care about RouteConfiguration name, we care only about virutal hosts names
		if typeURL == cache.RouteType {
			return getRouteResourceRoutesNames(resource.(*xdspb.RouteConfiguration)), nil
		}

		names[i] = cache.GetResourceName(resource)
	}

	return names, nil
}

func createResource(typeURL string) (cache.Resource, error) {
	switch typeURL {
	case cache.EndpointType:
		return &xdspb.ClusterLoadAssignment{}, nil
	case cache.ClusterType:
		return &xdspb.Cluster{}, nil
	case cache.RouteType:
		return &xdspb.RouteConfiguration{}, nil
	case cache.ListenerType:
		return &xdspb.Listener{}, nil
	default:
		return nil, fmt.Errorf("%s not supported", typeURL)
	}
}

func getRouteResourceRoutesNames(route *xdspb.RouteConfiguration) []string {
	names := make([]string, len(route.VirtualHosts))

	for i, vh := range route.VirtualHosts {
		names[i] = vh.GetName()
	}

	return names
}

// parseRouteNumbers returns slice of integers which are parsed by stripping last number after last dot in the input string
func parseRouteNumbers(resources []string) ([]int, error) {
	nums := make([]int, len(resources))

	for i, res := range resources {
		numStr := res[strings.LastIndex(res, "_")+1:]
		num, err := strconv.Atoi(numStr)
		if err != nil {
			return nil, err
		}
		nums[i] = num
	}
	return nums, nil
}

func serializeRouteNumbers(nums []int) string {
	numsStr := make([]string, len(nums))
	for i, n := range nums {
		numsStr[i] = fmt.Sprintf("%d", n)
	}

	return strings.Join(numsStr, ",")
}
