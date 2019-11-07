library(tidyverse)
library(gridExtra)

filename <- "./"

mb_from_bytes <- function(x) {
  return(round(x/(1024*1024), digits=1))
}

secondsFromNanoseconds <- function(x) {
  return(round(x/(1000*1000*1000), digits=1))
}

# TODO something is wrong
times=read_csv(paste(filename, "importanttimes.csv", sep=""))
zeroPoint = min(times$stamp)
maxSec = max(times$stamp)

breaksFromZero <- seq(from=zeroPoint, to=maxSec, by=120 * 1000 * 1000 * 1000)

secondsFromZero <- function(x) {
  return (secondsFromNanoseconds(x - zeroPoint))
}

experiment_time_x_axis <- function(p) {
  return(
         p + lines() + xlab("Time (seconds)") +
         scale_x_continuous(labels=secondsFromZero, breaks=breaksFromZero)
       )
}

lines <- function() {
  return(
    geom_vline(data=times, mapping=aes(xintercept=stamp), color="grey80", alpha=0.5)
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

# Control Plane Latency by Percentile
controlplane = read_csv(paste(filename, "user_data.csv", sep="")) %>%
  select(`user id`, `nanoseconds to first success`, `nanoseconds to last error`)
first_values = quantile(controlplane$`nanoseconds to first success`, quantiles)
last_values = quantile(controlplane$`nanoseconds to last error`, quantiles)
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

# # Timestamp vs Latency (ms) for smaller numbers of runs
# dataload = read_csv(paste(filename, "dataload.csv", sep=""))
# selected.dataload <- select(dataload, runID, Name,
#                             `Min. latency`, `Max. latency`,
#                             `68% Latency`,`90% Latency`,`99% Latency`)
# gathered.dataload <- gather(selected.dataload, key, milliseconds, -Name, -runID)
# overtime <- ggplot(gathered.dataload) +
#   labs(title = "Dataplane Latency (ms) over Time") +
#   geom_line(mapping = aes(x=Name,y=milliseconds,group=key,colour=key)) +
#   facet_wrap(vars(runID),ncol=1,strip.position = "bottom") +
#   lineLabels() +
#   ylab("Latency (ms)") +
#   scale_colour_brewer(palette = "Set1") +
#   our_theme() %+replace%
#     theme(legend.position="bottom")
# overtime <- experiment_time_x_axis(overtime)
# ggsave(paste(filename, "dataload_time.svg", sep=""))

# Timestamp vs Avg Latency (ms) for very large numbers of runs
dataload = read_csv(paste(filename, "dataload.csv", sep=""))
selected.dataload <- select(dataload, runID, Name,
                            `Min. latency`, `Max. latency`,
                            `68% Latency`,`90% Latency`,`99% Latency`)
gathered.dataload <- gather(selected.dataload, key, milliseconds, -Name, -runID)
overtime.max <- ggplot(gathered.dataload) +
  labs(title = "Max Dataplane Latency over Time (ms)", subtitle="Max, mean, and median of maximum latencies across all runs") +
  geom_line(mapping = aes(x=Name,y=milliseconds,group=interaction(runID, key)), color="grey85") +
  stat_summary_bin(data=dataload, aes(x=Name, y=`Max. latency`, colour="max of max"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(data=dataload, aes(x=Name, y=`Max. latency`, colour="mean of max"), fun.y = "mean", bins=100, geom="line") +
  stat_summary_bin(data=dataload, aes(x=Name, y=`Max. latency`, colour="median of max"), fun.y = "median", bins=100, geom="line") +
  ylab("Latency (ms)") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")
overtime.max <- experiment_time_x_axis(overtime.max)

overtime.99 <- ggplot(gathered.dataload) +
  labs(title = "99th Percentile Dataplane Latency over Time (ms)", subtitle="Max, mean, and median of 99th percentile latencies across all runs") +
  geom_line(mapping = aes(x=Name,y=milliseconds,group=interaction(runID, key)), color="grey85") +
  stat_summary_bin(data=dataload, aes(x=Name, y=`99% Latency`, colour="max of 99"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(data=dataload, aes(x=Name, y=`99% Latency`, colour="mean of 99"), fun.y = "mean", bins=100, geom="line") +
  stat_summary_bin(data=dataload, aes(x=Name, y=`99% Latency`, colour="median of 99"), fun.y = "median", bins=100, geom="line") +
  ylab("Latency (ms)") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")
overtime.99 <- experiment_time_x_axis(overtime.99)

ggsave(paste(filename, "dataload_time.svg", sep=""), arrangeGrob(overtime.max, overtime.99))


# Latency (ms) by Percentile
dataload = read_csv(paste(filename, "rawlatencies.txt", sep=""))
values = quantile(dataload$latency, quantiles)
dataload = tibble(mylabels, values)
ggplot(dataload, aes(x=mylabels, y=values)) +
  labs(title = "Dataplane Latency (ms) by Percentile") +
  geom_line(mapping = aes(group="not the default")) +
  geom_point(mapping = aes(size=1, stroke=0)) + scale_size_identity() +
  scale_x_discrete(limits = mylabels) +
  ylab("Latency (ms)") +  xlab("Percentile") +
  our_theme()

ggsave(paste(filename, "dataload_percentile.svg", sep=""), width=7, height=3.5)

# Sidecar memory usage for small numbers of runs
# sidecar = read_csv(paste(filename, "sidecarstats.csv", sep="")) %>%
#   group_by(runID) %>%
#   mutate(dummy_var = as.character(x = factor(x = podname,
#                                              labels = seq_len(length.out = n_distinct(x = podname))))) %>%
#   ungroup()
# experiment_time_x_axis(ggplot(sidecar) +
#   labs(title = "Envoy Sidecar Memory Usage Over Time") +
#   ylab("Memory (mb)") +
#   geom_line(mapping = aes(x=timestamp, y=memory, group=podname, color=dummy_var, alpha=0.95)) +
#   scale_y_continuous(labels=mb_from_bytes) +
#   facet_wrap(vars(runID),strip.position="bottom",ncol=1) +
#   scale_colour_brewer(palette = "Set1") +
#   our_theme() %+replace%
#     theme(strip.placement = "outside", legend.position="none"))
# ggsave(paste(filename, "sidecar.svg", sep=""), width=7, height=5)

# Sidecar memory usage for large numbers of runs
sidecar = read_csv(paste(filename, "sidecarstats.csv", sep="")) %>%
  group_by(runID) %>%
  mutate(dummy_var = as.character(x = factor(x = podname,
                                             labels = seq_len(length.out = n_distinct(x = podname))))) %>%
  ungroup()
experiment_time_x_axis(ggplot(sidecar) +
  labs(title = "Envoy Sidecar Memory Usage Over Time") +
  ylab("Memory (mb)") +
  geom_line(mapping = aes(x=timestamp, y=memory, group=podname), color="grey85") +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "mean"), fun.y = "mean", bins=100, geom="line") +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "max"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "median"), fun.y = "median", bins=100, geom="line") +
  guides(colour = guide_legend(title = "Key")) +
  scale_y_continuous(labels=mb_from_bytes) +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(strip.placement = "outside", legend.position="bottom"))
ggsave(paste(filename, "sidecar.svg", sep=""), height=3.5)


# Gateway memory usage for small number of runs
# gateway = read_csv(paste(filename, "gatewaystats.csv", sep="")) %>%
#   group_by(runID) %>%
#   mutate(dummy_var = as.character(x = factor(x = podname,
#                                              labels = seq_len(length.out = n_distinct(x = podname))))) %>%
#   ungroup()
# experiment_time_x_axis(ggplot(gateway) +
#   labs(title = "Gateway Memory Usage over Time") +
#   ylab("Memory (mb)") +
#   geom_line(rename(gateway, pod=podname), mapping = aes(x=timestamp, y = memory, group=pod, color=dummy_var)) +
#   scale_y_continuous(labels=mb_from_bytes) +
#   facet_wrap(vars(runID),strip.position = "bottom", ncol=1) +
#   lineLabels() +
#   scale_colour_brewer(palette = "Set1") +
#   our_theme() %+replace%
#     theme(legend.position="none"))
# ggsave(paste(filename, "gateway.svg", sep=""), width=7, height=7)

# Gateway memory usage for large number of runs
gateway = read_csv(paste(filename, "gatewaystats.csv", sep="")) %>%
  group_by(runID) %>%
  mutate(dummy_var = as.character(x = factor(x = podname,
                                             labels = seq_len(length.out = n_distinct(x = podname))))) %>%
  ungroup()
experiment_time_x_axis(ggplot(gateway) +
  labs(title = "Gateway Memory Usage over Time") +
  ylab("Memory (mb)") +
  geom_line(mapping = aes(x=timestamp, y=memory, group=podname), color="grey85") +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "mean"), fun.y = "mean", bins=100, geom="line") +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "max"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "median"), fun.y = "median", bins=100, geom="line") +
  guides(colour = guide_legend(title = "Key")) +
  scale_y_continuous(labels=mb_from_bytes) +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(strip.placement = "outside", legend.position="bottom"))
