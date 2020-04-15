package main

import (
	"flag"
	"log"
	"os"

	"code.cloudfoundry.org/jaegerscrapper/client"
)

var jaegerQueryAddr string
var csvPath string
var traceType string

func init() {
	flag.StringVar(&jaegerQueryAddr, "jaegerQueryAddr", "", "Address to Jaeger Query service, e.g. 10.0.0.2:80")
	flag.StringVar(&csvPath, "csvPath", "", "Path where to save output CSV file which is seperated by semicolon \";\"")
	flag.StringVar(&traceType, "operationName", "", "Operation nanme to scrape, can be \"createSnapshot\" or \"sendConfig\"")
	flag.Parse()

	if jaegerQueryAddr == "" {
		log.Fatal("jaegerQueryAddr is required")
	}
	if csvPath == "" {
		log.Fatal("csvPath is required")
	}
	if traceType == "" {
		log.Fatal("traceType is required")
	}
}

func main() {
	traces, err := client.FetchAndParse(jaegerQueryAddr)
	if err != nil {
		log.Fatalf("cannot fetch traces, err: %s", err)
	}

	events := client.ProduceEvents(traces, traceType)

	outFile, err := os.Create(csvPath)
	if err != nil {
		log.Fatalf("cannot open file to write, err: %s", err)
	}

	err = client.CreateCSV(events, outFile)
	if err != nil {
		log.Fatalf("cannot write CSV, err: %s", err)
	}

	log.Print("Done!")
}
