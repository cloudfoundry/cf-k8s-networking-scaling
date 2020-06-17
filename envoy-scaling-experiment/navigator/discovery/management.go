package discovery

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"

	"github.com/pkg/errors"

	"code.cloudfoundry.org/navigator/route"
	opentracing "github.com/opentracing/opentracing-go"
)

type ManagementServer struct {
	xdsServer       *DiscoverServer
	handler         http.Handler
	hostnameForat   string
	port            int
	configGenerator *route.ConfigGenerator
}

func NewManagmentServer(hostnameFormat string, port int, discoveryServer *DiscoverServer) *ManagementServer {
	mux := http.NewServeMux()
	s := &ManagementServer{
		xdsServer:       discoveryServer,
		hostnameForat:   hostnameFormat,
		port:            port,
		handler:         mux,
		configGenerator: route.NewConfigGenerator(),
	}
	mux.HandleFunc("/set-routes", s.HandleSetRoutes)
	mux.HandleFunc("/", s.HandleIndex)

	return s
}

func (s *ManagementServer) ListenAndServe(addr string) error {
	httpServer := &http.Server{
		Handler: s.handler,
		Addr:    addr,
	}

	return httpServer.ListenAndServe()
}

type HandleSetRoutesPaylaod struct {
	Numbers  []int
	Clusters []int
}

func (s *ManagementServer) HandleIndex(w http.ResponseWriter, req *http.Request) {
	_, _ = w.Write([]byte("Registered nodes:\n"))
	for nodeID := range s.xdsServer.nodes {
		_, _ = w.Write([]byte("\t" + nodeID + "\n"))
	}
	w.WriteHeader(http.StatusOK)
}

func (s *ManagementServer) HandleSetRoutes(w http.ResponseWriter, req *http.Request) {
	var err error
	span := opentracing.GlobalTracer().StartSpan("setRoutes")
	defer span.Finish()

	body, err := ioutil.ReadAll(req.Body)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	var payload HandleSetRoutesPaylaod
	err = json.Unmarshal(body, &payload)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(errors.Wrap(err, "cannot parse JSON").Error()))
		return
	}

	span.SetTag("routes", payload.Numbers)

	var routeConfig *route.RouteConfig
	onlyEndpoints := req.URL.Query()["onlyEndpoints"] != nil

	if onlyEndpoints {
		routeConfig, err = s.configGenerator.GenerateOnlyEndpoints(s.hostnameForat, uint32(s.port), payload.Numbers)
	} else {
		routeConfig, err = s.configGenerator.Generate(s.hostnameForat, uint32(s.port), payload.Numbers, payload.Clusters)
	}

	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(errors.Wrap(err, "cannot create route config").Error()))
		return
	}

	updated, err := s.xdsServer.UpdateRoutes(routeConfig.Clusters, routeConfig.LoadAssignments, routeConfig.VirutalHosts, onlyEndpoints)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(errors.Wrap(err, "cannot update Discover Server routes").Error()))
		return
	}

	_, _ = w.Write([]byte(fmt.Sprintf("{\"updated\": %d}", updated)))
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
}
