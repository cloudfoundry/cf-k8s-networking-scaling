library(tidyverse)
library(gridExtra)
library(anytime)
library(scales)
options(digits.secs=6)                ## for fractional seconds below
Sys.setenv(TZ=anytime:::getTZ())      ## helper function to try to get TZ
filename = "./"

## Conversion Functions
mb_from_bytes = function(x) {
  return(round(x/(1024*1024), digits=1))
}

nanosecondsFromSeconds = function(x) {
  return(x*1000*1000*1000)
}
secondsFromNanoseconds = function(x) {
  return(round(x/(1000*1000*1000), digits=0))
}
minutesFromNanoseconds = function(x) {
  return(round(x/(60*1000*1000*1000), digits=0))
}

## Calculate timestamp when experiment began
times = read_csv(paste(filename, "importanttimes.csv", sep=""))
times.dpload = filter(times, event == "GENERATE DP LOAD")$stamp
times.cpload = filter(times, event == "GENERATE CP LOAD")$stamp
times.finish = filter(times, event == "TEST COMPLETE")$stamp
times.inbetween = times.cpload + (times.finish - times.cpload) / 10
zeroPoint = min(times$stamp)
maxSec = max(times$stamp)

## Create time axis for experiment
breaksFromZero = seq(from=zeroPoint, to=maxSec, by=10 * 60 * 1000 * 1000 * 1000)

secondsFromZero = function(x) {
  return (secondsFromNanoseconds(x - zeroPoint))
}

minutesFromZero = function(x) {
  return (round((x - zeroPoint)/(1000*1000*1000*60), digits=0))
}

experiment_time_x_axis = function(p) {
  return(
         p + xlab("Time (minutes)") +
         scale_x_continuous(labels=minutesFromZero, breaks=breaksFromZero)
       )
}

lines = function() {
  return(
    geom_vline(data=times, mapping=aes(xintercept=stamp), color="grey80")
  )
}

lineLabels = function() {
  return(
    geom_text(data=times, mapping=aes(x=stamp, y=0, label=event), size=2, angle=90, vjust=-0.4, hjust=0, color="grey25")
  )
}

## Place to customize theme settings for all charts
our_theme = function() {
  return(
         theme_linedraw()
  )
}

extractPilotConfigVersion = function(version) {
  return (
          str_extract(version, "\\d+$")
  )
}

## Constants
quantiles = c(0.68, 0.90, 0.99, 0.999, 1)
mylabels = c("p68", "p90", "p99", "p999", "max")
fiveSecondsInNanoseconds = 5 * 1000 * 1000 * 1000

print("Graph The Duration of Each Span")

# Spans from Envoy
discovery = read_csv("./envoy_ondiscoveryresponse.csv", col_types=cols(Version=col_character())) %>%
  arrange(Timestamp) %>%
  select(stamp=Timestamp, version=Version, duration=Duration, type=Type, nodeid=NodeID, routes=Resources, did_update=DidUpdate) %>%
  extract("nodeid", "gateway", regex = "istio-ingressgateway-([[:alnum:]]+-[[:alnum:]]+)\\.", convert=TRUE) %>%
  #filter(str_detect(routes, "app")) %>%
  mutate(version = extractPilotConfigVersion(version))

# Spans from Envoy when it sends requests to xDS server
discovery.request = read_csv("./envoy_senddiscoveryrequest.csv", col_types=cols(Version=col_character())) %>%
  arrange(Timestamp) %>%
  select(stamp=Timestamp, version=Version, duration=Duration, type=Type, nodeid=NodeID, routes=Resources) %>%
  extract("nodeid", "gateway", regex = "istio-ingressgateway-([[:alnum:]]+-[[:alnum:]]+)\\.", convert=TRUE) %>%
  #filter(str_detect(routes, "app")) %>%
  #filter(type != "Listener") %>%
  mutate(version = extractPilotConfigVersion(version))

# Pause spans from Envoy
pause = read_csv("./envoy_pause.csv", col_types=cols(Version=col_character())) %>%
  select(stamp=Timestamp, version=Version, duration=Duration, type=Type, nodeid=NodeID) %>%
  extract("nodeid", "gateway", regex = "istio-ingressgateway-([[:alnum:]]+-[[:alnum:]]+)\\.", convert=TRUE) %>%
  semi_join(discovery, by="version") %>%
  mutate(version = extractPilotConfigVersion(version))

# EDS updates from Envoy
# eds_update = read_csv("./envoy_eds_update.csv", col_types=cols(Version=col_character())) %>%
#   select(stamp=Timestamp, version=Version, duration=Duration, type=Type) %>%
#   mutate(type="EDS update")

# "Route works" spans from client vm
routes = read_csv("./user_data.csv") %>%
  select(version=`user id`, stamp = `start time`, estamp = `success time`, duration = `nanoseconds to first success`) %>%
  mutate(type="Route", gateway="gcp", gateway="client") %>%
  arrange(stamp)


# Pilot spans
pilot = read_csv("./pilot_traces.csv", col_types=cols(version=col_character())) %>%
  select(stamp, duration, stamp_version=version, resources, nodeid=hostname, skipped, gateway=envoy) %>%
  filter(str_detect(gateway, "router"), str_detect(skipped, "router", negate=TRUE)) %>%
  separate_rows(gateway, sep=",",convert = TRUE) %>%
  filter(str_detect(gateway, "router")) %>%
  extract("gateway", "gateway", regex = "istio-ingressgateway-([[:alnum:]]+-[[:alnum:]]+)\\.", convert=TRUE) %>%
  extract("resources", c("istiotype", "resource"), regex = "networking.istio.io/v1alpha3/([a-zA-Z]+)/(.*)$", convert=TRUE) %>%
  extract("nodeid", "pilot", regex = "istiod-([[:alnum:]]+-[[:alnum:]]+)", convert=TRUE) %>%
  mutate(version = extractPilotConfigVersion(stamp_version)) %>%
  mutate(type=recode(istiotype, ServiceEntry="Cluster", VirtualService="RouteConfiguration", Gateway="Listener"))

ddd = pilot %>% filter(version == "197") %>% group_by(gateway, type) %>% mutate(n = n()) %>% filter(n >= 2)
write_csv(ddd, "./debug.csv")
quit()

print("data loaded")
all_spans = bind_rows(
                      "envoy"=discovery,
                      "pause"=pause,
                      "client"=routes,
                      "pilot"=pilot,
                      .id="source"
                    ) %>%
  filter(version == "197")
#print(all_spans %>%
#  filter(type == "RouteConfiguration") %>%
#  arrange(stamp) %>%
#  #filter(stamp >= times.cpload, stamp <= times.finish) %>%
#  group_by(gateway) %>%
#  mutate(d = minutesFromNanoseconds(lead(stamp) - stamp)) %>%
#  select(stamp, version, d) %>%
#  arrange(desc(d)))

top_spans = all_spans %>%
  arrange(stamp) %>%
  mutate(estamp = stamp + duration) %>%
  #filter(estamp >= times.cpload, stamp <= times.finish) %>%
  mutate(name=paste(version, type, source, gateway, stamp),
         typeSource=paste(type, source),
         nodeSource=paste(source, gateway)) %>%
  pivot_longer(c(stamp, estamp), names_to="timetype", values_to="time")

