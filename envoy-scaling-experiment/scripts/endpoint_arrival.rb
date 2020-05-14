#!/snap/bin/ruby

require 'json'
require 'pry'

class Gateway
  def initialize(name, address)
    @name = name
    @address = address
    @routes = {}
    @endpoints = {}
    @missing = Hash.new([])
  end

  def process_rds
    clusters = `curl -s "http://#{@address}/config_dump" | jq -r .configs[4].dynamic_route_configs[].route_config.virtual_hosts[]?.routes[0].route.cluster 2>&1`.split("\n")
    puts "#{Time.now.to_i},/config_dump"

    if clusters.empty?
      # puts "Failed to reach #{@address}/config_dump, retrying in 5 seconds"
      sleep(5)
      process_rds
      return
    end

    clusters.each do |c|
      next if c.include?('*')

      if @routes[c].nil?
        @routes[c] = Time.now.to_i
      end
    end

    @routes.keys.each do |e|
      if !clusters.include?(e)
        @missing[e] += [Time.now.to_i]
      end
    end
  end

  def routes_to_csv
    out = []
    @routes.keys.each do |e|
      out << ["#{@routes[e]}000000000", @name, e, @address, "appears"].join(',')
    end
    @missing.keys.each do |m|
      @missing[m].each do |time|
        out << ["#{time}000000000", @name, m, @address, "missing"].join(',')
      end
    end
    out.join("\n")
  end

  def process_eds
    # get endpoints with IPs only
    clusters_response = `2>&1 curl -sS --max-time 10 -w "%{http_code}" "http://#{@address}/clusters?format=json"`.split("\n")
    status_code = clusters_response.pop
    puts "#{(Time.now.to_f * 1e9).to_i},#{status_code}"

    clusters = JSON.parse(clusters_response.join("\n"))
    endpoints = clusters["cluster_statuses"]
      .select { |cluster| cluster["added_via_api"] }
      .map { |cluster| cluster["name"] }

    if endpoints.empty?
      # puts "Failed to reach #{@address}/clusters, retrying"
      sleep(1)
      process_eds
      return
    end

    endpoints.each do |e|
      next if e.include?('*')

      if @endpoints[e].nil?
        @endpoints[e] = (Time.now.to_f * 1e9).to_i
      end
    end
  end

  def endpoints_to_csv
    out = []
    @endpoints.keys.each do |e|
      out << ["#{@endpoints[e]}", @name, e, @address, "appears"].join(',')
    end
    out.join("\n")
  end
end

gateway = Gateway.new("gateway", ENV["ADMIN_ADDR"])

begin
  while true
    # gateway.process_rds
    gateway.process_eds

    # open("routes_arrival.csv", 'w') do |f|
    #   f.puts "stamp,gateway,route,local_port,event"
    #   f.puts gateway.routes_to_csv
    # end
    open("endpoints_arrival.csv", 'w') do |f|
      f.puts "stamp,gateway,route,local_port,event"
      f.puts gateway.endpoints_to_csv
    end
    sleep(0.25)
  end
end
