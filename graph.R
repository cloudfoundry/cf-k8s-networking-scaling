library(tidyverse)
library(gridExtra)

filename <- "./"

mb_from_bytes <- function(x) {
  return(round(x/(1024*1024), digits=1))
}

secondsFromNanoseconds <- function(x) {
  return(round(x/(1000*1000*1000), digits=1))
}

times=read_csv(paste(filename, "importanttimes.csv", sep=""))
zeroPoint = min(times$stamp)
maxSec = max(times$stamp)

breaksFromZero <- seq(from=zeroPoint, to=maxSec, by=120 * 1000 * 1000 * 1000)

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

our_theme <- function() {
  return(
         theme_linedraw()
  )
}

quantiles = c(0.68, 0.90, 0.99, 0.999, 1)
mylabels = c("p68", "p90", "p99", "p999", "max")
fiveSecondsInNanoseconds = 5 * 1000 * 1000 * 1000

print("Control Plane Latency by Percentile")
controlplane = read_csv(paste(filename, "user_data.csv", sep=""))
selected.controlplane <- select(controlplane, `user id`, `nanoseconds to first success`, `nanoseconds to last error`)
first_values = quantile(selected.controlplane$`nanoseconds to first success`, quantiles)
last_values = quantile(selected.controlplane$`nanoseconds to last error`, quantiles)
controlplane = tibble(quantiles = mylabels, `time to first success` = first_values, `time to last error` = last_values)
gathered.controlplane <- gather(controlplane, event, latency, -quantiles)
ggplot(gathered.controlplane, aes(x=quantiles, y=latency)) +
  labs(title="Control Plane Latency by Percentile") +
  ylab("Latency (s)") +
  xlab("Percentile") +
  geom_line(mapping = aes(group=event, color=event)) +
  geom_point(mapping = aes(size=1, stroke=0)) + scale_size_identity() +
  # add line for goal
  geom_hline(yintercept = fiveSecondsInNanoseconds, color="grey80") +
  geom_text(mapping = aes(y=fiveSecondsInNanoseconds, x="p68", label="GOAL 5sec at p95"), size=2, vjust=1.5, hjust=1, color="grey25") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  scale_x_discrete(limits=mylabels) +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")
ggsave(paste(filename, "controlplane.svg", sep=""), width=7, height = 3.5)

print("Timestamp vs Latency (ms)")
dataload = read_csv(paste(filename, "dataload.csv", sep=""), col_types=cols(Name=col_number()))
selected.dataload <- select(dataload, Name,
                            `Min. latency`, `Max. latency`,
                            `68% Latency`,`90% Latency`,`99% Latency`)
gathered.dataload <- gather(selected.dataload, key, milliseconds, -Name)
overtime <- ggplot(gathered.dataload) +
  labs(title = "Dataplane Latency (ms) over Time") +
  geom_line(mapping = aes(x=Name,y=milliseconds,group=key,colour=key)) +
  lineLabels() + lines() +
  ylab("Latency (ms)") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")
overtime <- experiment_time_x_axis(overtime)

print("Latency (ms) by Percentile")
dataload = read_csv(paste(filename, "rawlatencies.txt", sep=""))
values = quantile(dataload$latency, quantiles)
dataload = tibble(mylabels, values)
bypercent <- ggplot(dataload, aes(x=mylabels, y=values)) +
  labs(title = "Dataplane Latency (ms) by Percentile") +
  geom_line(mapping = aes(group="not the default")) +
  geom_point(mapping = aes(size=1, stroke=0)) + scale_size_identity() +
  scale_y_continuous(limits=layer_scales(overtime)$y$range$range) + # make scales match
  scale_x_discrete(limits = mylabels) +
  ylab("Latency (ms)") +  xlab("Percentile") +
  our_theme()

ggsave(paste(filename, "dataload.svg", sep=""), arrangeGrob(overtime, bypercent))

print("Sidecar Memory")
sidecar = read_csv(paste(filename, "sidecarstats.csv", sep=""))
experiment_time_x_axis(ggplot(sidecar) +
  labs(title = "Envoy Sidecar Memory Usage Over Time") +
  ylab("Memory (mb)") + lines() +
  geom_line(rename(sidecar, pod=podname),
            mapping = aes(x=timestamp, y=memory, group=pod),
            colour="grey85") +
  geom_line(mapping = aes(x=timestamp, y=memory, group=podname)) +
  scale_y_continuous(labels=mb_from_bytes) +
  facet_wrap(vars(podname),strip.position = "bottom") +
  our_theme() %+replace%
    theme(strip.background = element_blank(), strip.placement = "outside"))