timerange.min = min(select(top_spans, time))
timerange.max = max(select(top_spans, time))
top_spans.discovery_request = discovery.request %>%
  #filter(stamp >= timerange.min, stamp <= timerange.max) %>%
  arrange(stamp) %>%
  mutate(source="envoy",
         name=paste(version, type, source, gateway, stamp),
         typeSource=paste(type, "envoy"),
         nodeSource=paste(source, gateway),
         time=stamp) %>%
  filter(version=="197")
print(top_spans.discovery_request)

# top_spans.discovery_request$resource_version = group_indices(top_spans.discovery_request, new_resources)

# Calculate the labels for each version
labels = top_spans %>% filter(timetype=="stamp") %>%
  mutate(version = str_sub(version, start=-2L, end=-1L))
mycols <- c("Cluster envoy" = "firebrick4",
            # "Cluster envoy request" = "green",
            "Cluster navigator" = "darkblue",
            "Cluster pilot" = "darkblue",
            "Cluster pause" = "dimgray",
            "ClusterLoadAssignment envoy" = "firebrick1",
            # "ClusterLoadAssignment envoy request" = "green",
            "ClusterLoadAssignment navigator" = "dodgerblue2",
            "ClusterLoadAssignment pilot" = "dodgerblue2",
            "ClusterLoadAssignment pause" = "darkgray",
            "EDS update envoy" = "orangered3",
            "Listener envoy" = "orangered3",
            "RouteConfiguration envoy" = "indianred1",
            # "RouteConfiguration envoy request" = "green",
            "RouteConfiguration navigator" = "deepskyblue",
            "RouteConfiguration pilot" = "deepskyblue",
            "RouteConfiguration pause" = "snow2",
            "Route client" = "purple",
            "request" = "green",
            "response" = "black")
mycols.t <- c("Cluster" = "yellow",
            "ClusterLoadAssignment" = "orange",
            "RouteConfiguration" = "red")
mycols.s <- c("envoy" = "firebrick4",
            "client" = "purple",
            "pause" = "dimgray",
            "dropped" = "orange",
            "navigator" = "darkblue",
            "pilot" = "darkblue")

myshapes <- c("request" = 1,
              "response" = 5,
              "dropped" = 8)

mysizes <- c("request" = 1,
             "response" = 2,
             "dropped" = 2)

print("plotting")
ggplot(top_spans, aes(x=gateway, y=time, color=source, group=name)) +
  labs(title="Navigator and Envoy spans over time by type") +
  ylab("Time (minutes)") +
  scale_y_continuous(breaks = breaks_width(nanosecondsFromSeconds(10)),
                     # labels = function(breaks) {str_sub(secondsFromZero(breaks), start=-3L, end=-1L)}) +
                     labels = function(breaks) {secondsFromZero(breaks)}) +
  xlab("Span Types") +
  geom_line(size=0.5,alpha=0.7, lineend="square") + # spans
  geom_point(size=0.02,shape=15,color="black") + # spans
  geom_text(labels, mapping=aes(label=version),
            vjust = -2, size=1) +
  geom_point(top_spans.discovery_request, mapping=aes(group=typeSource),
             size=0.02, shape=8, color="orange", alpha=0.5) +
  coord_flip() +
  facet_wrap(vars(type), ncol=1, scales="free_y") +
  scale_colour_manual(values = mycols.s) +
  scale_shape_manual(values = myshapes) +
  scale_size_manual(values = mysizes) +
  our_theme() %+replace%
    theme(#strip.text.x = element_blank(),
          #strip.background = element_blank(),
          legend.position="bottom")

ggsave(paste(filename, "duration.png", sep=""), width=100, height=12, limitsize = FALSE)
quit()




print("histogram")
ggplot(durations, aes(x=duration, fill=typeSource)) +
  labs(title="Spans by Type and Source") +
  ylab("Count") +
  xlab("Duration (s)") +
  facet_wrap(vars(typeSource), ncol=1) +
  geom_histogram(bins=500) +
  scale_colour_manual(values = mycols) +
  scale_fill_manual(values = mycols) +
  scale_x_continuous(labels = secondsFromNanoseconds) +
  our_theme() %+replace%
    theme(strip.text.x = element_blank(),
          strip.background = element_blank(),
          legend.position="bottom")
ggsave(paste(filename, "span_duration_hist.png", sep=""), width=20, height=20)

quit()
print("Config duration")

discovery = read_csv("./envoy_ondiscoveryresponse.csv", col_types=cols(Version=col_character())) %>%
  arrange(Timestamp) %>%
  select(stamp=Timestamp, version=Version, duration=Duration, type=Type) %>%
  mutate(estamp = stamp + (duration * 1000)) %>%
  group_by(version) %>%
  summarize(duration=max(estamp) - min(stamp))

values = quantile(discovery$duration, quantiles)
tails = tibble(mylabels, values)
ggplot(tails, aes(x=mylabels, y=values)) +
  labs(title="Config Version Duration Percentiles") +
  ylab("Duration (s)") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  xlab("Percentile") +
  scale_x_discrete(limits=mylabels) +
  geom_line(mapping=aes(group="default does not work")) +
  geom_point() +
  # add line for goal
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")
ggsave(paste(filename, "duration_percentile.png", sep=""), width=7, height=5)

quit()

print("Graph Durations of Each Send")
discovery = read_csv("./envoy_ondiscoveryresponse.csv") %>%
  arrange(Timestamp) %>%
  select(version=Version, duration=Duration, type=Type, resources=Resources, size=PayloadSize) %>%
  mutate(durationms = duration / 1000)

navigator.sendconfig = read_csv("./sendconfigjaeger.csv") %>%
  select(version=Version, duration=Duration, type=Type, routes=Routes, size=PayloadSize) %>%
  mutate(durationms = duration / 1000)

normalize = function (c) {
  (c - min(c)) / (max(c) - min(c))
}

data = left_join(discovery, navigator.sendconfig, by=c("version","type")) %>%
  mutate(diff = durationms.y - durationms.x) %>%
  mutate(size_diff = size.y - size.x) %>%
  mutate(size_norm = normalize(size.x))
  # select(version, diff, type, size_norm)
# print(filter(data, size_diff != 0))


ggplot(data, group=type) +
  labs(title="Span Durations by Version") +
  ylab("Duration (ms)") +
  xlab("Version (timestamp)") +
  geom_point(mapping=aes(x=version, y=durationms.y, color=type, size=size_norm, shape="navigator"), alpha=0.4) +
  geom_point(mapping=aes(x=version, y=durationms.x, color=type, size=size_norm, shape="envoy"), alpha=0.4) +
  scale_colour_brewer(palette = "Set1") +
  geom_vline(xintercept = data$version, color="grey80", size=0.1) +
  our_theme() %+replace%
    theme(legend.position="right")

ggsave(paste(filename, "duration.png", sep=""), width=10, height=7)

quit()

ggplot(data) +
  labs(title="Duration of Configs over Time") +
  ylab("Duration (ms)") +
  # scale_y_continuous(labels=secondsFromNanoseconds) +
  xlab("Time (seconds)") +
  scale_x_continuous(labels=secondsFromZero, breaks=breaksFromZero) +
  lines() +
  geom_path(mapping=aes(x=Timestamp, y=Duration, color=Type), alpha=0.5) +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")

ggsave(paste(filename, "duration.png", sep=""))

print("Collect Route Status Data")
# timestamp, status, route, startstamp
routes = read_csv("./route-status.csv", col_types=cols(status=col_factor(), route=col_integer())) %>%
  drop_na() %>%
  filter(status == "200")

halfRoute = max(routes$route) # the route-status.csv will only include routes created during CP load

time_when_route_first_works = routes %>% select(stamp, route)

