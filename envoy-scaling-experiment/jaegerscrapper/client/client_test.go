package client

import (
	"io/ioutil"
	"testing"
)

func TestGenerateEvents(t *testing.T) {
	content, err := ioutil.ReadFile("./traces.json")
	if err != nil {
		panic("Could not read traces.json " + err.Error())
	}
	traces, err := Parse(content)
	if err != nil {
		t.Error("Could not parse traces.json", err)
	}
	events := ProduceEvents(traces)

	if len(events) == 0 {
		t.Error("Definitely should have some events")
	}

	expectedEvents := []Event{
		{
			Version:   "1583188518",
			Timestamp: 1583188521661038,
			Type:      "Cluster",
			Routes:    []int{},
		},
		{
			Version:   "1583188518",
			Timestamp: 1583188521662062,
			Type:      "ClusterLoadAssignment",
			Routes:    []int{},
		},
		{
			Version:   "1583188518",
			Timestamp: 1583188521665451,
			Type:      "RouteConfiguration",
			Routes:    []int{},
		},
	}
}