ggsave(paste(filename, "gateway.svg", sep=""), height=3.5)

# Only useful for smaller numbers of runs
# dataload = read_csv(paste(filename, "howmanypilots.csv", sep=""))
# experiment_time_x_axis(ggplot(dataload) +
#   labs(title = "Number of Pilots over time") +
#   geom_line(mapping=aes(x=stamp,y=count, group=runID, color=factor(runID), alpha=0.1, size=2), show.legend=FALSE) +
#   scale_colour_brewer(palette = "Set1") +
#   our_theme() %+replace%
#     theme(legend.position="bottom"))
# ggsave(paste(filename, "howmanypilots.svg", sep=""), width=7, height=3.5)

pilotdata = read_csv(paste(filename, "howmanypilots.csv", sep=""))
experiment_time_x_axis(ggplot(pilotdata, aes(x=stamp,y=count)) +
  labs(title = "Average Number of Pilots over time") +
  geom_line(mapping=aes(x=stamp,y=count, group=runID), color="grey70", alpha=0.5, show.legend=FALSE) +
  our_theme() %+replace%
    theme(legend.position="bottom") +
  stat_summary_bin(fun.y = "mean", colour = "red", bins=100, geom="line") 
)
ggsave(paste(filename, "howmanypilots.svg", sep=""), width=7, height=3.5)

