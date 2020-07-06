package route

import (
	"fmt"
	"log"
	"sync"

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

type ConfigGenerator struct {
	resolver Resolver
}

type RouteConfig struct {
	Clusters        []*xdspb.Cluster
	LoadAssignments []*xdspb.ClusterLoadAssignment
	VirutalHosts    []*routepb.VirtualHost
}

func NewConfigGenerator() *ConfigGenerator {
	cg := &ConfigGenerator{
		NewHostnameResolver(),
	}

	return cg
}

func (cg *ConfigGenerator) NewConfig(hostnameFormat string, port uint32, numbers []int) (*Config, error) {
	err := validateNumbers(numbers)
	if err != nil {
		return nil, err
	}

	c := &Config{
		hostnameFormat,
		port,
		numbers,
		cg.resolver,
	}

	return c, nil
}

func (cg *ConfigGenerator) Generate(hostnameFormat string, port uint32, numbers []int, extraClusters []int) (*RouteConfig, error) {
	var err error
	if len(extraClusters) > 0 {
		err = validateNumbers(extraClusters)
		if err != nil {
			return nil, err
		}
	}

	c, err := cg.NewConfig(hostnameFormat, port, numbers)
	if err != nil {
		return nil, err
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

	if len(extraClusters) > 0 {
		c.Numbers = extraClusters
		extraCls, err := c.GenerateClusters()
		if err != nil {
			return nil, errors.Wrap(err, "cannot generate extra clusters")
		}
		rc.Clusters = append(rc.Clusters, extraCls...)
	}

	return rc, nil
}

func (cg *ConfigGenerator) GenerateOnlyEndpoints(hostnameFormat string, port uint32, numbers []int) (*RouteConfig, error) {
	// create new resolver to clean its cache
	// TODO: find a better way for cleaning cache
	cg.resolver = NewHostnameResolver()
	c, err := cg.NewConfig(hostnameFormat, port, numbers)
	if err != nil {
		return nil, err
	}
	rc := &RouteConfig{}
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
			Name:    c.routeName(n),
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
	addresses, err := c.generateAddresses()
	if err != nil {
		return nil, err
	}

	for _, n := range c.Numbers {
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
												Address: addresses[n],
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
	return fmt.Sprintf("service_%d", n)
}

func (c *Config) routeName(n int) string {
	return fmt.Sprintf("route_%d", n)
}

func (c *Config) clusterHostname(n int) string {
	return fmt.Sprintf(c.HostnameFormat, n)
}

func (c *Config) domain(n int) string {
	return fmt.Sprintf("%d.example.com", n)
}

type resolveResult struct {
	adddress string
	number   int
}

func (c *Config) generateAddresses() (map[int]string, error) {
	n := len(c.Numbers)
	results := map[int]string{}

	retChan := make(chan resolveResult, n)
	errChan := make(chan error, 1)

	for _, n := range c.Numbers {
		go func(n int) {
			h := c.clusterHostname(n)
			addr, err := c.Resolver.ResolveAddr(h)
			if err != nil {
				errChan <- fmt.Errorf("cannot resolve addr for service: %s, because: %s", h, err)
				return
			}
			retChan <- resolveResult{
				addr,
				n,
			}
		}(n)
	}

	for i := 0; i < n; i++ {
		select {
		case ret := <-retChan:
			results[ret.number] = ret.adddress
		case err := <-errChan:
			return nil, err
		}
	}

	return results, nil
}

type HostnameResolver struct {
	cache map[string]string
	mu    sync.Mutex
}

func NewHostnameResolver() *HostnameResolver {
	return &HostnameResolver{
		cache: make(map[string]string),
	}
}

func (hr *HostnameResolver) ResolveAddr(hostname string) (string, error) {
	hr.mu.Lock()
	addr, ok := hr.cache[hostname]
	hr.mu.Unlock()
	if ok {
		return addr, nil
	}

	addr, err := resolve.ResolveAddr(hostname)
	if err != nil {
		return "", err
	}

	log.Printf("resolved addr for service %s to %s", hostname, addr)

	hr.mu.Lock()
	hr.cache[hostname] = addr
	hr.mu.Unlock()
	return addr, nil
}

func validateNumbers(numbers []int) error {
	numbersSeen := map[int]struct{}{}

	for _, n := range numbers {
		if _, seen := numbersSeen[n]; seen {
			return fmt.Errorf("expected numbers to be unique, however number %d is repeated", n)
		}
		numbersSeen[n] = struct{}{}
	}

	return nil
}
