library(tidyverse)
library(gridExtra)

filename <- "./"

humanReadable <- function(x) {
  return(paste(round(x/(1024*1024), digits=2), "mb"))
}

times=read_csv(paste(filename, "importanttimes.csv", sep=""))

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
labels = c("p68", "p90", "p99", "p999", "max")

controlplane = read_csv(paste(filename, "user_data.csv", sep=""))
selected.controlplane <- select(controlplane, `user id`, `seconds to first success`, `seconds to first completion`)
first_values = quantile(selected.controlplane$`seconds to first success`, quantiles)
last_values = quantile(selected.controlplane$`seconds to first completion`, quantiles)
controlplane = tibble(quantiles = labels, first_values, last_values)
gathered.controlplane <- gather(controlplane, event, latency, -quantiles)
ggplot(gathered.controlplane, aes(x=quantiles, y=latency)) +
  geom_line(mapping = aes(group=event, color=event)) + geom_point() +
  scale_x_discrete(limits=labels) +
  labs(title="Control Plane Latency (sec) by Percentile") +
  ylab("Time from VirtualService Creation to Event (seconds)") +
  xlab("Percentile") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")
ggsave(paste(filename, "controlplane.svg", sep=""))

gateway = read_csv(paste(filename, "gatewaystats.csv", sep=""))
ggplot(gateway) +
  geom_line(rename(gateway, pod=podname), mapping = aes(x=timestamp, y = memory, group=pod, color=pod)) +
  scale_y_continuous(labels=humanReadable) +
  lines() + lineLabels() +
  labs(title = "Gateway Memory Usage") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")
ggsave(paste(filename, "gateway.svg", sep=""))

sidecar = read_csv(paste(filename, "sidecarstats.csv", sep=""))
ggplot(sidecar) +
  geom_line(rename(sidecar, pod=podname),
            mapping = aes(x=timestamp, y=memory, group=pod),
            colour="grey85") +
  geom_line(mapping = aes(x=timestamp, y=memory, group=podname)) +
  scale_y_continuous(labels=humanReadable) +
  facet_wrap(vars(podname),strip.position = "bottom") +
  lines() +
  labs(title = "Envoy Sidecar Memory Usage Over Time") +
  our_theme() %+replace%
    theme(strip.background = element_blank(), strip.placement = "outside", axis.text.x = element_text(angle = 90))
ggsave(paste(filename, "sidecar.svg", sep=""))

# Timestamp vs Latency (ms)
dataload = read_csv(paste(filename, "dataload.csv", sep=""))
selected.dataload <- select(dataload, Name,
                            `Min. latency`, `Max. latency`,
                            `50% Latency`,`90% Latency`,`99% Latency`)
gathered.dataload <- gather(selected.dataload, key, milliseconds, -Name)
overtime <- ggplot(gathered.dataload) +
  geom_line(mapping = aes(x=Name,y=milliseconds,group=key,colour=key)) +
  lines() + lineLabels() +
  labs(title = "Dataplane Latency (ms) over Time") +
  xlab("Unix Timestamp (seconds)") +
  ylab("Latency (ms)") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")

# Latency (ms) by Percentile
dataload = read_csv(paste(filename, "rawlatencies.txt", sep=""))
values = quantile(dataload$latency, quantiles)
dataload = tibble(labels, values)
bypercent <- ggplot(dataload, aes(x=labels, y=values)) +
  geom_line(mapping = aes(group="not the default")) + geom_point() +
  scale_y_continuous(limits=layer_scales(overtime)$y$range$range) + # make scales match
  scale_x_discrete(limits = labels) +
  labs(title = "Dataplane Latency (ms) by Percentile") +
  ylab("Latency (ms)") +  xlab("Percentile") +
  our_theme()

ggsave(paste(filename, "dataload.svg", sep=""), arrangeGrob(overtime, bypercent))

dataload = read_csv(paste(filename, "howmanypilots.csv", sep=""))
ggplot(dataload) +
  geom_line(mapping=aes(x=stamp,y=count)) +
  lines() + lineLabels() +
  labs(title = "Number of Pilots over time") +
  our_theme()
ggsave(paste(filename, "howmanypilots.svg", sep=""))

print("All done.")
