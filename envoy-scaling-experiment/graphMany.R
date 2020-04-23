library(tidyverse)
library(gridExtra)

filename <- "./"

## Conversion Functions
mb_from_bytes <- function(x) {
  return(round(x/(1024*1024), digits=1))
}

bytes_from_mb <- function(x) {
  return(x * 1024 * 1024)
}

# Read in important times (runID, stamp, event)
times=read_csv(paste(filename, "importanttimes.csv", sep=""))

# Set up x-axis in experimental time (all data has normalized timestamps)
maxSec = max(times$stamp)
breaksFromZero <- seq(from=0, to=maxSec, by=20 * 60 * 1000 * 1000 * 1000)

secondsFromNanoseconds <- function(x) {
  return(round(x/(1000*1000*1000), digits=1))
}
minutesFromNanoseconds <- function(x) {
  return(round(x/(60*1000*1000*1000), digits=1))
}
nanosecondsFromSeconds <- function(x) {
 x*1000*1000*1000
}

experiment_time_x_axis <- function(p) {
  return(
         p + xlab("Time (minutes)") +
         scale_x_continuous(labels=minutesFromNanoseconds, breaks=breaksFromZero)
       )
}

# Add vertical lines for all important time events in all experiment runs
lines <- function() {
  return(
    geom_vline(data=times, mapping=aes(xintercept=stamp), color="grey80", alpha=0.5)
  )
}

# Add labels to the vertical lines (add text before the first line)
first_times = group_by(times, event) %>% summarize(stamp = min(stamp))
lineLabels <- function() {
  return(
    geom_text(data=first_times, mapping=aes(x=stamp, y=0, label=event), size=2, angle=90, vjust=-0.4, hjust=0, color="grey25")
  )
}

our_theme <- function() {
  return(
         theme_linedraw() %+replace%
           theme(legend.title=element_blank())
  )
}

quantiles = c(0.68, 0.90, 0.99, 0.999, 1)
mylabels = c("p68", "p90", "p99", "p999", "max")
fiveSecondsInNanoseconds = 5 * 1000 * 1000 * 1000


print("Collect Route Status Data")
# timestamp, runID, status, route
routes = read_csv("./route-status.csv", col_types=cols(runID=col_factor(), status=col_factor(), route=col_integer())) %>% drop_na()
halfRoute = max(routes$route) # the route-status.csv will only include routes created during CP load
print(paste("halfRoute = ", halfRoute))
time_when_route_first_works = routes %>% filter(status == "200") %>%
  select(runID, stamp, route) %>%
  arrange(stamp) %>%
  group_by(runID, route) %>%  slice(1L) %>% ungroup()

obs_deltas = routes %>%
  filter(route < halfRoute) %>%
  arrange(stamp) %>%
  group_by(runID, route) %>%
  mutate(delta = stamp - lag(stamp, default=stamp[1])) %>%
  filter(delta != 0) %>%
  summarize(m = mean(delta), n = n()) %>%
  group_by(runID) %>%
  summarize(m = mean(m)) %>%
  mutate(m = m / 1e6)


print(obs_deltas)
# envoy_polls = read_csv('./envoy_requests.csv') %>%
#   group_by(runID) %>%
#   mutate(delta = stamp - lag(stamp, default=stamp[1])) %>%
#   summarize(m = median(delta))


# print(envoy_polls)
# quit()


print("Collect Config Send Data")
xds = read_csv("./jaeger.csv", col_types=cols(runID=col_factor()))
xds = xds %>%
  separate_rows(Routes, convert = TRUE) %>%  # one row per observation of a route being configured
  drop_na() # sometimes route is NA, so drop those

# RouteConfiguration is the first type sent. ClusterLoadAllocation is last.
time_when_route_first_sent = xds %>% filter(Type == "RouteConfiguration") %>%
  select(runID, stamp=Timestamp, route=Routes) %>%
  arrange(stamp) %>%
  group_by(runID, route) %>%  slice(1L) %>% ungroup() %>%
  filter(route < halfRoute)

print("Collect /clusters Data")
time_when_cluster_appears = read_csv("endpoints_arrival.csv", col_types=cols(runID=col_factor())) %>%
  filter(str_detect(route, "service_.*")) %>%
  select(runID, stamp, route) %>%
  extract("route", "route", regex = "service_([[:alnum:]]+)", convert=TRUE) %>%
  filter(route < halfRoute) %>% # only include routes from CP load

print("Calculate Control Plane Latency")
from_config_sent_to_works = left_join(time_when_route_first_sent, time_when_route_first_works, by=c("runID","route")) %>%
  mutate(time_diff = stamp.y - stamp.x) # when it works minus when it was sent

