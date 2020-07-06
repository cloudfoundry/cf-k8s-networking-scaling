package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"time"

	"code.cloudfoundry.org/jaegerscrapper/client"
)

var jaegerQueryAddr string
var csvPath string
var operationName string
var service string

func init() {
	flag.StringVar(&jaegerQueryAddr, "jaegerQueryAddr", "", "Address to Jaeger Query service, e.g. 10.0.0.2:80")
	flag.StringVar(&csvPath, "csvPath", "", "Path where to save output CSV file which is seperated by semicolon \";\"")
	flag.StringVar(&operationName, "operationName", "", "Operation nanme to scrape, can be \"createSnapshot\" or \"sendConfig\"")
	flag.StringVar(&service, "service", "navigator", "Jaeger service to scrape")
	flag.Parse()

	if jaegerQueryAddr == "" {
		log.Fatal("jaegerQueryAddr is required")
	}
	if csvPath == "" {
		log.Fatal("csvPath is required")
	}
	if operationName == "" {
		log.Fatal("operationName is required")
	}
}

func main() {
	traces, err := client.FetchAndParse(jaegerQueryAddr, service)
	if err != nil {
		log.Fatalf("cannot fetch traces, err: %s", err)
	}

	defer func() {
		// In case of error save traces for further processing
		if r := recover(); r != nil {
			if traces != nil {
				traces_str, _ := json.Marshal(traces)
				_ = ioutil.WriteFile(fmt.Sprintf("traces_%s_%s_%s.json", time.Now().Format(time.RFC3339), service, operationName), traces_str, os.ModeAppend)
				panic(r)
			}
		}
	}()

	events := client.ProduceEvents(traces, operationName)

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