ggsave(paste(filename, "sidecar.svg", sep=""), width=7, height=5)

print("Gateway Memory")
gateway = read_csv(paste(filename, "gatewaystats.csv", sep=""))
experiment_time_x_axis(ggplot(gateway) +
  labs(title = "Gateway Memory Usage over Time") +
  ylab("Memory (mb)") + lines() +
  geom_line(rename(gateway, pod=podname), mapping = aes(x=timestamp, y = memory, group=pod, color=pod), alpha=0.5) +
  scale_y_continuous(labels=mb_from_bytes) +
  lineLabels() +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="none"))
ggsave(paste(filename, "gateway.svg", sep=""), width=7, height=3.5)

print("Pilot Count")
dataload = read_csv(paste(filename, "howmanypilots.csv", sep=""))
experiment_time_x_axis(ggplot(dataload) +
  labs(title = "Number of Pilots over time") +
  geom_line(mapping=aes(x=stamp,y=count)) +
  lineLabels() + lines() +
  our_theme())
ggsave(paste(filename, "howmanypilots.svg", sep=""), width=7, height=3.5)

print("Reading in pod-by-node data")
# Read in timestamp-node-pod data
nodes4pods = read_csv(paste(filename, "nodes4pods.csv", sep="")) %>%
  extract(pod, "podtype", "([A-Za-z][A-Za-z0-9]+-?[A-Za-z]+)", remove=FALSE) %>%
  extract(node, "nodename", "gke-.+-([A-Za-z0-9]+)")
podcountsbynodetime = nodes4pods %>% select(-pod) %>% group_by(nodename, podtype, stamp) %>% summarize(n=n())
podtypesbynode = nodes4pods %>% select(nodename, podtype) %>% distinct() %>% group_by(nodename) %>% summarize(podtypes = str_c(podtype, collapse=":"))

# Read in timestamp-node-cpu-mem data
nodeusage = read_csv(paste(filename, "nodemon.csv", sep=""), col_types=cols(cpupercent=col_number(), memorypercent=col_number())) %>%
  extract(nodename, "nodename", "gke-.+-([A-Za-z0-9]+)") %>%
  select(timestamp, nodename, cpupercent, memorypercent) %>%
  left_join(podtypesbynode, by="nodename", name="podtypes") %>%
  mutate(hasIstio = if_else(str_detect(podtypes, "istio"), "with istio", "without istio"))

busynodenames = nodeusage %>% group_by(nodename) %>% summarize(maxcpu = max(cpupercent)) %>% filter(maxcpu > 50)
busynodes = busynodenames %>% left_join(nodeusage) %>% select(timestamp, nodename, cpupercent, memorypercent, hasIstio)

nodeusage = nodeusage %>% gather(type, percent, -nodename, -timestamp, -hasIstio, -podtypes)
busynodes = busynodes %>% gather(type, percent, -nodename, -timestamp, -hasIstio)
print("Usage by Node")
experiment_time_x_axis(ggplot(nodeusage, aes(group=nodename)) +
  labs(title = "Node Utilization", subtitle="100% = utilizing the whole machine") +
  ylab("Utilization %") + ylim(0,100) + lines() +
  facet_wrap(vars(hasIstio, type), ncol=1) +
  geom_line(mapping = aes(x=timestamp,y=percent), color="gray15", alpha=0.15) +
  geom_line(busynodes, mapping=aes(x=timestamp,y=percent, color=nodename)) +
  our_theme() %+replace%
    theme(legend.position="bottom"))
ggsave(paste(filename, "nodemon.svg", sep=""), width=7, height=12)

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
ggsave(paste(filename, "nodes4pods.svg", sep=""), width=7, height=3.5 * numberofbusynodes)

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
ggsave(paste(filename, "resources.svg", sep=""), width=7, height=3.5)

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
ggsave(paste(filename, "ifstats.svg", sep=""), width=7, height=3.5)

print("All done.")