from_clusters_to_works = left_join(time_when_cluster_appears, time_when_route_first_works, by=c("runID", "route")) %>%
  mutate(time_diff = stamp.y - stamp.x) %>% # route works - cluster exists
  arrange(route)

from_config_sent_to_clusters = left_join(time_when_route_first_sent, time_when_cluster_appears, by=c("runID", "route")) %>%
  mutate(time_diff = stamp.y - stamp.x) %>% # cluster exists - route sent
  arrange(route)

print(filter(from_clusters_to_works, is.na(time_diff)))
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
    .id="type"
  ) %>%
  filter(route < halfRoute)

# TODO make negative time_diff zero
print(latencies_by_route)

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

latencies_bars = ggplot(latencies_by_route, aes(x=route, y=time_diff)) +
  labs(title="Control Plane Latency by Route") +
  ylab("Latency (s)") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  xlab("Route") +
  # facet_wrap(vars(runID), ncol=1) +
  # geom_bar(mapping=aes(fill=type), stat="identity") +
  facet_wrap(vars(type), ncol=1) +
  geom_point(color="black", alpha=0.25) +
  stat_summary_bin(aes(colour="max"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(aes(colour="median"), fun.y = "median", bins=100, geom="line") +
  geom_hline(yintercept = 0, color="grey45") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")

ggsave(paste(filename, "latency.png", sep=""),
       arrangeGrob(tail_latencies, latencies_bars), width=3 * 7, height=3 * 10)


print("Graph Node Usage")
nodemon = read_csv(paste(filename, "nodemon.csv", sep=""), col_types=cols(percent=col_number()))
experiment_time_x_axis(ggplot(nodemon) +
  labs(title = "Node Utilization") +
  lines() + lineLabels() +
  geom_hline(yintercept = 100, color="grey45") +
  facet_wrap(vars(type), ncol=1) +
  geom_line(mapping=aes(x=timestamp, y=percent, group=interaction(runID, nodename)), color="gray15", alpha=0.15, show.legend=FALSE) +
  stat_summary_bin(aes(x=timestamp, y=percent, colour="max"),fun.y="max", bins=100, geom="line") +
  stat_summary_bin(aes(x=timestamp, y=percent, colour="median"),fun.y="median", bins=100, geom="line") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="none", axis.title.x=element_blank(), axis.text.x=element_blank()))
ggsave(paste(filename, "nodemon.png", sep=""), width=7, height=3.5)

print("Graph Client VM Usage")
memstats = read_csv(paste(filename, "memstats.csv", sep="")) %>% mutate(memory = (used/total) * 100) %>% select(runID, timestamp=stamp, memory)
cpustats = read_csv(paste(filename, "cpustats.csv", sep="")) %>% filter(cpuid == "all") %>% mutate(cpu = (100 - idle)) %>% select(runID, timestamp=stamp, cpuid, cpu)
clientstats = full_join(memstats, cpustats) %>% gather("metric", "percent", -runID, -cpuid, -timestamp)
cpu = experiment_time_x_axis(ggplot(clientstats, aes(x=timestamp, y=percent)) +
  labs(title = "Client Utilization") +
  ylab("Utilization %") +
  lines() + lineLabels() +
  geom_hline(yintercept = 100, color="grey45") +
  facet_wrap(vars(metric), ncol=1, scales="free_y") +
  geom_line(mapping=aes(group=interaction(runID, cpuid)), color="gray15", alpha=0.15) +
  stat_summary_bin(aes(colour="max"),fun.y="max", geom="line", bins=100) +
  stat_summary_bin(aes(colour="median"),fun.y="median", bins=100, geom="line") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="none", axis.title.x=element_blank(), axis.text.x=element_blank()))

ggsave(paste(filename, "resources.png", sep=""), width=7, height=3.5)

ifstats = read_csv(paste(filename, "ifstats.csv", sep="")) %>% gather("direction", "rate", -runID, -stamp) %>% mutate(rate = rate / 1024)
experiment_time_x_axis(ggplot(ifstats) +
  labs(title = "Client Network Usage") +
  ylab("Speed (mb/s)") +
  lines() + lineLabels() +
  facet_wrap(vars(direction), ncol=1, scales="free_y") +
  geom_line(mapping=aes(x=stamp, y=rate, group=runID), color="grey15", alpha=0.15) +
  stat_summary_bin(aes(x=stamp, y=rate, colour="max"),fun.y="max", geom="line", bins=100) +
  stat_summary_bin(aes(x=stamp, y=rate, colour="median"),fun.y="median", bins=100, geom="line") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="none"))
ggsave(paste(filename, "ifstats.png", sep=""), width=7, height=3.5)

print("All done!")
