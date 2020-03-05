package client

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"

	"github.com/pkg/errors"
)

type Response struct {
	Data []*Trace `json:"data"`
}

type Trace struct {
	TraceID string  `json:"traceID"`
	Spans   []*Span `json:"spans"`
}

func (t *Trace) GetID() string {
	return t.TraceID
}

type Span struct {
	SpanID        string `json:"spanID"`
	OperationName string `json:"operationName"`
	StartTime     int64  `json:"startTime"`
	Duration      int    `json:"duration"`
	Tags          []*Tag `json:"tags"`
	Logs          []*Log `json:"logs"`
}

func (s *Span) GetID() string {
	return s.SpanID
}

type Tag struct {
	Key   string      `json:"key"`
	Type  string      `json:"type"`
	Value interface{} `json:"value"`
}

type Log struct {
	Timestamp int64  `json:"timestamp"`
	Fields    []*Tag `json:"fields"`
}

// http://35.223.181.191/api/traces?end=1583191141380000&limit=20&lookback=1h&maxDuration&minDuration&service=navigator&start=1583187541380000
func Fetch(jaegerQueryAddr string) ([]byte, error) {
	resp, err := http.Get(fmt.Sprintf("http://%s/api/traces?service=navigator&loopback=2d&limit=100000000", jaegerQueryAddr))
	if err != nil {
		return nil, errors.Wrap(err, "cannot fetch Jaeger query")
	}

	json, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, errors.Wrap(err, "cannot receive body")
	}

	return json, nil
}

func Parse(b []byte) ([]*Trace, error) {
	var data Response
	err := json.Unmarshal(b, &data)
	if err != nil {
		return nil, errors.Wrap(err, "cannot parse JSON")
	}

	return data.Data, nil
}

func FetchAndParse(jaegerQueryAddr string) ([]*Trace, error) {
	b, err := Fetch(jaegerQueryAddr)
	if err != nil {
		return nil, err
	}

	return Parse(b)
}

