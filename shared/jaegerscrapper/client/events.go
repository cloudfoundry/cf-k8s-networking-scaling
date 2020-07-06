package client

import (
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"
)

type Event struct {
	Version     string
	Timestamp   int64
	Datetime    string
	Type        string // Cluster Route ClusterLoadAssignment Endpoints
	RoutesStr   string // Comman seprated list of routes we configure on Envoy
	Routes      []int  // Routes we configure on Envoy
	Duration    int64
	Timeout     bool
	Resources   string // Used in Envoy
	PayloadSize float64
	NodeID      string
	Sent        string // Used in Navigator to track cache.responsd
	DidUpdate   string // Used in Envoy
}

func ProduceEvents(traces []*Trace, operationName string) []*Event {
	spans := extractSpans(traces)
	// spans = filterSpans(spans, operationName)
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
		fmt.Println(span.OperationName)
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
		if len(span.Logs) > 0 {
			for _, log := range span.Logs {
				events = append(events, createEventFromLog(log, span))
			}
		} else {
			events = append(events, createEventFromSpan(span))
		}
	}

	return events
}

func createEventFromSpan(s *Span) *Event {
	return createEvent(s.StartTime, s.Tags, s)
}

func createEventFromLog(l *Log, s *Span) *Event {
	return createEvent(l.Timestamp, l.Fields, s)
}

func createEvent(timestamp int64, tags []*Tag, s *Span) *Event {
	event := &Event{
		Timestamp: timestamp,
		Datetime:  time.Unix(0, milisecondsToNanosecods(timestamp)).Format(time.RFC3339),
		Duration:  milisecondsToNanosecods(s.Duration),
		Timeout:   extractTimeoutTag(s),
	}

	for _, field := range tags {
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
		case "resources":
			event.Resources = field.Value.(string)
		case "resource":
			event.Resources = field.Value.(string)
		case "size":
			if field.Type == "string" {
				event.PayloadSize, _ = strconv.ParseFloat(field.Value.(string), 64)
			} else {
				event.PayloadSize, _ = field.Value.(float64)
			}
		case "node_id":
			event.NodeID = field.Value.(string)
		case "sent":
			event.Sent = field.Value.(string)
		case "did_update":
			event.DidUpdate = field.Value.(string)
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

func milisecondsToNanosecods(s int64) int64 {
	return s * 1000
}
