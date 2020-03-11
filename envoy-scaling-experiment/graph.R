library(tidyverse)
library(gridExtra)
library(anytime)
options(digits.secs=6)                ## for fractional seconds below
Sys.setenv(TZ=anytime:::getTZ())      ## helper function to try to get TZ
filename <- "./"

## Conversion Functions
mb_from_bytes <- function(x) {
  return(round(x/(1024*1024), digits=1))
}

secondsFromNanoseconds <- function(x) {
  return(round(x/(1000*1000*1000), digits=1))
}

## Calculate timestamp when experiment began
times=read_csv(paste(filename, "importanttimes.csv", sep=""))
zeroPoint = min(times$stamp)
maxSec = max(times$stamp)

## Create time axis for experiment
breaksFromZero <- seq(from=zeroPoint, to=maxSec, by=5 * 60 * 1000 * 1000 * 1000)

secondsFromZero <- function(x) {
  return (secondsFromNanoseconds(x - zeroPoint))
}

experiment_time_x_axis <- function(p) {
  return(
         p + xlab("Time (seconds)") +
         scale_x_continuous(labels=secondsFromZero, breaks=breaksFromZero)
       )
}

lines <- function() {
  return(
    geom_vline(data=times, mapping=aes(xintercept=stamp), color="grey80")
  )
}

lineLabels <- function() {
  return(
    geom_text(data=times, mapping=aes(x=stamp, y=0, label=event), size=2, angle=90, vjust=-0.4, hjust=0, color="grey25")
  )
}

## Place to customize theme settings for all charts
our_theme <- function() {
  return(
         theme_linedraw()
  )
}

## Constants
quantiles = c(0.68, 0.90, 0.99, 0.999, 1)
mylabels = c("p68", "p90", "p99", "p999", "max")
fiveSecondsInNanoseconds = 5 * 1000 * 1000 * 1000


print("Graph Route Statuses")
routes = read_csv("./route-status.csv", col_types=cols(status=col_factor(), route=col_integer())) %>% drop_na()
only_errors = filter(routes, status != "200")
route_status = experiment_time_x_axis(ggplot(routes) +
  labs(title="Route Status over Time") +
  ylab("Route Number") +
  lines() +
  lineLabels() +
  facet_wrap(vars(status), ncol=1) +
  geom_point(mapping=aes(x=stamp, y=route, color=status), alpha = 0.5) +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom"))

ggsave(paste(filename, "routes.png", sep=""), route_status, width=7, height=7)

print("Graph Configs Sent")
xds = read_delim("./jaeger.csv", ";")
xds = xds %>%
  separate_rows(Routes, convert = TRUE) %>%  # one row per observation of a route being configured
  drop_na() # sometimes route is NA, so drop those
configs_sent =ggplot(xds) +
  labs(title="Config Sent over Time") +
  ylab("Route Number") +
  facet_wrap(vars(Type), ncol=1) +
  geom_point(mapping=aes(x=Date, y=Routes, color=Version), alpha=0.5, size=0.4) +
  scale_size_area() +
  scale_colour_distiller(palette="Spectral") +
  our_theme() %+replace%
    theme(legend.position="bottom")

ggsave(paste(filename, "config.png", sep=""), configs_sent, width=7, height=7)

print("Latency between Config Sent and Route Working")
scaleMicroToNano <- function(x, na.rm = FALSE) x * 10^3
configs = xds %>% filter(Type == "RouteConfiguration") %>%
  select(stamp=Timestamp, route=Routes) %>%
  arrange(stamp, route) %>%
  group_by(route) %>%  slice(1L) %>% ungroup()

observations = routes %>% filter(status == "200") %>%
  select(stamp, route) %>%
  arrange(stamp, route) %>%
  group_by(route) %>%  slice(1L) %>% ungroup()

halfRoute = max(configs$route) / 2
all.withtimes = left_join(configs, observations, by="route") %>%
  filter(route < halfRoute) %>%
  mutate(time_diff = stamp.y - stamp.x)

latency_by_route <- ggplot(all.withtimes) +
  labs(title="Latency from Config Sent to Route returns 200") +
  ylab("Time (seconds)") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  xlab("Route Number") +
  geom_point(mapping=aes(y=time_diff, x=route)) +
  our_theme() %+replace%
    theme(legend.position="bottom")

values = quantile(all.withtimes$time_diff, quantiles)
cptails = tibble(mylabels, values)
tail_latencies <- ggplot(cptails, aes(x=mylabels, y=values)) +
  labs(title="Control Plane Latency by Percentile") +
  ylab("Latency (s)") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  xlab("Percentile") +
  scale_x_discrete(limits=mylabels) +
  geom_line(mapping=aes(group="default does not work")) +
  geom_point() +
  # add line for goal
  geom_hline(yintercept = fiveSecondsInNanoseconds, color="grey80") +
  geom_text(mapping = aes(y=fiveSecondsInNanoseconds, x="p68", label="GOAL 5sec at p95"), size=2, vjust=1.5, hjust=1, color="grey25") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")

ggsave(paste(filename, "latency.png", sep=""), arrangeGrob(tail_latencies, latency_by_route), width=7, height=10)

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

