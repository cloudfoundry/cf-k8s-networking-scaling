.PHONY: all clean test build

all: clean build
clean:
	rm -rf bin
test:
	go test -race -v ./...
build:
	go build -o bin/scrapper cmd/main.go

