package main

import (
	"code.cloudfoundry.org/navigator/discovery"
	"google.golang.org/grpc"
	"log"
	"net"
	"os"

	ads "github.com/envoyproxy/go-control-plane/envoy/service/discovery/v2"
)

func main() {
	port := os.Getenv("PORT")

	log.Println("Creating ADS server")
	server := discovery.NewDiscoveryServer()
	log.Println("Creating gRPS server")
	grpcServer := grpc.NewServer()
	log.Printf("Trying to bind port %s\n", port)
	lis, _ := net.Listen("tcp", ":" + port)

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
