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
    @pid = spawn("istioctl -n istio-system dashboard envoy #{@name}", :out=>"route" )
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
        @endpoints[c] = (Time.now.to_f * 1e9).to_i
      end
    end

    @endpoints.keys.each do |e|
      if !clusters.include?(e)
        @missing[e] += [(Time.now.to_f * 1e9).to_i]
      end
    end
  end

  def to_csv
    out = []
    @endpoints.keys.each do |e|
      out << [@endpoints[e], @name, e, @route, "appears"].join(',')
    end
    @missing.keys.each do |m|
      @missing[m].each do |time|
        out << [time, @name, m, @route, "missing"].join(',')
      end
    end
    out.join("\n")
  end

  def get_ip_from_host_endpoint(endpoint)
    return endpoint&.dig("host_statuses", 0, "address", "socket_address", "address")
  end

  def process_eds
    # get endpoints with IPs only
    clusters_response = `2>&1 curl -sS --max-time 10 -w "%{http_code}" "#{@route}/clusters?format=json"`.split("\n")
    status_code = clusters_response.pop
    puts "#{(Time.now.to_f * 1e9).to_i},#{@name},request,#{status_code}"

    clusters = JSON.parse(clusters_response.join("\n"))
    endpoints = clusters["cluster_statuses"]
      .select { |cluster| cluster["added_via_api"] }

    if endpoints.empty?
      # puts "Failed to reach #{@address}/clusters, retrying"
      sleep(1)
      process_eds
      return
    end

    endpoints.each do |e|
      next if e["name"].include?('*')
      ip = get_ip_from_host_endpoint(e) || ""
      old_ip = get_ip_from_host_endpoint(@envoy_endpoints[e["name"]]&.[]("cluster")) || ""
      if !@envoy_endpoints[e["name"]].nil? && old_ip != ip
        puts("#{(Time.now.to_f * 1e9).to_i},#{@name},new_ip,#{e["name"]} #{old_ip} #{ip}")
      end

      if @envoy_endpoints[e["name"]].nil? || old_ip != ip
        @envoy_endpoints[e["name"]] = {
          "stamp" => (Time.now.to_f * 1e9).to_i,
          "cluster" => e,
        }
      end
    end
  end

  def envoy_endpoints_to_csv
    out = []
    @envoy_endpoints.keys.each do |e|
      endpoint = @envoy_endpoints[e]
      out << [endpoint["stamp"], @name, e, @route, "appears", get_ip_from_host_endpoint(endpoint["cluster"])].join(',')
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
      f.puts "stamp,gateway,route,local_port,event,address"
      f.puts gateways.map(&:envoy_endpoints_to_csv).join("\n")
    end
    sleep(0.25)
  end
rescue SignalException
  `pkill istioctl`
end

`pkill istioctl`

