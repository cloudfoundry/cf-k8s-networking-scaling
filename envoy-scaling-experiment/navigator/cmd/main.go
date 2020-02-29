package main

import (
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strconv"

	"code.cloudfoundry.org/navigator/discovery"
	"google.golang.org/grpc"

	ads "github.com/envoyproxy/go-control-plane/envoy/service/discovery/v2"
	opentracing "github.com/opentracing/opentracing-go"
	jaeger "github.com/uber/jaeger-client-go"
	config "github.com/uber/jaeger-client-go/config"
)

func main() {
	port := os.Getenv("PORT")
	numAppsStr := os.Getenv("NUM_APPS")
	if numAppsStr == "" {
		log.Fatal("NUM_APPS is not set")
	}
	numApps, err := strconv.Atoi(numAppsStr)
	if err != nil {
		log.Fatalf("NUM_APPS %q is not a number", numAppsStr)
	}

	tracer, closer := initJaeger("navigator")
	defer closer.Close()
	opentracing.SetGlobalTracer(tracer)

	log.Println("Creating ADS server")
	server := discovery.NewDiscoveryServer()
	log.Println("Creating gRPS server")
	grpcServer := grpc.NewServer()
	log.Printf("Trying to bind port %s\n", port)
	lis, _ := net.Listen("tcp", ":"+port)

	log.Println("Registering ADS")
	ads.RegisterAggregatedDiscoveryServiceServer(grpcServer, server)

	go func() {
		log.Println("Serving gRPS server")
		if err := grpcServer.Serve(lis); err != nil {
			// error handling
		}
	}()

	select {}
}

func initJaeger(service string) (opentracing.Tracer, io.Closer) {
	cfg := &config.Configuration{
		Sampler: &config.SamplerConfig{
			Type:  "const",
			Param: 1,
		},
		Reporter: &config.ReporterConfig{
			LogSpans:           true,
			LocalAgentHostPort: "jaeger-agent:6831",
		},
	}
	tracer, closer, err := cfg.New(service, config.Logger(jaeger.StdLogger))
	if err != nil {
		panic(fmt.Sprintf("ERROR: cannot init Jaeger: %v\n", err))
	}
	return tracer, closer
}