print("Collect Config Send Data")
xds = read_csv("./jaeger.csv")
xds = xds %>%
  separate_rows(Routes, convert = TRUE) %>%  # one row per observation of a route being configured
  filter(Routes < halfRoute) %>% # only include routes created during CP load
  drop_na() # sometimes route is NA, so drop those

# RouteConfiguration is the first type sent. ClusterLoadAllocation is last.
time_when_route_first_sent = xds %>% filter(Type == "RouteConfiguration") %>%
  select(stamp=Timestamp, route=Routes) %>%
  arrange(stamp) %>%
  group_by(route) %>%  slice(1L) %>% ungroup()

print("Collect /clusters Data")
time_when_cluster_appears = read_csv("endpoints_arrival.csv") %>%
  filter(str_detect(route, "service_.*")) %>%
  select(stamp, route) %>%
  extract("route", "route", regex = "service_([[:alnum:]]+)", convert=TRUE) %>%
  filter(route < halfRoute)

print("Calculate Control Plane Latency")
from_config_sent_to_works = left_join(time_when_route_first_sent, time_when_route_first_works, by=c("route")) %>%
  mutate(time_diff = stamp.y - stamp.x) # when it works minus when it was sent

from_clusters_to_works = left_join(time_when_cluster_appears, time_when_route_first_works, by=c("route")) %>%
  mutate(time_diff = stamp.y - stamp.x) # route works - cluster exists

from_config_sent_to_clusters = left_join(time_when_route_first_sent, time_when_cluster_appears, by=c("route")) %>%
  mutate(time_diff = stamp.y - stamp.x) # cluster exists - route sent

print("Calculate Quantiles")
from_config_sent_to_works.q = quantile(from_config_sent_to_works$time_diff, quantiles)
from_clusters_to_works.q = quantile(from_clusters_to_works$time_diff, quantiles)
cptails = tibble(mylabels,
                 from_config_sent=from_config_sent_to_works.q,
                 from_clusters=from_clusters_to_works.q) %>%
  pivot_longer(c(from_config_sent, from_clusters), names_to="type", values_to="time_diff")

print("Calculate Time Spent Per Step")
latencies_by_route = bind_rows(
    "from_config_sent_to_clusters"=from_config_sent_to_clusters,
    "from_clusters_to_works"=from_clusters_to_works,
    "from_config_sent_to_works"=from_config_sent_to_works,
    .id="type"
  )

# print(latencies_by_route %>% group_by(route) %>% summarize(n = n()) %>% filter(n != 3))

print("Graph Latency to Route Working")
tail_colors <- c("from_config_sent"="black", "from_clusters"="gray85")
tail_latencies = ggplot(cptails, aes(x=mylabels, y=time_diff)) +
  labs(title="Control Plane Latency by Percentile") +
  ylab("Latency (s)") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  xlab("Percentile") +
  scale_x_discrete(limits=mylabels) +
  geom_line(mapping=aes(color=type, group=type)) +
  geom_point() +
  geom_text(vjust = -0.5, aes(label = secondsFromNanoseconds(time_diff))) +
  scale_colour_manual(values = tail_colors) +
  our_theme() %+replace%
    theme(legend.position="bottom")

latencies_bars = ggplot(latencies_by_route, aes(x=route, y=time_diff, group=type, color=type)) +
  labs(title="Control Plane Latency by Route") +
  ylab("Latency (s)") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  xlab("Route") +
  # facet_wrap(vars(type), ncol=1) +
  # geom_point(mapping=aes(y=stamp.x), group="x", color="black", alpha=0.25, size=0.1) +
  geom_line(alpha=0.5) +
  # stat_summary_bin(fun.y = "max", bins=100, geom="line") +
  # stat_summary_bin(aes(color="max"), fun.y = "max", bins=100, geom="line") +
  # stat_summary_bin(aes(color="median"), fun.y = "median", bins=100, geom="line") +
  # stat_summary_bin(aes(color="min"), fun.y = "min", bins=100, geom="line") +
  geom_hline(yintercept = 0, color="grey45") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")

ggsave(paste(filename, "latency.png", sep=""),
       arrangeGrob(tail_latencies, latencies_bars), width=7, height=10)

# quit()


print("Graph Configs Sent")
xds.version_incremental = read_csv('./sendconfigjaeger.csv') %>%
  select(stamp=Timestamp, route=Routes, type=Type, version=Version) %>%
  arrange(version)
xds.version_incremental$version = group_indices(xds.version_incremental, version)

config_apply_total_time_per_version = xds.version_incremental %>%
  group_by(version) %>%
  summarize(time_diff = max(stamp) - min(stamp), n = n())

versions_with_not_all_configs = filter(config_apply_total_time_per_version, n != 3)

config_apply_type_by_version_graph = ggplot(config_apply_total_time_per_version, aes(x=version, y=time_diff)) +
  labs(title="Config Apply Time by Version") +
  ylab("Time (seconds)") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  xlab("Version") +
  geom_point(alpha=0.5, size=0.4) +
  geom_vline(xintercept = versions_with_not_all_configs$version, color="grey80", size=0.1) +
  scale_size_area() +
  our_theme() %+replace%
    theme(legend.position="bottom")

ggsave(paste(filename, "config.png", sep=""), config_apply_type_by_version_graph, width=7, height=3)


envoy_requests = read_csv('./envoy_requests.csv')

experiment_time_x_axis(ggplot(envoy_requests, aes(x=stamp, y=status, color=status)) +
  labs(title="Envoy Polling") +
  lines() +
  geom_jitter(alpha=0.5) +
  our_theme() %+replace%
    theme(legend.position="bottom"))

ggsave(paste(filename, "polling.png", sep=""))



# # configs_sent = ggplot(xds) +
# #   labs(title="Config Sent over Time") +
# #   ylab("Route Number") +
# #   facet_wrap(vars(Type), ncol=1) +
# #   geom_point(mapping=aes(x=Date, y=Routes, color=Version), alpha=0.5, size=0.4) +
# #   scale_size_area() +
# #   scale_colour_distiller(palette="Spectral") +
# #   our_theme() %+replace%
# #     theme(legend.position="none")


# # Get the first time a route number appears in each type of config
# configs.all = xds %>%
#   select(stamp=Timestamp, route=Routes, type=Type, version=Version) %>%
#   arrange(version, route) %>%
#   group_by(type, route) %>% slice(1L) %>% ungroup()


# # # For each type of config, get the relative time from
# # # when the first config type for a new route was sent
# # scale_times.per_route = configs.all %>% group_by(route) %>%
# #   summarize(first = min(version)) %>%
# #   select(route, first) %>%
# #   right_join(configs.all, by="route") %>%
# #   mutate(scaled_time = version - first)

# # scale_times.per_version = xds.version_inc %>% group_by(version) %>%
# #   summarize(first = min(stamp)) %>%
# #   select(version, first) %>%
# #   right_join(xds.version_inc, by="version") %>%
# #   mutate(scaled_time = stamp - first)

# # timestampByType.per_route = ggplot(scale_times.per_route, aes(x=route)) +
# #   labs(title="Difference Between First and Last Config Sent Per Route") +
# #   xlab("Route Number") +
# #   # coord_cartesian(xlim = c(0, 100), ylim = c(1584121000, 1584121500)) + # zoom in on first half of graph
# #   # ylab("Latency from first config sent (s)") +
# #   # scale_y_continuous(labels=secondsFromNanoseconds) +
# #   ylab("Version") +
# #   scale_colour_brewer(palette = "Set1") +
# #   scale_size_area() +
# #   geom_point(mapping =  aes(y=version, color=type), size=0.1, alpha=0.40) +
# #   our_theme() %+replace%
# #     theme(legend.position="bottom")

