package client

import (
	"log"
	"strconv"
	"strings"
	"time"
)

type Event struct {
	Version   string
	Timestamp int64
	Datetime  string
	Type      string // Cluster Route ClusterLoadAssignment Endpoints
	RoutesStr string // Comman seprated list of routes we configure on Envoy
	Routes    []int  // Routes we configure on Envoy
}

func ProduceEvents(traces []*Trace) []*Event {
	spans := extractSpans(traces)
	spans = dedupeSpans(spans)
	return createEvents(spans)
}

func extractSpans(traces []*Trace) []*Span {
	spans := []*Span(nil)

	for _, tr := range traces {
		spans = append(spans, tr.Spans...)
	}

	return spans
}

// dedupeSpans returns a list of unique Spans which are deduped on SpanID and longest duration
func dedupeSpans(spans []*Span) []*Span {
	seen := map[string]*Span{}

	for _, span := range spans {
		if s, ok := seen[span.SpanID]; !ok || span.Duration > s.Duration {
			seen[span.SpanID] = span
		}
	}

	deduped := []*Span(nil)
	for _, span := range seen {
		deduped = append(deduped, span)
	}
	return deduped
}

func createEvents(spans []*Span) []*Event {
	events := []*Event(nil)

	for _, span := range spans {
		for _, log := range span.Logs {
			events = append(events, createEvent(log))
		}
	}

	return events
}

func createEvent(l *Log) *Event {
	event := &Event{
		Timestamp: l.Timestamp,
		Datetime:  time.Unix(0, l.Timestamp*1000).Format(time.RFC3339),
	}

	for _, field := range l.Fields {
		switch field.Key {
		case "type":
			event.Type = field.Value.(string)
		case "version":
			event.Version = field.Value.(string)
		case "routes":
			event.RoutesStr = field.Value.(string)
			event.Routes = mustParseRoutes(field.Value.(string))
			if len(event.Routes) == 0 {
				log.Printf("Warning: routes for event at %d are empty", event.Timestamp)
			}
		}
	}

	return event
}

// mustParseRoutes parses comma separated list of integers and returns themj
func mustParseRoutes(s string) []int {
	routesStr := strings.Split(s, ",")
	routes := make([]int, len(routesStr))

	for i, str := range routesStr {
		n, err := strconv.Atoi(str)
		if err != nil {
			return routes
		}
		routes[i] = n
	}

	return routes
}
