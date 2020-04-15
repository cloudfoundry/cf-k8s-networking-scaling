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
	Duration  int
	Timeout   bool
}

func ProduceEvents(traces []*Trace, operationName string) []*Event {
	spans := extractSpans(traces)
	spans = filterSpans(spans, operationName)
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

func filterSpans(spans []*Span, operationName string) []*Span {
	for i, span := range spans {
		if span.OperationName != operationName {
			spans[i] = nil
		}
	}

	return spans
}

// dedupeSpans returns a list of unique Spans which are deduped on SpanID and longest duration
func dedupeSpans(spans []*Span) []*Span {
	seen := map[string]*Span{}

	for _, span := range spans {
		if span == nil {
			continue
		}
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
			events = append(events, createEvent(log, span))
		}
	}

	return events
}

func createEvent(l *Log, s *Span) *Event {
	event := &Event{
		Timestamp: l.Timestamp,
		Datetime:  time.Unix(0, l.Timestamp*1000).Format(time.RFC3339),
		Duration:  s.Duration,
		Timeout:   extractTimeoutTag(s),
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

func extractTimeoutTag(s *Span) bool {
	for _, t := range s.Tags {
		if t.Key == "timeout" {
			return t.Value.(bool)
		}
	}

	return false
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
