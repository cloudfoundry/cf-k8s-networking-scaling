package client

import (
	"io/ioutil"
	"testing"

	"github.com/go-test/deep"
)

const TRACES_PATH = "./artifacts/traces.json"

func TestGenerateEvents(t *testing.T) {
	content, err := ioutil.ReadFile(TRACES_PATH)
	if err != nil {
		t.Fatal("Could not read traces.json " + err.Error())
	}

	traces, err := Parse(content)
	if err != nil {
		t.Error("Could not parse traces.json", err)
	}

	events := ProduceEvents(traces)

	if len(events) == 0 {
		t.Error("Definitely should have some events")
	}

	expectedEvents := []*Event{
		{
			Version:   "1583262975",
			Timestamp: 1583262975620460,
			Datetime:  "2020-03-03T19:16:15Z",
			Type:      "Cluster",
			Routes:    []int{6, 7, 8, 9},
			RoutesStr: "6,7,8,9",
		},
		{
			Version:   "1583262975",
			Timestamp: 1583262975621216,
			Datetime:  "2020-03-03T19:16:15Z",
			Type:      "RouteConfiguration",
			Routes:    []int{6, 7, 8, 9},
			RoutesStr: "6,7,8,9",
		},
		{
			Version:   "1583262975",
			Timestamp: 1583262975634576,
			Datetime:  "2020-03-03T19:16:15Z",
			Type:      "ClusterLoadAssignment",
			Routes:    []int{6, 7, 8, 9},
			RoutesStr: "6,7,8,9",
		},
		{
			Version:   "1583271032",
			Timestamp: 1583271032701013,
			Datetime:  "2020-03-03T21:30:32Z",
			Type:      "Cluster",
			Routes:    []int{4, 5, 1, 2, 3},
			RoutesStr: "4,5,1,2,3",
		},
		{
			Version:   "1583271032",
			Timestamp: 1583271032701923,
			Datetime:  "2020-03-03T21:30:32Z",
			Type:      "RouteConfiguration",
			Routes:    []int{1, 2, 3, 4, 5},
			RoutesStr: "1,2,3,4,5",
		},
		{
			Version:   "1583271032",
			Timestamp: 1583271032717064,
			Datetime:  "2020-03-03T21:30:32Z",
			Type:      "ClusterLoadAssignment",
			Routes:    []int{1, 2, 3, 4, 5},
			RoutesStr: "1,2,3,4,5",
		},
	}

	if diff := deep.Equal(events, expectedEvents); diff != nil {
		t.Error(diff)
	}
}