# # timestampByType.per_version = ggplot(scale_times.per_version, aes(x=version)) +
# #   labs(title="Difference Between First and Last Config Sent Per Version") +
# #   xlab("Version") +
# #   ylab("Latency from first config sent (s)") +
# #   scale_y_continuous(labels=secondsFromNanoseconds) +
# #   scale_colour_brewer(palette = "Set1") +
# #   scale_size_area() +
# #   geom_vline(xintercept = versions_not_full$version, color="grey80", size=0.1) +
# #   geom_point(mapping =  aes(y=scaled_time, color=type), size=0.1) +
# #   our_theme() %+replace%
# #     theme(legend.position="bottom")

# # # ggsave(paste(filename, "config.png", sep=""), arrangeGrob(timestampByType.per_route, timestampByType.per_version) , width=7, height=11)
# # ggsave(paste(filename, "config.png", sep=""), arrangeGrob(configs_sent, timestampByType.per_route, timestampByType.per_version) , width=7, height=11)

# print("Latency between Config Sent and Route Working")
# configs = configs.all %>% filter(type == "RouteConfiguration")

# observations = routes %>% filter(status == "200") %>%
#   select(stamp, route) %>%
#   arrange(stamp, route) %>%
#   group_by(route) %>%  slice(1L) %>% ungroup()

# # all.withtimes = left_join(configs, observations, by="route") %>%
# #   filter(route < halfRoute) %>%
# #   mutate(time_diff = stamp.y - stamp.x)

# # latency_by_route = ggplot(all.withtimes) +
# #   labs(title="Latency from Config Sent to Route returns 200") +
# #   ylab("Time (seconds)") +
# #   scale_y_continuous(labels=secondsFromNanoseconds) +
# #   xlab("Route Number") +
# #   geom_point(mapping=aes(y=time_diff, x=route)) +
# #   our_theme() %+replace%
# #     theme(legend.position="bottom")

# # values = quantile(all.withtimes$time_diff, quantiles)
# # cptails = tibble(mylabels, values)
# # tail_latencies = ggplot(cptails, aes(x=mylabels, y=values)) +
# #   labs(title="Control Plane Latency by Percentile") +
# #   ylab("Latency (s)") +
# #   scale_y_continuous(labels=secondsFromNanoseconds) +
# #   xlab("Percentile") +
# #   scale_x_discrete(limits=mylabels) +
# #   geom_line(mapping=aes(group="default does not work")) +
# #   geom_point() +
# #   # add line for goal
# #   geom_hline(yintercept = fiveSecondsInNanoseconds, color="grey80") +
# #   geom_text(mapping = aes(y=fiveSecondsInNanoseconds, x="p68", label="GOAL 5sec at p95"), size=2, vjust=1.5, hjust=1, color="grey25") +
# #   scale_colour_brewer(palette = "Set1") +
# #   our_theme() %+replace%
# #     theme(legend.position="bottom")

# # # ggsave(paste(filename, "latency.png", sep=""), arrangeGrob(tail_latencies, latency_by_route), width=7, height=10)

print("Reading in pod-by-node data")
# Read in timestamp-node-pod data
nodes4pods = read_csv(paste(filename, "nodes4pods.csv", sep="")) %>%
  extract(pod, "podtype", "([A-Za-z][A-Za-z0-9]+-?[A-Za-z]+)", remove=FALSE) %>%
  extract(node, "nodename", "gke-.+-([A-Za-z0-9]+)")
podcountsbynodetime = nodes4pods %>% select(-pod) %>% group_by(nodename, podtype, stamp) %>% summarize(n=n())
podtypesbynode = nodes4pods %>% select(nodename, podtype) %>% distinct() %>% group_by(nodename) %>% summarize(podtypes = str_c(podtype, collapse=":"))

print("Reading in node cpu/mem data")
# Read in timestamp-node-cpu-mem data
nodeusage = read_csv(paste(filename, "nodemon.csv", sep=""), col_types=cols(percent=col_number())) %>%
  extract(nodename, "nodename", "gke-.+-([A-Za-z0-9]+)") %>%
  pivot_wider(names_from=type, values_from=percent, values_fn = list(percent = max)) %>%
  left_join(podtypesbynode, by="nodename", name="podtypes") %>%
  mutate(hasEnvoy = if_else(str_detect(podtypes, "gateway"), "with Envoy", "without Envoy"))

print("Picking busiest nodes")
busynodenames = nodeusage %>% group_by(nodename) %>% summarize(maxcpu = max(cpu, na.rm=TRUE)) %>% top_n(3,maxcpu)
busynodes = busynodenames %>% left_join(nodeusage) %>% select(timestamp, nodename, cpu, memory, hasEnvoy)

nodeusage = nodeusage %>% gather(type, percent, -nodename, -timestamp, -hasEnvoy, -podtypes)
busynodes = busynodes %>% gather(type, percent, -nodename, -timestamp, -hasEnvoy)

print("Usage by Node")
experiment_time_x_axis(ggplot(nodeusage) +
  labs(title = "Node Utilization", subtitle="100% = utilizing the whole machine") +
  ylab("Utilization %") + ylim(0,100) + lines() +
  facet_wrap(vars(hasEnvoy, type), ncol=1) +
  geom_line(mapping = aes(x=timestamp,y=percent, group=nodename), color="gray15", alpha=0.15) +
  geom_line(busynodes, mapping=aes(x=timestamp,y=percent, color=nodename), alpha=0.75) +
  our_theme() %+replace%
    theme(legend.position="bottom"))
ggsave(paste(filename, "nodemon.png", sep=""), width=7, height=12)

podcountsbusynodes = podcountsbynodetime %>% right_join(busynodenames) %>%
  filter(podtype != "prometheus-to", podtype != "kube-proxy", podtype != "fluentd-gcp") %>%
  mutate(podcategory = if_else(str_detect(podtype, "httpbin"), "workload", "system"))

print("Pods on Busy Nodes")
experiment_time_x_axis(ggplot(podcountsbusynodes) +
  labs(title = "Pods by Node over Time") + lines() +
  facet_wrap(vars(nodename), ncol=1) +
  geom_count(mapping=aes(x=stamp,y=podtype,size=n,color=podtype), alpha=0.5) +
  scale_size_area() +
  our_theme() %+replace%
    theme(legend.position="bottom"))
numberofbusynodes = n_distinct(podcountsbusynodes$nodename)
ggsave(paste(filename, "nodes4pods.png", sep=""), width=7, height=2.5 * numberofbusynodes)

print("Client Usage")
memstats = read_csv(paste(filename, "memstats.csv", sep=""))
cpustats = read_csv(paste(filename, "cpustats.csv", sep=""))
experiment_time_x_axis(ggplot(memstats) +
  labs(title = "Client Resource Usage") +
  ylab("Utilization %") + ylim(0,100) + lines() +
  geom_line(mapping=aes(x=stamp,y=(used/total)*100, colour="memory")) +
  geom_line(data=cpustats,mapping=aes(x=stamp,y=(100-idle), group=cpuid, colour=cpuid)) +
  guides(colour = guide_legend(title = "CPU #")) +
  lineLabels() +
   our_theme() %+replace%
     theme(legend.position="bottom"))
ggsave(paste(filename, "resources.png", sep=""), width=7, height=3.5)

