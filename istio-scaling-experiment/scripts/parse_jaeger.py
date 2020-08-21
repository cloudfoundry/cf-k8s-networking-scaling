import json
import requests
import csv
from argparse import ArgumentParser


def fetch_traces(jaeger_url, service, operation="all"):
    params = {
        "service": service,
        "loopback": "2d",
        "limit": 10000000,
    }
    if operation != "all":
        params["operation"] = operation

    resp = requests.get("{}/api/traces".format(jaeger_url), params=params)
    return resp.json()


def process_traces(traces):
    columns = [
        "stamp",
        "duration",
        "operationName",
    ]
    rows = []
    processes_tags_columns = []
    tags_columns = []

    for t in traces["data"]:
        tags_dict = process_tags(t["spans"][0]["tags"])
        current_tags_columns = sorted(tags_dict.keys())

        if current_tags_columns != tags_columns:
            diff = [t for t in current_tags_columns if t not in tags_columns]
            tags_columns.extend(diff)

        p_tags_dict = process_tags(t["processes"]["p1"]["tags"])
        current_p_tags_columns = sorted(p_tags_dict.keys())

        if current_p_tags_columns != processes_tags_columns:
            diff = [
                t for t in current_p_tags_columns if t not in processes_tags_columns
            ]
            processes_tags_columns.extend(diff)

        row = {
            "stamp": t["spans"][0]["startTime"] * 1000,
            "duration": t["spans"][0]["duration"] * 1000,
            "operationName": t["spans"][0]["operationName"],
            **p_tags_dict,
            **tags_dict,
        }

        rows.append(row)

    return columns + processes_tags_columns + tags_columns, rows


def write_csv(columns, rows, fname):
    with open(fname, "w", newline="") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def process_tags(tags):
    tags_dict = {}

    for t in tags:
        k, v = t["key"], t["value"]
        if tags_dict.get(k, ""):
            tags_dict[k] += "," + str(v)
        else:
            tags_dict[k] = str(v)

    return tags_dict


def get_hostname(trace):
    return next(
        t["value"] for t in trace["processes"]["p1"]["tags"] if t["key"] == "hostname"
    )


def main():
    parser = ArgumentParser("Jaeger Traces to CSV")
    parser.add_argument("--jaeger_url", help="URL to Jaeger Collector", required=True)
    parser.add_argument("--service", help="Service name in Jaeger", required=True)
    parser.add_argument("--operation", help="Operation name in Jaeger", default="all")
    parser.add_argument("output", help="Output path for CSV", default="/dev/fd/1")
    args = parser.parse_args()

    print("fetching traces")
    traces = fetch_traces(args.jaeger_url, args.service, args.operation)
    print("processing traces")
    columns, rows = process_traces(traces)
    print("converting to CSV")
    write_csv(columns, rows, args.output)


if __name__ == "__main__":
    main()
