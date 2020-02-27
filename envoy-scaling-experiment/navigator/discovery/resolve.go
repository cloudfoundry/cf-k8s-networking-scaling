// Copyright 2017 Istio Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package discovery

import (
	"context"
	stderrors "errors"
	"fmt"
	"log"
	"net"
	"time"

	"github.com/pkg/errors"
)

type lookupIPAddrType = func(ctx context.Context, addr string) ([]net.IPAddr, error)

// ErrResolveNoAddress error occurs when IP address resolution is attempted,
// but no address was provided.
var ErrResolveNoAddress = stderrors.New("no address specified")

// ResolveAddr resolves an authority address to an IP address. Incoming
// addr can be an IP address or hostname. If addr is an IPv6 address, the IP
// part must be enclosed in square brackets.
//
// LookupIPAddr() may return multiple IP addresses, of which this function returns
// the first IPv4 entry. To use this function in an IPv6 only environment, either
// provide an IPv6 address or ensure the hostname resolves to only IPv6 addresses.
func ResolveAddr(addr string, lookupIPAddr ...lookupIPAddrType) (string, error) {
	if addr == "" {
		return "", ErrResolveNoAddress
	}
	log.Printf("Attempting to lookup address: %s", addr)
	defer log.Printf("Finished lookup of address: %s", addr)
	// lookup the udp address with a timeout of 15 seconds.
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	var addrs []net.IPAddr
	var lookupErr error
	if (len(lookupIPAddr) > 0) && (lookupIPAddr[0] != nil) {
		// if there are more than one lookup function, ignore all but first
		addrs, lookupErr = lookupIPAddr[0](ctx, addr)
	} else {
		addrs, lookupErr = net.DefaultResolver.LookupIPAddr(ctx, addr)
	}

	if lookupErr != nil || len(addrs) == 0 {
		return "", errors.WithMessage(lookupErr, "lookup failed for IP address")
	}
	var resolvedAddr string

	for _, address := range addrs {
		ip := address.IP
		if ip.To4() == nil {
			resolvedAddr = fmt.Sprintf("[%s]", ip)
		} else {
			resolvedAddr = ip.String()
			break
		}
	}
	log.Printf("Addr resolved to: %s", resolvedAddr)
	return resolvedAddr, nil
}