print("Client Network")
ifstats = read_csv(paste(filename, "ifstats.csv", sep=""))
experiment_time_x_axis(ggplot(ifstats) +
  labs(title = "Client Network Usage") +
  ylab("Speed (kb/s)") + lines() +
  geom_line(mapping=aes(x=stamp,y=down, colour="down")) +
  geom_line(mapping=aes(x=stamp,y=up, colour="up")) +
  guides(colour = guide_legend(title = "Key")) +
  lineLabels() +
   our_theme() %+replace%
     theme(legend.position="bottom"))
ggsave(paste(filename, "ifstats.png", sep=""), width=7, height=3.5)

#library(tidyverse)
#library(gridExtra)
#library(anytime)
#library(scales)
#options(digits.secs=6)                ## for fractional seconds below
#Sys.setenv(TZ=anytime:::getTZ())      ## helper function to try to get TZ
#filename = "./"

### Conversion Functions
#mb_from_bytes = function(x) {
#  return(round(x/(1024*1024), digits=1))
#}

#nanosecondsFromSeconds = function(x) {
#  return(x*1000*1000*1000)
#}
#secondsFromNanoseconds = function(x) {
#  return(round(x/(1000*1000*1000), digits=1))
#}

### Calculate timestamp when experiment began
#times = read_csv(paste(filename, "importanttimes.csv", sep=""))
#zeroPoint = min(times$stamp)
#maxSec = max(times$stamp)
#times.dpload = filter(times, event == "GENERATE DP LOAD")$stamp
#times.cpload = filter(times, event == "GENERATE CP LOAD")$stamp
#times.cpcomplete = filter(times, event == "CP LOAD COMPLETE")$stamp
#times.finish = filter(times, event == "TEST COMPLETE")$stamp


### Create time axis for experiment
#breaksFromZero = seq(from=zeroPoint, to=maxSec, by=10 * 60 * 1000 * 1000 * 1000)

#secondsFromZero = function(x) {
#  return (secondsFromNanoseconds(x - zeroPoint))
#}

#minutesFromZero = function(x) {
#  return (secondsFromZero(x) / 60)
#}

#experiment_time_x_axis = function(p) {
#  return(
#         p + xlab("Time (minutes)") +
#         scale_x_continuous(labels=minutesFromZero, breaks=breaksFromZero)
#       )
#}

#lines = function() {
#  return(
#    geom_vline(data=times, mapping=aes(xintercept=stamp), color="grey80")
#  )
#}

#lineLabels = function() {
#  return(
#    geom_text(data=times, mapping=aes(x=stamp, y=0, label=event), size=2, angle=90, vjust=-0.4, hjust=0, color="grey25")
#  )
#}

### Place to customize theme settings for all charts
#our_theme = function() {
#  return(
#         theme_linedraw()
#  )
#}

### Constants
#quantiles = c(0.68, 0.90, 0.99, 0.999, 1)
#mylabels = c("p68", "p90", "p99", "p999", "max")
#fiveSecondsInNanoseconds = 5 * 1000 * 1000 * 1000

#print("Graph The Duration of Each Span")

## Spans from Envoy
#discovery = read_csv("./envoy_ondiscoveryresponse.csv", col_types=cols(Version=col_character())) %>%
#  arrange(Timestamp) %>%
#  select(stamp=Timestamp, version=Version, duration=Duration, type=Type, nodeid=NodeID, routes=Resources) %>%
#  extract("nodeid", "gateway", regex = "(istio-ingressgateway-[[:alnum:]]+-[[:alnum:]]+)\\.", convert=TRUE) %>%
#  filter(str_detect(routes, "httpbin"))

## Pause spans from Envoy
#pause = read_csv("./envoy_pause.csv", col_types=cols(Version=col_character())) %>%
#  select(stamp=Timestamp, version=Version, duration=Duration, type=Type, nodeid=NodeID) %>%
#  extract("nodeid", "gateway", regex = "(istio-ingressgateway-[[:alnum:]]+-[[:alnum:]]+)\\.", convert=TRUE) %>%
#  semi_join(discovery, by="version")

## "Route works" spans from client vm
#routes = read_csv("./user_data.csv") %>%
#  select(version=`user id`, stamp = `start time`, estamp = `success time`, duration = `nanoseconds to first success`) %>%
#  mutate(type="Route", gateway="gcp") %>%
#  arrange(stamp)
## halfRoute = max(routes$route) # the route-status.csv will only include routes created during CP load
## routes = routes %>% filter(route < halfRoute)

## Get config version to new route mapping
## routes_by_config = read_csv("./sendconfigjaeger.csv", col_types=cols(Version=col_character())) %>%
##   select(version=Version, routes=Routes, type=Type) %>%
##   filter(type == "RouteConfiguration") %>%
##   separate_rows(routes, convert = TRUE) %>%  # one row per observation of a route being configured
##   filter(routes < halfRoute) %>% # only include routes created during CP load
##   group_by(routes) %>% summarize(version = min(version)) %>%
##   select(route=routes, version)
## when_route_works = left_join(routes, routes_by_config, by="route")

#print("data loaded")
#all_spans = bind_rows("envoy"=discovery, "pause"=pause, "client"=routes, .id="source") %>%
#  filter(type != "Listener")
#durations = all_spans %>% mutate(asdf=paste(type, source)) %>%
#  select(asdf, type, source, version, duration)
##last_success = tail(routes, 1L)$estamp
## top_versions = all_spans %>% filter(type=="Route") %>% arrange(stamp) %>% slice(290:300) #top_n(10, duration)
## avg_versions = all_spans %>% filter(type=="Route") %>% top_n(10, -duration)
#top_spans = all_spans %>% #semi_join(top_versions, by="version") %>%
#  arrange(stamp) %>%
#  mutate(estamp = stamp + duration,
#         name=paste(version, type, source),
#         typeSource=paste(type, source)) %>%
#  pivot_longer(c(stamp, estamp), names_to="timetype", values_to="time")
#print(top_spans %>% filter(type!="Route"))
## Calculate dotted lines between the rows for each version
##x.breaks = (top_spans %>% group_by(version, name) %>% summarize(m=1) %>% summarize(n=n()) %>% mutate(s = cumsum(n)))$s + 0.5


#envoyarrival = read_csv("./envoy_endpoint_arrival.csv") %>%
#  extract("route", c("user","group"), regex = "httpbin-([[:alnum:]]+)-g([[:alnum:]]+)\\.", convert=TRUE) %>%
#  drop_na(group) %>%
#  mutate(user = ifelse(user == 0, 5.5, 4.5)) %>%
#  select(stamp, gateway, user, group) %>%
#  mutate(typeSource = "Cluster /clusters")
#print(envoyarrival)


#labels = top_spans %>% filter(timetype=="stamp")
#mycols <- c("Cluster envoy" = "firebrick4",
#            "Cluster /clusters" = "darkblue",
#            "Cluster pause" = "dimgray",
#            "ClusterLoadAssignment envoy" = "firebrick1",
#            "One" = "dodgerblue2",
#            "ClusterLoadAssignment pause" = "darkgray",
#            "RouteConfiguration envoy" = "indianred1",
#            "RouteConfiguration navigator" = "deepskyblue",
#            "RouteConfiguration pause" = "snow2",
#            "Zero" = "orange",
#            "Route client" = "purple")
#mycols.t <- c("Cluster" = "yellow",
#            "ClusterLoadAssignment" = "orange",
#            "RouteConfiguration" = "red")
#mycols.s <- c("envoy" = "yellow",
#            "navigator" = "blue",
#            "pause" = "gray")

