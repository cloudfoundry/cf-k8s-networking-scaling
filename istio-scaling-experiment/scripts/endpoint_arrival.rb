#!/snap/bin/ruby

require 'json'
require 'pry'

class Gateway
  def initialize(name)
    @name = name
    @endpoints = {}
    @envoy_endpoints = {}
    @missing = Hash.new([])
  end

  def generate_route
    print "Generating route for #{@name}..."
    @pid = spawn("~/istio-1.4.2/bin/istioctl -n istio-system dashboard envoy #{@name}", :out=>"route" )
    sleep(0.5)
    @route = File.read("route").split("\n").first
    puts "#{@route}"
  end

  def process_endpoints
    clusters = `curl -s "#{@route}/config_dump" | jq .configs[4].dynamic_route_configs[].route_config.virtual_hosts[].name`.split("\n")

    if clusters.empty?
      puts "Failed to reach gateway, retrying"
      generate_route
      process_endpoints
      return
    end

    clusters.each do |c|
      next if c.include?('*')

      if @endpoints[c].nil?
        @endpoints[c] = Time.now.to_i
      end
    end

    @endpoints.keys.each do |e|
      if !clusters.include?(e)
        @missing[e] += [Time.now.to_i]
      end
    end
  end

  def to_csv
    out = []
    @endpoints.keys.each do |e|
      out << ["#{@endpoints[e]}000000000", @name, e, @route, "appears"].join(',')
    end
    @missing.keys.each do |m|
      @missing[m].each do |time|
        out << ["#{time}000000000", @name, m, @route, "missing"].join(',')
      end
    end
    out.join("\n")
  end

  def process_eds
    # get endpoints with IPs only
    endpoints = `curl -sS "#{@route}/clusters" | grep -P '(\\d{1,3}\\.?){4,4}:\\d{1,}' | awk -F '::' '{print $1}' | uniq 2>&1`.split("\n")

    if endpoints.empty?
      puts "Failed to reach #{@route}/clusters, retrying"
      sleep(5)
      process_eds
      return
    end

    endpoints.each do |e|
      next if e.include?('*')

      if @envoy_endpoints[e].nil?
        @envoy_endpoints[e] = Time.now.to_i
      end
    end
  end

  def envoy_endpoints_to_csv
    out = []
    @envoy_endpoints.keys.each do |e|
      out << ["#{@envoy_endpoints[e]}000000000", @name, e, @route, "appears"].join(',')
    end
    out.join("\n")
  end
end

gateway_names = `kubectl get pods -n istio-system | grep ingressgateway | awk '{print $1}'`.split("\n")

gateways = []
gateway_names.each do |gw|
  gateways << Gateway.new(gw)
end

gateways.map(&:generate_route)

begin
  while true
    gateways.map(&:process_endpoints)

    open("endpoint_arrival.csv", 'w') do |f|
      f.puts "stamp,gateway,route,local_port,event"
      f.puts gateways.map(&:to_csv).join("\n")
    end

    gateways.map(&:process_eds)

    open("envoy_endpoint_arrival.csv", 'w') do |f|
      f.puts "stamp,gateway,route,local_port,event"
      f.puts gateways.map(&:envoy_endpoints_to_csv).join("\n")
    end
    sleep(0.25)
  end
rescue SignalException
  `pkill istioctl`
end

`pkill istioctl`

