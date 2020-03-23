package discovery

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"

	"github.com/pkg/errors"

	"code.cloudfoundry.org/navigator/route"
)

type ManagementServer struct {
	xdsServer     *DiscoverServer
	handler       http.Handler
	hostnameForat string
	port          int
}

func NewManagmentServer(hostnameFormat string, port int, discoveryServer *DiscoverServer) *ManagementServer {
	mux := http.NewServeMux()
	s := &ManagementServer{
		xdsServer:     discoveryServer,
		hostnameForat: hostnameFormat,
		port:          port,
		handler:       mux,
	}
	mux.HandleFunc("/set-routes", s.HandleSetRoutes)

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
	Numbers []int
}

func (s *ManagementServer) HandleSetRoutes(w http.ResponseWriter, req *http.Request) {
	var payload HandleSetRoutesPaylaod
	body, err := ioutil.ReadAll(req.Body)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	err = json.Unmarshal(body, &payload)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(errors.Wrap(err, "cannot parse JSON").Error()))
		return
	}

	c, err := route.Generate(s.hostnameForat, uint32(s.port), payload.Numbers)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(errors.Wrap(err, "cannot create route config").Error()))
		return
	}

	updated, err := s.xdsServer.UpdateRoutes(c.Clusters, c.LoadAssignments, c.VirutalHosts)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(errors.Wrap(err, "cannot update Discover Server routes").Error()))
		return
	}

	_, _ = w.Write([]byte(fmt.Sprintf("{\"updated\": %d}", updated)))
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
}

