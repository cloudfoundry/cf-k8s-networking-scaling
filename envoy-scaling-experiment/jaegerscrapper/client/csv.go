package client

import (
	"encoding/csv"
	"fmt"
	"io"
)

var headers = []string{
	"Timestamp",
	"Date",
	"Version",
	"Type",
	"Routes",
}

func CreateCSV(events []*Event, out io.Writer) error {
	w := csv.NewWriter(out)
	w.Comma = ';'

	if err := w.Write(headers); err != nil {
		return err
	}

	for _, event := range events {
		r := toRecord(event)
		if err := w.Write(r); err != nil {
			return err
		}
	}

	w.Flush()

	return w.Error()
}

func toRecord(e *Event) []string {
	return []string{
		fmt.Sprintf("%d", e.Timestamp*1000),
		e.Datetime,
		e.Version,
		e.Type,
		e.RoutesStr,
	}
}
