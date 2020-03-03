package main

import (
	"fmt"

	"code.cloudfoundry.org/jaegerscrapper/client"
	"github.com/davecgh/go-spew/spew"
)

func main() {
	// GOAL:
	// - Query jaeger
	//   (via undocument HTTP API that backs the web UI)
	// - Save as CSV
	//   (one line per log event)

	traces, err := client.FetchAndParse("35.223.181.191")
	fmt.Println(spew.Sdump(traces), err)
}
