package route

import (
	"fmt"
	"log"

	"code.cloudfoundry.org/navigator/resolve"
	xdspb "github.com/envoyproxy/go-control-plane/envoy/api/v2"
	corepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/core"
	endpb "github.com/envoyproxy/go-control-plane/envoy/api/v2/endpoint"
	routepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/route"
	"github.com/golang/protobuf/ptypes/duration"
	"github.com/pkg/errors"
)

//go:generate go run github.com/maxbrunsfeld/counterfeiter/v6 . Resolver
type Resolver interface {
	ResolveAddr(hostname string) (addr string, err error)
}

type Config struct {
	HostnameFormat string
	Port           uint32
	Numbers        []int
	Resolver
}

type RouteConfig struct {
	Clusters        []*xdspb.Cluster
	LoadAssignments []*xdspb.ClusterLoadAssignment
	VirutalHosts    []*routepb.VirtualHost
}

func Generate(hostnameFormat string, port uint32, numbers []int) (*RouteConfig, error) {
	numbersSeen := map[int]struct{}{}

	for _, n := range numbers {
		if _, seen := numbersSeen[n]; seen {
			return nil, fmt.Errorf("expected numbers to be unique, however number %d is repeated", n)
		}
		numbersSeen[n] = struct{}{}
	}

	c := Config{
		hostnameFormat,
		port,
		numbers,
		&HostnameResolver{},
	}
	rc := &RouteConfig{}

	vhs, err := c.GenerateVirtualHosts()
	if err != nil {
		return nil, errors.Wrap(err, "cannot generate virutal hosts")
	}
	rc.VirutalHosts = vhs

	cls, err := c.GenerateClusters()
	if err != nil {
		return nil, errors.Wrap(err, "cannot generate clusters")
	}
	rc.Clusters = cls

	clas, err := c.GenerateLoadAssignments()
	if err != nil {
		return nil, errors.Wrap(err, "cannot generate cluster load assignemnts")
	}
	rc.LoadAssignments = clas

	return rc, nil
}

func (c *Config) GenerateVirtualHosts() (vhs []*routepb.VirtualHost, err error) {
	for _, n := range c.Numbers {
		vhs = append(vhs, &routepb.VirtualHost{
			Name:    fmt.Sprintf("route.%d", n),
			Domains: []string{c.domain(n)},
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
							Cluster: c.clusterName(n),
						},
					},
				},
			}},
		})
	}
	return
}

func (c *Config) GenerateClusters() (cls []*xdspb.Cluster, err error) {
	for _, n := range c.Numbers {
		cls = append(cls, &xdspb.Cluster{
			Name: c.clusterName(n),
			ConnectTimeout: &duration.Duration{
				Seconds: 1,
			},
			ClusterDiscoveryType: &xdspb.Cluster_Type{Type: xdspb.Cluster_EDS},
			LbPolicy:             xdspb.Cluster_ROUND_ROBIN,
			EdsClusterConfig: &xdspb.Cluster_EdsClusterConfig{
				ServiceName: c.clusterName(n),
				EdsConfig: &corepb.ConfigSource{
					ConfigSourceSpecifier: &corepb.ConfigSource_Ads{
						Ads: &corepb.AggregatedConfigSource{},
					},
				},
			},
		})
	}

	return
}

func (c *Config) GenerateLoadAssignments() (endps []*xdspb.ClusterLoadAssignment, err error) {
	for _, n := range c.Numbers {
		hostname := c.clusterHostname(n)
		addr, err := c.Resolver.ResolveAddr(hostname)
		if err != nil {
			return nil, fmt.Errorf("cannot resolve addr for service: %s, because: %s", hostname, err)
		} else {
			log.Printf("resolved addr for service %s to %s", hostname, addr)
		}

		endps = append(endps, &xdspb.ClusterLoadAssignment{
			ClusterName: c.clusterName(n),
			Endpoints: []*endpb.LocalityLbEndpoints{
				&endpb.LocalityLbEndpoints{
					LbEndpoints: []*endpb.LbEndpoint{
						&endpb.LbEndpoint{
							HostIdentifier: &endpb.LbEndpoint_Endpoint{
								Endpoint: &endpb.Endpoint{
									Address: &corepb.Address{
										Address: &corepb.Address_SocketAddress{
											SocketAddress: &corepb.SocketAddress{
												Address: addr,
												PortSpecifier: &corepb.SocketAddress_PortValue{
													PortValue: c.Port,
												},
											},
										},
									},
								},
							},
						},
					},
				}},
		})
	}
	return
}

func (c *Config) clusterName(n int) string {
	return fmt.Sprintf("service.%d", n)
}

func (c *Config) clusterHostname(n int) string {
	return fmt.Sprintf(c.HostnameFormat, n)
}

func (c *Config) domain(n int) string {
	return fmt.Sprintf("%d.example.com", n)
}

type HostnameResolver struct{}

func (hr *HostnameResolver) ResolveAddr(hostname string) (string, error) {
	return resolve.ResolveAddr(hostname)
}

