library(tidyverse)


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
  labs(title = "Envoy Sidecar Memory Usage Over Time") +

ggsave(paste(filename, "sidecar.svg", sep=""))

dataload = read_csv(paste(filename, "dataload.csv", sep=""))

selected.dataload <- select(dataload, Name,
                            `Avg. Latency`, `Min. latency`, `Max. latency`,
                            `50% Latency`,`90% Latency`,`98% Latency`,`99% Latency`)
gathered.dataload <- gather(selected.dataload, key, milliseconds, -Name)

ggplot(gathered.dataload) +
  geom_line(mapping = aes(x=Name,y=milliseconds,group=key,colour=key)) +
  theme(legend.position="bottom") +
  lines() + lineLabels() +
  labs(title = "Dataplane Latency (ms) over Time")

ggsave(paste(filename, "dataload.svg", sep=""))

dataload = read_csv(paste(filename, "howmanypilots.csv", sep=""))

ggplot(dataload) +
  geom_line(mapping=aes(x=stamp,y=count)) +
  lines() + lineLabels() +
  labs(title = "Number of Pilots over time")

ggsave(paste(filename, "howmanypilots.svg", sep=""))

print("All done.")
