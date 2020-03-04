package discovery

import (
	"testing"

	xdspb "github.com/envoyproxy/go-control-plane/envoy/api/v2"
	routepb "github.com/envoyproxy/go-control-plane/envoy/api/v2/route"
	"github.com/envoyproxy/go-control-plane/pkg/cache"
	"github.com/go-test/deep"
	anypb "github.com/golang/protobuf/ptypes/any"
)

func TestParseResourcesNames(t *testing.T) {
	tests := []struct {
		name          string
		typeURL       string
		resources     []cache.Resource
		expectedNames []string
	}{
		{
			name:    "Endpoints",
			typeURL: cache.EndpointType,
			resources: []cache.Resource{
				&xdspb.ClusterLoadAssignment{
					ClusterName: "service.1",
				},
				&xdspb.ClusterLoadAssignment{
					ClusterName: "service.2",
				},
				&xdspb.ClusterLoadAssignment{
					ClusterName: "service.3",
				},
				&xdspb.ClusterLoadAssignment{
					ClusterName: "service.4",
				},
			},
			expectedNames: []string{
				"service.1",
				"service.2",
				"service.3",
				"service.4",
			},
		},
		{
			name:    "Clusters",
			typeURL: cache.ClusterType,
			resources: []cache.Resource{
				&xdspb.Cluster{
					Name: "service.1",
				},
				&xdspb.Cluster{
					Name: "service.2",
				},
				&xdspb.Cluster{
					Name: "service.3",
				},
				&xdspb.Cluster{
					Name: "service.4",
				},
			},
			expectedNames: []string{
				"service.1",
				"service.2",
				"service.3",
				"service.4",
			},
		},
		{
			name:    "Routes",
			typeURL: cache.RouteType,
			resources: []cache.Resource{
				&xdspb.RouteConfiguration{
					Name: "ingress",
					VirtualHosts: []*routepb.VirtualHost{
						{
							Name: "route.1",
						},
						{
							Name: "route.2",
						},
						{
							Name: "route.3",
						},
						{
							Name: "route.4",
						},
					},
				},
			},
			expectedNames: []string{
				"route.1",
				"route.2",
				"route.3",
				"route.4",
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Log(test.typeURL)

			resources, err := marshalResources(test.resources, test.typeURL)
			if err != nil {
				panic(err)
			}
			names, err := parseResourcesNames(resources, test.typeURL)

			if err != nil {
				t.Errorf("expected not to error but got %s", err)
			}
			if diff := deep.Equal(names, test.expectedNames); diff != nil {
				t.Error(diff)
			}
		})
	}
}

func marshalResources(resources []cache.Resource, typeURL string) ([]*anypb.Any, error) {
	marshaledResources := make([]*anypb.Any, len(resources))

	for i, resource := range resources {
		marshaled, err := cache.MarshalResource(resource)
		if err != nil {
			return nil, err
		}

		marshaledResources[i] = &anypb.Any{
			TypeUrl: typeURL,
			Value:   marshaled,
		}
	}

	return marshaledResources, nil
}

func TestParseRouteNumbers(t *testing.T) {
	resourcesNames := []string{
		"resource.1",
		"resource.2",
		"resource.3",
		"resource.4",
	}
	expectedRoutes := []int{1, 2, 3, 4}
	routes, err := parseRouteNumbers(resourcesNames)
	if err != nil {
		t.Errorf("expected not to error but got %s", err)
	}
	if diff := deep.Equal(routes, expectedRoutes); diff != nil {
		t.Error(diff)
	}
}
