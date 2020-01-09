#!/snap/bin/ruby

require 'json'

gateways = `kubectl get pods -n istio-system | grep ingressgateway | awk '{print $1}'`.split("\n")

pids = []
routes = {}
gateways.each do |g|
  pids << spawn("~/istio-1.4.2/bin/istioctl -n istio-system dashboard envoy #{g}", :out=>"route" )
  sleep(2)
  routes[File.read("route").split("\n").first] = g
end

puts routes
cluster_with_time_identified = Hash.new

begin
  while true
    routes.keys.each do |r|
      clusters = `curl -s "#{r}/config_dump" | jq .configs[4].dynamic_route_configs[].route_config.virtual_hosts[].name`.split("\n")
      clusters.each do |c|
        cr = "#{routes[r]},#{c}"
        if cluster_with_time_identified[cr].nil?
          cluster_with_time_identified[cr] = Time.now.to_i
        end
      end
    end

    open("endpoint_arrival.json", 'w') do |f|
      f.puts cluster_with_time_identified.to_json
    end
    sleep 1
  end
rescue SignalException
  pids.each do |pid|
    Process.kill("EXIT", pid)
  end
end