#print("plotting")
#ggplot(top_spans, aes(x=typeSource, y=time)) +
#  labs(title="Envoy spans by config version and type") +
#  facet_wrap(vars(gateway), ncol=1, scale="free_y") +
#  geom_line(size=1,alpha=0.5, lineend="square", mapping= aes(group=name, color=typeSource)) +
#  geom_point(data=envoyarrival, mapping=aes(y=stamp, x=user, color=typeSource), alpha=0.01, size=0.5) +
#  scale_y_continuous(breaks = breaks_width(nanosecondsFromSeconds(60)),
#                     labels = function(breaks) {rep_along(breaks, element_blank())},
#                     limits=c(times.cpload, times.cpcomplete)) +
#  geom_hline(data=times, mapping=aes(yintercept=stamp), color="grey80")+
#  geom_text(data=times, mapping=aes(x=0, y=stamp, label=event), size=2, angle=90, vjust=-0.4, hjust=0, color="grey25")+
#  ylab("Time (minutes)") +
#  xlab("Gateway") +
#  scale_x_discrete(labels = element_blank()) +
#  coord_flip() +
#  scale_colour_manual(values = mycols) +
#  #scale_colour_distiller(palette = "Spectral") +
#  our_theme() %+replace%
#    theme(strip.text.x = element_blank(),
#          strip.background = element_blank(),
#          legend.position="bottom")

#ggsave(paste(filename, "duration.png", sep=""), width=30, height=10)

#print("histogram")
#ggplot(durations, aes(x=duration, fill=asdf)) +
#  labs(title="Spans by Type and Source") +
#  ylab("Count") +
#  xlab("Duration (s)") +
#  facet_wrap(vars(asdf), ncol=1) +
#  geom_histogram(bins=500) +
#  scale_colour_manual(values = mycols) +
#  scale_fill_manual(values = mycols) +
#  scale_x_continuous(labels = secondsFromNanoseconds) +
#  our_theme() %+replace%
#    theme(strip.text.x = element_blank(),
#          strip.background = element_blank(),
#          legend.position="bottom")
#ggsave(paste(filename, "span_duration_hist.png", sep=""), width=20, height=20)

#quit()
#print("Config duration")

#discovery = read_csv("./envoy_ondiscoveryresponse.csv", col_types=cols(Version=col_character())) %>%
#  arrange(Timestamp) %>%
#  select(stamp=Timestamp, version=Version, duration=Duration, type=Type) %>%
#  mutate(estamp = stamp + (duration * 1000)) %>%
#  group_by(version) %>%
#  summarize(duration=max(estamp) - min(stamp))

#values = quantile(discovery$duration, quantiles)
#tails = tibble(mylabels, values)
#ggplot(tails, aes(x=mylabels, y=values)) +
#  labs(title="Config Version Duration Percentiles") +
#  ylab("Duration (s)") +
#  scale_y_continuous(labels=secondsFromNanoseconds) +
#  xlab("Percentile") +
#  scale_x_discrete(limits=mylabels) +
#  geom_line(mapping=aes(group="default does not work")) +
#  geom_point() +
#  # add line for goal
#  scale_colour_brewer(palette = "Set1") +
#  our_theme() %+replace%
#    theme(legend.position="bottom")
#ggsave(paste(filename, "duration_percentile.png", sep=""), width=7, height=5)

#quit()

#print("Graph Durations of Each Send")
#discovery = read_csv("./envoy_ondiscoveryresponse.csv") %>%
#  arrange(Timestamp) %>%
#  select(version=Version, duration=Duration, type=Type, resources=Resources, size=PayloadSize) %>%
#  mutate(durationms = duration / 1000)

#sendconfig = read_csv("./sendconfigjaeger.csv") %>%
#  select(version=Version, duration=Duration, type=Type, routes=Routes, size=PayloadSize) %>%
#  mutate(durationms = duration / 1000)

#normalize = function (c) {
#  (c - min(c)) / (max(c) - min(c))
#}

#data = left_join(discovery, sendconfig, by=c("version","type")) %>%
#  mutate(diff = durationms.y - durationms.x) %>%
#  mutate(size_diff = size.y - size.x) %>%
#  mutate(size_norm = normalize(size.x))
#  # select(version, diff, type, size_norm)
## print(filter(data, size_diff != 0))


#ggplot(data, group=type) +
#  labs(title="Span Durations by Version") +
#  ylab("Duration (ms)") +
#  xlab("Version (timestamp)") +
#  geom_point(mapping=aes(x=version, y=durationms.y, color=type, size=size_norm, shape="navigator"), alpha=0.4) +
#  geom_point(mapping=aes(x=version, y=durationms.x, color=type, size=size_norm, shape="envoy"), alpha=0.4) +
#  scale_colour_brewer(palette = "Set1") +
#  geom_vline(xintercept = data$version, color="grey80", size=0.1) +
#  our_theme() %+replace%
#    theme(legend.position="right")

#ggsave(paste(filename, "duration.png", sep=""), width=10, height=7)

#quit()

#ggplot(data) +
#  labs(title="Duration of Configs over Time") +
#  ylab("Duration (ms)") +
#  # scale_y_continuous(labels=secondsFromNanoseconds) +
#  xlab("Time (seconds)") +
#  scale_x_continuous(labels=secondsFromZero, breaks=breaksFromZero) +
#  lines() +
#  geom_path(mapping=aes(x=Timestamp, y=Duration, color=Type), alpha=0.5) +
#  scale_colour_brewer(palette = "Set1") +
#  our_theme() %+replace%
#    theme(legend.position="bottom")

#ggsave(paste(filename, "duration.png", sep=""))

#print("Collect Route Status Data")
## timestamp, status, route, startstamp
#routes = read_csv("./route-status.csv", col_types=cols(status=col_factor(), route=col_integer())) %>%
#  drop_na() %>%
#  filter(status == "200")

#halfRoute = max(routes$route) # the route-status.csv will only include routes created during CP load

#time_when_route_first_works = routes %>% select(stamp, route)

#print("Collect Config Send Data")
#xds = read_csv("./jaeger.csv")
#xds = xds %>%
#  separate_rows(Routes, convert = TRUE) %>%  # one row per observation of a route being configured
#  filter(Routes < halfRoute) %>% # only include routes created during CP load
#  drop_na() # sometimes route is NA, so drop those

## RouteConfiguration is the first type sent. ClusterLoadAllocation is last.
#time_when_route_first_sent = xds %>% filter(Type == "RouteConfiguration") %>%
#  select(stamp=Timestamp, route=Routes) %>%
#  arrange(stamp) %>%
#  group_by(route) %>%  slice(1L) %>% ungroup()

#print("Collect /clusters Data")
#time_when_cluster_appears = read_csv("endpoints_arrival.csv") %>%
#  filter(str_detect(route, "service_.*")) %>%
#  select(stamp, route) %>%
#  extract("route", "route", regex = "service_([[:alnum:]]+)", convert=TRUE) %>%
#  filter(route < halfRoute)

#print("Calculate Control Plane Latency")
#from_config_sent_to_works = left_join(time_when_route_first_sent, time_when_route_first_works, by=c("route")) %>%
#  mutate(time_diff = stamp.y - stamp.x) # when it works minus when it was sent

#from_clusters_to_works = left_join(time_when_cluster_appears, time_when_route_first_works, by=c("route")) %>%
#  mutate(time_diff = stamp.y - stamp.x) # route works - cluster exists