dataload = read_csv(paste(filename, "nodemon.csv", sep=""), col_types=cols(cpupercent=col_number(), memorypercent=col_number()))
experiment_time_x_axis(ggplot(dataload, aes(group=runID)) +
  labs(title = "Node utilization percent") +
  stat_summary(aes(x=timestamp,y=cpupercent, colour="CPU% Max"),fun.y="max", geom="line", linetype=1) +
  stat_summary(aes(x=timestamp,y=cpupercent, colour="CPU% Mean"),fun.y="mean", geom="line", linetype=1) +
  stat_summary(aes(x=timestamp,y=memorypercent, colour="Memory% Max"),fun.y="max", geom="line", linetype=2) +
  stat_summary(aes(x=timestamp,y=memorypercent, colour="Memory% Mean"),fun.y="mean", geom="line", linetype=2, key_glyph="timeseries") +
  scale_colour_brewer(palette = "Set1") +
  guides(colour = guide_legend(title = "Key")) +
  our_theme() %+replace%
    theme(legend.position="bottom"))
ggsave(paste(filename, "nodemon.svg", sep=""), width=7, height=3.5)

memstats = read_csv(paste(filename, "memstats.csv", sep=""))
cpustats = read_csv(paste(filename, "cpustats.csv", sep=""))

cpustats.selected <- cpustats[which(cpustats$cpuid=='all'),]

experiment_time_x_axis(ggplot(memstats) +
  labs(title = "Client Resource Usage") +
  ylab("Utilization %") + ylim(0,100) +
  geom_line(mapping=aes(x=stamp,y=(used/total)*100, colour="memory")) +
  geom_line(data=cpustats.selected,mapping=aes(x=stamp,y=(100-idle), group=interaction(runID, cpuid), colour=interaction(runID, cpuid))) +
  guides(colour = guide_legend(title = "CPU #")) +
  our_theme() %+replace%
     theme(legend.position="none"))
ggsave(paste(filename, "resources.svg", sep=""), width=7, height=3.5)

ifstats = read_csv(paste(filename, "ifstats.csv", sep=""))
experiment_time_x_axis(ggplot(ifstats) +
  labs(title = "Client Network Usage") +
  ylab("Speed (kb/s)") +
  geom_line(mapping=aes(x=stamp,y=down, colour=interaction(runID, "down"), group=runID)) +
  geom_line(mapping=aes(x=stamp,y=up, colour=interaction(runID, "up"), group=runID)) +
  guides(colour = guide_legend(title = "Key")) +
  our_theme() %+replace%
     theme(legend.position="none"))
ggsave(paste(filename, "ifstats.svg", sep=""), width=7, height=3.5)

print("All done!")
