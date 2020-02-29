package route_test

import (
	"errors"
	"testing"

	"code.cloudfoundry.org/navigator/route"
	"code.cloudfoundry.org/navigator/route/routefakes"
	xdspb "github.com/envoyproxy/go-control-plane/envoy/api/v2"
	corepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/core"
	endpb "github.com/envoyproxy/go-control-plane/envoy/api/v2/endpoint"
	routepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/route"
	"github.com/go-test/deep"
	"github.com/golang/protobuf/ptypes/duration"
)

type GenerateVirtualHostsResult struct {
	vh  []*routepb.VirtualHost
	err error
}

func TestGenerateVirtualHosts(t *testing.T) {
	var tests = []struct {
		name     string
		config   route.Config
		expected *GenerateVirtualHostsResult
	}{
		{
			name:   "No Routes",
			config: route.Config{HostnameFormat: "", Numbers: []uint64{}},
			expected: &GenerateVirtualHostsResult{
				vh:  []*routepb.VirtualHost(nil),
				err: nil,
			},
		},
		{
			name:   "One Route",
			config: route.Config{HostnameFormat: "", Numbers: []uint64{1}},
			expected: &GenerateVirtualHostsResult{
				vh: []*routepb.VirtualHost{
					{
						Name:    "route.1",
						Domains: []string{"1.example.com"},
						Routes: []*routepb.Route{{
							Name: "",
							Match: &routepb.RouteMatch{
								PathSpecifier: &routepb.RouteMatch_Prefix{
									Prefix: "/",
								},
							},
							Action: &routepb.Route_Route{
								Route: &routepb.RouteAction{
									ClusterSpecifier: &routepb.RouteAction_Cluster{
										Cluster: "service.1",
									},
								},
							},
						}},
					},
				},
				err: nil,
			},
		},
		{
			name:   "More Routes",
			config: route.Config{HostnameFormat: "", Numbers: []uint64{1, 100, 500}},
			expected: &GenerateVirtualHostsResult{
				vh: []*routepb.VirtualHost{
					{
						Name:    "route.1",
						Domains: []string{"1.example.com"},
						Routes: []*routepb.Route{{
							Name: "",
							Match: &routepb.RouteMatch{
								PathSpecifier: &routepb.RouteMatch_Prefix{
									Prefix: "/",
								},
							},
							Action: &routepb.Route_Route{
								Route: &routepb.RouteAction{
									ClusterSpecifier: &routepb.RouteAction_Cluster{
										Cluster: "service.1",
									},
								},
							},
						}},
					},
					{
						Name:    "route.100",
						Domains: []string{"100.example.com"},
						Routes: []*routepb.Route{{
							Name: "",
							Match: &routepb.RouteMatch{
								PathSpecifier: &routepb.RouteMatch_Prefix{
									Prefix: "/",
								},
							},
							Action: &routepb.Route_Route{
								Route: &routepb.RouteAction{
									ClusterSpecifier: &routepb.RouteAction_Cluster{
										Cluster: "service.100",
									},
								},
							},
						}},
					},
					{
						Name:    "route.500",
						Domains: []string{"500.example.com"},
						Routes: []*routepb.Route{{
							Name: "",
							Match: &routepb.RouteMatch{
								PathSpecifier: &routepb.RouteMatch_Prefix{
									Prefix: "/",
								},
							},
							Action: &routepb.Route_Route{
								Route: &routepb.RouteAction{
									ClusterSpecifier: &routepb.RouteAction_Cluster{
										Cluster: "service.500",
									},
								},
							},
						}},
					},
				},
				err: nil,
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			vh, err := test.config.GenerateVirtualHosts()

			if diff := deep.Equal(err, test.expected.err); diff != nil {
				t.Error(diff)
			}

			if diff := deep.Equal(vh, test.expected.vh); diff != nil {
				t.Error(diff)
			}
		})
	}
}

type GenerateClustersResult struct {
	cl  []*xdspb.Cluster
	err error
}