#from_config_sent_to_clusters = left_join(time_when_route_first_sent, time_when_cluster_appears, by=c("route")) %>%
#  mutate(time_diff = stamp.y - stamp.x) # cluster exists - route sent

#print("Calculate Quantiles")
#from_config_sent_to_works.q = quantile(from_config_sent_to_works$time_diff, quantiles)
#from_clusters_to_works.q = quantile(from_clusters_to_works$time_diff, quantiles)
#cptails = tibble(mylabels,
#                 from_config_sent=from_config_sent_to_works.q,
#                 from_clusters=from_clusters_to_works.q) %>%
#  pivot_longer(c(from_config_sent, from_clusters), names_to="type", values_to="time_diff")

#print("Calculate Time Spent Per Step")
#latencies_by_route = bind_rows(
#    "from_config_sent_to_clusters"=from_config_sent_to_clusters,
#    "from_clusters_to_works"=from_clusters_to_works,
#    "from_config_sent_to_works"=from_config_sent_to_works,
#    .id="type"
#  )

## print(latencies_by_route %>% group_by(route) %>% summarize(n = n()) %>% filter(n != 3))

#print("Graph Latency to Route Working")
#tail_colors <- c("from_config_sent"="black", "from_clusters"="gray85")
#tail_latencies = ggplot(cptails, aes(x=mylabels, y=time_diff)) +
#  labs(title="Control Plane Latency by Percentile") +
#  ylab("Latency (s)") +
#  scale_y_continuous(labels=secondsFromNanoseconds) +
#  xlab("Percentile") +
#  scale_x_discrete(limits=mylabels) +
#  geom_line(mapping=aes(color=type, group=type)) +
#  geom_point() +
#  geom_text(vjust = -0.5, aes(label = secondsFromNanoseconds(time_diff))) +
#  scale_colour_manual(values = tail_colors) +
#  our_theme() %+replace%
#    theme(legend.position="bottom")

#latencies_bars = ggplot(latencies_by_route, aes(x=route, y=time_diff, group=type, color=type)) +
#  labs(title="Control Plane Latency by Route") +
#  ylab("Latency (s)") +
#  scale_y_continuous(labels=secondsFromNanoseconds) +
#  xlab("Route") +
#  # facet_wrap(vars(type), ncol=1) +
#  # geom_point(mapping=aes(y=stamp.x), group="x", color="black", alpha=0.25, size=0.1) +
#  geom_line(alpha=0.5) +
#  # stat_summary_bin(fun.y = "max", bins=100, geom="line") +
#  # stat_summary_bin(aes(color="max"), fun.y = "max", bins=100, geom="line") +
#  # stat_summary_bin(aes(color="median"), fun.y = "median", bins=100, geom="line") +
#  # stat_summary_bin(aes(color="min"), fun.y = "min", bins=100, geom="line") +
#  geom_hline(yintercept = 0, color="grey45") +
#  scale_colour_brewer(palette = "Set1") +
#  our_theme() %+replace%
#    theme(legend.position="bottom")

#ggsave(paste(filename, "latency.png", sep=""),
#       arrangeGrob(tail_latencies, latencies_bars), width=7, height=10)

## quit()


#print("Graph Configs Sent")
#xds.version_incremental = read_csv('./sendconfigjaeger.csv') %>%
#  select(stamp=Timestamp, route=Routes, type=Type, version=Version) %>%
#  arrange(version)
#xds.version_incremental$version = group_indices(xds.version_incremental, version)

#config_apply_total_time_per_version = xds.version_incremental %>%
#  group_by(version) %>%
#  summarize(time_diff = max(stamp) - min(stamp), n = n())

#versions_with_not_all_configs = filter(config_apply_total_time_per_version, n != 3)

#config_apply_type_by_version_graph = ggplot(config_apply_total_time_per_version, aes(x=version, y=time_diff)) +
#  labs(title="Config Apply Time by Version") +
#  ylab("Time (seconds)") +
#  scale_y_continuous(labels=secondsFromNanoseconds) +
#  xlab("Version") +
#  geom_point(alpha=0.5, size=0.4) +
#  geom_vline(xintercept = versions_with_not_all_configs$version, color="grey80", size=0.1) +
#  scale_size_area() +
#  our_theme() %+replace%
#    theme(legend.position="bottom")

#ggsave(paste(filename, "config.png", sep=""), config_apply_type_by_version_graph, width=7, height=3)


#envoy_requests = read_csv('./envoy_requests.csv')

#experiment_time_x_axis(ggplot(envoy_requests, aes(x=stamp, y=status, color=status)) +
#  labs(title="Envoy Polling") +
#  lines() +
#  geom_jitter(alpha=0.5) +
#  our_theme() %+replace%
#    theme(legend.position="bottom"))

#ggsave(paste(filename, "polling.png", sep=""))



## # configs_sent = ggplot(xds) +
## #   labs(title="Config Sent over Time") +
## #   ylab("Route Number") +
## #   facet_wrap(vars(Type), ncol=1) +
## #   geom_point(mapping=aes(x=Date, y=Routes, color=Version), alpha=0.5, size=0.4) +
## #   scale_size_area() +
## #   scale_colour_distiller(palette="Spectral") +
## #   our_theme() %+replace%
## #     theme(legend.position="none")


## # Get the first time a route number appears in each type of config
## configs.all = xds %>%
##   select(stamp=Timestamp, route=Routes, type=Type, version=Version) %>%
##   arrange(version, route) %>%
##   group_by(type, route) %>% slice(1L) %>% ungroup()


## # # For each type of config, get the relative time from
## # # when the first config type for a new route was sent
## # scale_times.per_route = configs.all %>% group_by(route) %>%
## #   summarize(first = min(version)) %>%
## #   select(route, first) %>%
## #   right_join(configs.all, by="route") %>%
## #   mutate(scaled_time = version - first)

## # scale_times.per_version = xds.version_inc %>% group_by(version) %>%
## #   summarize(first = min(stamp)) %>%
## #   select(version, first) %>%
## #   right_join(xds.version_inc, by="version") %>%
## #   mutate(scaled_time = stamp - first)

## # timestampByType.per_route = ggplot(scale_times.per_route, aes(x=route)) +
## #   labs(title="Difference Between First and Last Config Sent Per Route") +
## #   xlab("Route Number") +
## #   # coord_cartesian(xlim = c(0, 100), ylim = c(1584121000, 1584121500)) + # zoom in on first half of graph
## #   # ylab("Latency from first config sent (s)") +
## #   # scale_y_continuous(labels=secondsFromNanoseconds) +
## #   ylab("Version") +
## #   scale_colour_brewer(palette = "Set1") +
## #   scale_size_area() +
## #   geom_point(mapping =  aes(y=version, color=type), size=0.1, alpha=0.40) +
## #   our_theme() %+replace%
## #     theme(legend.position="bottom")

## # timestampByType.per_version = ggplot(scale_times.per_version, aes(x=version)) +
## #   labs(title="Difference Between First and Last Config Sent Per Version") +
## #   xlab("Version") +
## #   ylab("Latency from first config sent (s)") +
## #   scale_y_continuous(labels=secondsFromNanoseconds) +
## #   scale_colour_brewer(palette = "Set1") +
## #   scale_size_area() +
## #   geom_vline(xintercept = versions_not_full$version, color="grey80", size=0.1) +
## #   geom_point(mapping =  aes(y=scaled_time, color=type), size=0.1) +
## #   our_theme() %+replace%
## #     theme(legend.position="bottom")

