package discovery

import (
	"context"
	"fmt"
	"log"

	"github.com/davecgh/go-spew/spew"
	xdspb "github.com/envoyproxy/go-control-plane/envoy/api/v2"
	corepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/core"
	endpb "github.com/envoyproxy/go-control-plane/envoy/api/v2/endpoint"
	lispb "github.com/envoyproxy/go-control-plane/envoy/api/v2/listener"
	routepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/route"
	hcmpb "github.com/envoyproxy/go-control-plane/envoy/config/filter/network/http_connection_manager/v2"
	"github.com/envoyproxy/go-control-plane/pkg/cache"
	xds "github.com/envoyproxy/go-control-plane/pkg/server"
	"github.com/envoyproxy/go-control-plane/pkg/wellknown"
	"github.com/golang/protobuf/ptypes"
	"github.com/golang/protobuf/ptypes/duration"
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

	// RDS configuration
	routes = []cache.Resource{
		&xdspb.RouteConfiguration{
			Name: "route.1",
			VirtualHosts: []*routepb.VirtualHost{{
				Name:    "backend",
				Domains: []string{"*"},
				Routes: []*routepb.Route{{
					Name: "",
					Match: &routepb.RouteMatch{
						PathSpecifier: &routepb.RouteMatch_Prefix{
							Prefix: "/service/1",
						},
					},
					Action: &routepb.Route_Route{
						Route: &routepb.RouteAction{
							ClusterSpecifier: &routepb.RouteAction_Cluster{
								Cluster: "service1",
							},
						},
					},
				}},
			}},
		},
	}

	//   - address:
	//       socket_address:
	//         address: 0.0.0.0
	//         port_value: 80
	//     filter_chains:
	//     - filters:
	//       - name: envoy.filters.network.http_connection_manager
	//         typed_config:
	//           "@type": type.googleapis.com/envoy.config.filter.network.http_connection_manager.v2.HttpConnectionManager
	//           codec_type: auto
	//           stat_prefix: ingress_http
	//           route_config:
	//             name: local_route
	//             virtual_hosts:
	//             - name: backend
	//               domains:
	//               - "*"
	//               routes:
	//               - match:
	//                   prefix: "/service/1"
	//                 route:
	//                   cluster: service1
	//               - match:
	//                   prefix: "/service/2"
	//                 route:
	//                   cluster: service2
	//           http_filters:
	//           - name: envoy.router
	//             typed_config: {}

	// HTTP filter configuration
	manager := &hcmpb.HttpConnectionManager{
		CodecType:  hcmpb.HttpConnectionManager_AUTO,
		StatPrefix: "ingress_http",
		RouteSpecifier: &hcmpb.HttpConnectionManager_Rds{
			Rds: &hcmpb.Rds{
				ConfigSource: &corepb.ConfigSource{
					ConfigSourceSpecifier: &corepb.ConfigSource_Ads{
						Ads: &corepb.AggregatedConfigSource{},
					},
				},
				RouteConfigName: "route.1",
			},
		},
		HttpFilters: []*hcmpb.HttpFilter{{
			Name: wellknown.Router,
		}},
	}
	pbst, err := ptypes.MarshalAny(manager)
	if err != nil {
		panic(err)
	}

	fmt.Printf("%s\n", pbst)

	listeners = []cache.Resource{
		&xdspb.Listener{
			Address: &corepb.Address{
				Address: &corepb.Address_SocketAddress{
					SocketAddress: &corepb.SocketAddress{
						Address: "0.0.0.0",
						PortSpecifier: &corepb.SocketAddress_PortValue{
							PortValue: 80,
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
	endpoints = []cache.Resource{&xdspb.ClusterLoadAssignment{
		ClusterName: "service1",
		Endpoints: []*endpb.LocalityLbEndpoints{
			&endpb.LocalityLbEndpoints{
				LbEndpoints: []*endpb.LbEndpoint{
					&endpb.LbEndpoint{
						HostIdentifier: &endpb.LbEndpoint_Endpoint{
							Endpoint: &endpb.Endpoint{
								Address: &corepb.Address{
									Address: &corepb.Address_SocketAddress{
										SocketAddress: &corepb.SocketAddress{
											Address: "172.28.1.1",
											PortSpecifier: &corepb.SocketAddress_PortValue{
												PortValue: 80,
											},
										},
									},
								},
							},
						},
					},
				},
			}},
	}}

	clusters = []cache.Resource{
		&xdspb.Cluster{
			Name: "service1",
			ConnectTimeout: &duration.Duration{
				Seconds: 1,
			},
			ClusterDiscoveryType: &xdspb.Cluster_Type{Type: xdspb.Cluster_EDS},
			LbPolicy:             xdspb.Cluster_ROUND_ROBIN,
			Http2ProtocolOptions: &corepb.Http2ProtocolOptions{},
			EdsClusterConfig: &xdspb.Cluster_EdsClusterConfig{
				ServiceName: "service1",
				EdsConfig: &corepb.ConfigSource{
					ConfigSourceSpecifier: &corepb.ConfigSource_Ads{
						Ads: &corepb.AggregatedConfigSource{},
					},
				},
			},
		},
	}

	snapshotCache := cache.NewSnapshotCache(false, cache.IDHash{}, &logger{})
	snapshot := cache.NewSnapshot("2.7", endpoints, clusters, routes, listeners, runtimes)
	_ = snapshotCache.SetSnapshot("ingressgateway", snapshot)

	server := xds.NewServer(context.Background(), snapshotCache, newCallbacks())

	return server
}

func newCallbacks() *discoveryServerCallbacks {
	return &discoveryServerCallbacks{}
}