func TestGenerateClusters(t *testing.T) {
	var tests = []struct {
		name     string
		config   route.Config
		expected *GenerateClustersResult
	}{
		{
			name:   "No Clusters",
			config: route.Config{HostnameFormat: "", Numbers: []uint64{}},
			expected: &GenerateClustersResult{
				cl:  []*xdspb.Cluster(nil),
				err: nil,
			},
		},
		{
			name:   "One Cluster",
			config: route.Config{HostnameFormat: "", Numbers: []uint64{1}},
			expected: &GenerateClustersResult{
				cl: []*xdspb.Cluster{
					{
						Name: "service.1",
						ConnectTimeout: &duration.Duration{
							Seconds: 1,
						},
						ClusterDiscoveryType: &xdspb.Cluster_Type{Type: xdspb.Cluster_EDS},
						LbPolicy:             xdspb.Cluster_ROUND_ROBIN,
						EdsClusterConfig: &xdspb.Cluster_EdsClusterConfig{
							ServiceName: "service.1",
							EdsConfig: &corepb.ConfigSource{
								ConfigSourceSpecifier: &corepb.ConfigSource_Ads{
									Ads: &corepb.AggregatedConfigSource{},
								},
							},
						},
					},
				},
				err: nil,
			},
		},
		{
			name:   "Multiple Clusters",
			config: route.Config{HostnameFormat: "", Numbers: []uint64{1, 100}},
			expected: &GenerateClustersResult{
				cl: []*xdspb.Cluster{
					{
						Name: "service.1",
						ConnectTimeout: &duration.Duration{
							Seconds: 1,
						},
						ClusterDiscoveryType: &xdspb.Cluster_Type{Type: xdspb.Cluster_EDS},
						LbPolicy:             xdspb.Cluster_ROUND_ROBIN,
						EdsClusterConfig: &xdspb.Cluster_EdsClusterConfig{
							ServiceName: "service.1",
							EdsConfig: &corepb.ConfigSource{
								ConfigSourceSpecifier: &corepb.ConfigSource_Ads{
									Ads: &corepb.AggregatedConfigSource{},
								},
							},
						},
					},
					{
						Name: "service.100",
						ConnectTimeout: &duration.Duration{
							Seconds: 1,
						},
						ClusterDiscoveryType: &xdspb.Cluster_Type{Type: xdspb.Cluster_EDS},
						LbPolicy:             xdspb.Cluster_ROUND_ROBIN,
						EdsClusterConfig: &xdspb.Cluster_EdsClusterConfig{
							ServiceName: "service.100",
							EdsConfig: &corepb.ConfigSource{
								ConfigSourceSpecifier: &corepb.ConfigSource_Ads{
									Ads: &corepb.AggregatedConfigSource{},
								},
							},
						},
					},
				},
				err: nil,
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cl, err := test.config.GenerateClusters()

			if diff := deep.Equal(err, test.expected.err); diff != nil {
				t.Error(diff)
			}

			if diff := deep.Equal(cl, test.expected.cl); diff != nil {
				t.Error(diff)
			}
		})
	}
}

type GenerateLoadAssignmentsResult struct {
	clas []*xdspb.ClusterLoadAssignment
	err  error
}

func TestGenerateLoadAssignments(t *testing.T) {
	fakeStaticResolver := &routefakes.FakeResolver{}
	fakeStaticResolver.ResolveAddrReturns("1.2.3.4", nil)

	fakeErroringResolver := &routefakes.FakeResolver{}
	fakeErroringResolver.ResolveAddrReturns("", errors.New("cannot resolve"))

	var tests = []struct {
		name     string
		config   route.Config
		expected *GenerateLoadAssignmentsResult
	}{
		{
			name: "No Endpoints",
			config: route.Config{
				HostnameFormat: "%d.example.com", Numbers: []uint64{}, Port: 80,
			},
			expected: &GenerateLoadAssignmentsResult{
				clas: []*xdspb.ClusterLoadAssignment(nil),
				err:  nil,
			},
		},
		{
			name: "One Endpoint",
			config: route.Config{
				HostnameFormat: "%d.example.com",
				Numbers:        []uint64{1},
				Port:           80,
				Resolver:       fakeStaticResolver,
			},
			expected: &GenerateLoadAssignmentsResult{
				clas: []*xdspb.ClusterLoadAssignment{
					{
						ClusterName: "service.1",
						Endpoints: []*endpb.LocalityLbEndpoints{
							&endpb.LocalityLbEndpoints{
								LbEndpoints: []*endpb.LbEndpoint{
									&endpb.LbEndpoint{
										HostIdentifier: &endpb.LbEndpoint_Endpoint{
											Endpoint: &endpb.Endpoint{
												Address: &corepb.Address{
													Address: &corepb.Address_SocketAddress{
														SocketAddress: &corepb.SocketAddress{
															Address: "1.2.3.4",
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
							},
						},
					},
				},
				err: nil,
			},
		},
		{
			name: "Invalid hostname",
			config: route.Config{
				HostnameFormat: "%d.example.com",
				Numbers:        []uint64{1},
				Port:           80,
				Resolver:       fakeErroringResolver,
			},
			expected: &GenerateLoadAssignmentsResult{
				clas: []*xdspb.ClusterLoadAssignment(nil),
				err:  errors.New("cannot resolve addr for service: 1.example.com, because: cannot resolve"),
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			clas, err := test.config.GenerateLoadAssignments()

			if diff := deep.Equal(err, test.expected.err); diff != nil {
				t.Error(diff)
			}

			if diff := deep.Equal(clas, test.expected.clas); diff != nil {
				t.Error(diff)
			}
		})
	}
}
