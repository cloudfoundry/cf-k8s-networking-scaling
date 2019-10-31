library(tidyverse)
library(gridExtra)


filename <- "./"

humanReadable <- function(x) {
  return(paste(round(x/(1024*1024), digits=2), "mb"))
}

times=read_csv(paste(filename, "importanttimes.csv", sep=""))

lines <- function() {
  return(
    geom_vline(data=times, mapping=aes(xintercept=stamp), color="grey")
  )
}
lineLabels <- function() {
  return(
    geom_text(data=times, mapping=aes(x=stamp, y=0, label=event), size=2, angle=90, vjust=-0.4, hjust=0, color="grey")
  )
}

controlplane = read_csv(paste(filename, "controlplane_latency.csv", sep=""))
gathered.controlplane = gather(controlplane, percentile, latency, -event, convert=TRUE)
ggplot(gathered.controlplane, aes(x=percentile, y=latency)) +
  geom_line(mapping = aes(group=event)) +
  geom_point() +
  facet_wrap(vars(event), ncol=1,
             labeller=as_labeller(c(`success` = "First Successful Route", `complete` = "Last Error on Route"))) +
  labs(title="Control Plane Latency (sec) by Percentile") +
  ylab("Time from VirtualService Creation to Event (seconds)") +
  xlab("Percentile") + scale_x_log10()

ggsave(paste(filename, "controlplane.svg", sep=""))

gateway = read_csv(paste(filename, "gatewaystats.csv", sep=""))

ggplot(gateway) +
  geom_line(rename(gateway, pod=podname), mapping = aes(x=timestamp, y = memory, group=pod, color=pod)) +
  scale_y_continuous(labels=humanReadable) +
  theme(legend.position="bottom") +
  lines() + lineLabels() +
  labs(title = "Gateway Memory Usage")

ggsave(paste(filename, "gateway.svg", sep=""))

sidecar = read_csv(paste(filename, "sidecarstats.csv", sep=""))

ggplot(sidecar) +
  geom_line(rename(sidecar, pod=podname),
            mapping = aes(x=timestamp, y=memory, group=pod),
            colour="grey85") +
  geom_line(mapping = aes(x=timestamp, y=memory, group=podname)) +
  scale_y_continuous(labels=humanReadable) +
  facet_wrap(vars(podname),strip.position = "bottom") +
  theme(strip.background = element_blank(), strip.placement = "outside") +
  lines() +
  theme(axis.text.x = element_text(angle = 90)) +
  labs(title = "Envoy Sidecar Memory Usage Over Time") +

ggsave(paste(filename, "sidecar.svg", sep=""))

# Timestamp vs Latency (ms)
dataload = read_csv(paste(filename, "dataload.csv", sep=""))
selected.dataload <- select(dataload, Name,
                            `Min. latency`, `Max. latency`,
                            `50% Latency`,`90% Latency`,`99% Latency`)
gathered.dataload <- gather(selected.dataload, key, milliseconds, -Name)
overtime <- ggplot(gathered.dataload) +
  geom_line(mapping = aes(x=Name,y=milliseconds,group=key,colour=key)) +
  theme(legend.position="bottom") +
  lines() + lineLabels() +
  labs(title = "Dataplane Latency (ms) over Time") +
  xlab("Unix Timestamp (seconds)") +
  ylab("Latency (ms)")

# Latency (ms) by Percentile
dataload = read_csv(paste(filename, "rawlatencies.txt", sep=""))
quantiles = c(0.68, 0.90, 0.99, 0.999, 1)
percentiles = c(68, 90, 99, 99.9, 100)
values = quantile(dataload$latency, quantiles)
dataload = tibble(percentiles, values)

bypercent <- ggplot(dataload, aes(x=percentiles, y=values)) +
  geom_line() + geom_point() +
  labs(title = "Dataplane Latency (ms) by Percentile") +
  ylab("Latency (ms)") +  xlab("Percentile") +
  scale_y_continuous(limits=layer_scales(overtime)$y$range$range) + # make scales match
  scale_x_log10()

ggsave(paste(filename, "dataload.svg", sep=""), arrangeGrob(overtime, bypercent))

dataload = read_csv(paste(filename, "howmanypilots.csv", sep=""))

ggplot(dataload) +
  geom_line(mapping=aes(x=stamp,y=count)) +
  lines() + lineLabels() +
  labs(title = "Number of Pilots over time")

ggsave(paste(filename, "howmanypilots.svg", sep=""))

print("All done.")
