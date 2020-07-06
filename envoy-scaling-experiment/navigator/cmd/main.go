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
	xdsPort, httpPort, serviceHostnameFormat, servicePort := parseArgs()

	tracer, closer := initJaeger("navigator")
	defer closer.Close()
	opentracing.SetGlobalTracer(tracer)

	log.Println("Creating ADS server")
	server := discovery.NewDiscoveryServer(80)
	log.Println("Creating gRPS server")
	grpcServer := grpc.NewServer()
	log.Printf("Trying to bind port %s\n", xdsPort)
	lis, _ := net.Listen("tcp", ":"+xdsPort)

	log.Println("Registering ADS")
	ads.RegisterAggregatedDiscoveryServiceServer(grpcServer, server)

	managementServer := discovery.NewManagmentServer(serviceHostnameFormat, servicePort, server)

	go func() {
		log.Println("Serving gRPS server")
		log.Fatal(grpcServer.Serve(lis))
	}()

	go func() {
		log.Println("Serving HTTP managmenet server")
		log.Fatal(managementServer.ListenAndServe(fmt.Sprintf(":%s", httpPort)))
	}()
	select {}
}

func initJaeger(service string) (opentracing.Tracer, io.Closer) {
	cfg, err := config.FromEnv()
	if err != nil {
		panic(fmt.Sprintf("ERROR: cannot configure Jaeger: %v\n", err))
	}

	cfg.Sampler.Type = "const"
	cfg.Sampler.Param = 1
	cfg.Reporter.LogSpans = true

	tracer, closer, err := cfg.New(service, config.Logger(jaeger.StdLogger))
	if err != nil {
		panic(fmt.Sprintf("ERROR: cannot init Jaeger: %v\n", err))
	}
	return tracer, closer
}

func parseArgs() (xdsPort, httpPort, serviceHostnameFormat string, servicePort int) {
	xdsPort = os.Getenv("XDS_PORT")
	if xdsPort == "" {
		log.Fatal("XDS_PORT is required")
	}
	httpPort = os.Getenv("HTTP_PORT")
	if httpPort == "" {
		log.Fatal("HTTP_PORT is required")
	}
	serviceHostnameFormat = os.Getenv("SERVICE_HOSTNAME_FORMAT")
	if serviceHostnameFormat == "" {
		log.Fatal("SERVICE_HOSTNAME_FORMAT is required")
	}
	servicePortStr := os.Getenv("SERVICE_PORT")
	if servicePortStr == "" {
		log.Fatal("SERVICE_PORT is required")
	}
	servicePort, err := strconv.Atoi(servicePortStr)
	if err != nil {
		log.Fatal("SERVICE_PORT is not a number")
	}
	if servicePort <= 0 {
		log.Fatal("SERVICE_PORT must be positive number")
	}

	return
}