## # # ggsave(paste(filename, "config.png", sep=""), arrangeGrob(timestampByType.per_route, timestampByType.per_version) , width=7, height=11)
## # ggsave(paste(filename, "config.png", sep=""), arrangeGrob(configs_sent, timestampByType.per_route, timestampByType.per_version) , width=7, height=11)

## print("Latency between Config Sent and Route Working")
## configs = configs.all %>% filter(type == "RouteConfiguration")

## observations = routes %>% filter(status == "200") %>%
##   select(stamp, route) %>%
##   arrange(stamp, route) %>%
##   group_by(route) %>%  slice(1L) %>% ungroup()

## # all.withtimes = left_join(configs, observations, by="route") %>%
## #   filter(route < halfRoute) %>%
## #   mutate(time_diff = stamp.y - stamp.x)

## # latency_by_route = ggplot(all.withtimes) +
## #   labs(title="Latency from Config Sent to Route returns 200") +
## #   ylab("Time (seconds)") +
## #   scale_y_continuous(labels=secondsFromNanoseconds) +
## #   xlab("Route Number") +
## #   geom_point(mapping=aes(y=time_diff, x=route)) +
## #   our_theme() %+replace%
## #     theme(legend.position="bottom")

## # values = quantile(all.withtimes$time_diff, quantiles)
## # cptails = tibble(mylabels, values)
## # tail_latencies = ggplot(cptails, aes(x=mylabels, y=values)) +
## #   labs(title="Control Plane Latency by Percentile") +
## #   ylab("Latency (s)") +
## #   scale_y_continuous(labels=secondsFromNanoseconds) +
## #   xlab("Percentile") +
## #   scale_x_discrete(limits=mylabels) +
## #   geom_line(mapping=aes(group="default does not work")) +
## #   geom_point() +
## #   # add line for goal
## #   geom_hline(yintercept = fiveSecondsInNanoseconds, color="grey80") +
## #   geom_text(mapping = aes(y=fiveSecondsInNanoseconds, x="p68", label="GOAL 5sec at p95"), size=2, vjust=1.5, hjust=1, color="grey25") +
## #   scale_colour_brewer(palette = "Set1") +
## #   our_theme() %+replace%
## #     theme(legend.position="bottom")

## # # ggsave(paste(filename, "latency.png", sep=""), arrangeGrob(tail_latencies, latency_by_route), width=7, height=10)

#print("Reading in pod-by-node data")
## Read in timestamp-node-pod data
#nodes4pods = read_csv(paste(filename, "nodes4pods.csv", sep="")) %>%
#  extract(pod, "podtype", "([A-Za-z][A-Za-z0-9]+-?[A-Za-z]+)", remove=FALSE) %>%
#  extract(node, "nodename", "gke-.+-([A-Za-z0-9]+)")
#podcountsbynodetime = nodes4pods %>% select(-pod) %>% group_by(nodename, podtype, stamp) %>% summarize(n=n())
#podtypesbynode = nodes4pods %>% select(nodename, podtype) %>% distinct() %>% group_by(nodename) %>% summarize(podtypes = str_c(podtype, collapse=":"))

#print("Reading in node cpu/mem data")
## Read in timestamp-node-cpu-mem data
#nodeusage = read_csv(paste(filename, "nodemon.csv", sep=""), col_types=cols(percent=col_number())) %>%
#  extract(nodename, "nodename", "gke-.+-([A-Za-z0-9]+)") %>%
#  pivot_wider(names_from=type, values_from=percent, values_fn = list(percent = max)) %>%
#  left_join(podtypesbynode, by="nodename", name="podtypes") %>%
#  mutate(hasEnvoy = if_else(str_detect(podtypes, "gateway"), "with Envoy", "without Envoy"))

#print("Picking busiest nodes")
#busynodenames = nodeusage %>% group_by(nodename) %>% summarize(maxcpu = max(cpu, na.rm=TRUE)) %>% top_n(3,maxcpu)
#busynodes = busynodenames %>% left_join(nodeusage) %>% select(timestamp, nodename, cpu, memory, hasEnvoy)

#nodeusage = nodeusage %>% gather(type, percent, -nodename, -timestamp, -hasEnvoy, -podtypes)
#busynodes = busynodes %>% gather(type, percent, -nodename, -timestamp, -hasEnvoy)

#print("Usage by Node")
#experiment_time_x_axis(ggplot(nodeusage) +
#  labs(title = "Node Utilization", subtitle="100% = utilizing the whole machine") +
#  ylab("Utilization %") + ylim(0,100) + lines() +
#  facet_wrap(vars(hasEnvoy, type), ncol=1) +
#  geom_line(mapping = aes(x=timestamp,y=percent, group=nodename), color="gray15", alpha=0.15) +
#  geom_line(busynodes, mapping=aes(x=timestamp,y=percent, color=nodename), alpha=0.75) +
#  our_theme() %+replace%
#    theme(legend.position="bottom"))
#ggsave(paste(filename, "nodemon.png", sep=""), width=7, height=12)

#podcountsbusynodes = podcountsbynodetime %>% right_join(busynodenames) %>%
#  filter(podtype != "prometheus-to", podtype != "kube-proxy", podtype != "fluentd-gcp") %>%
#  mutate(podcategory = if_else(str_detect(podtype, "httpbin"), "workload", "system"))

#print("Pods on Busy Nodes")
#experiment_time_x_axis(ggplot(podcountsbusynodes) +
#  labs(title = "Pods by Node over Time") + lines() +
#  facet_wrap(vars(nodename), ncol=1) +
#  geom_count(mapping=aes(x=stamp,y=podtype,size=n,color=podtype), alpha=0.5) +
#  scale_size_area() +
#  our_theme() %+replace%
#    theme(legend.position="bottom"))
#numberofbusynodes = n_distinct(podcountsbusynodes$nodename)
#ggsave(paste(filename, "nodes4pods.png", sep=""), width=7, height=2.5 * numberofbusynodes)

#print("Client Usage")
#memstats = read_csv(paste(filename, "memstats.csv", sep=""))
#cpustats = read_csv(paste(filename, "cpustats.csv", sep=""))
#experiment_time_x_axis(ggplot(memstats) +
#  labs(title = "Client Resource Usage") +
#  ylab("Utilization %") + ylim(0,100) + lines() +
#  geom_line(mapping=aes(x=stamp,y=(used/total)*100, colour="memory")) +
#  geom_line(data=cpustats,mapping=aes(x=stamp,y=(100-idle), group=cpuid, colour=cpuid)) +
#  guides(colour = guide_legend(title = "CPU #")) +
#  lineLabels() +
#   our_theme() %+replace%
#     theme(legend.position="bottom"))
#ggsave(paste(filename, "resources.png", sep=""), width=7, height=3.5)

#print("Client Network")
#ifstats = read_csv(paste(filename, "ifstats.csv", sep=""))
#experiment_time_x_axis(ggplot(ifstats) +
#  labs(title = "Client Network Usage") +
#  ylab("Speed (kb/s)") + lines() +
#  geom_line(mapping=aes(x=stamp,y=down, colour="down")) +
#  geom_line(mapping=aes(x=stamp,y=up, colour="up")) +
#  guides(colour = guide_legend(title = "Key")) +
#  lineLabels() +
#   our_theme() %+replace%
#     theme(legend.position="bottom"))
#ggsave(paste(filename, "ifstats.png", sep=""), width=7, height=3.5)

