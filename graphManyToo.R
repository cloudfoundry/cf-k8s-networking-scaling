library(tidyverse)
library(gridExtra)

filename <- "./"

mb_from_bytes <- function(x) {
  return(round(x/(1024*1024), digits=1))
}

# Read in important times (runID, stamp, event)
times=read_csv(paste(filename, "importanttimes.csv", sep=""))

# Set up x-axis in experimental time (all data has normalized timestamps)
maxSec = max(times$stamp)
breaksFromZero <- seq(from=0, to=maxSec, by=120 * 1000 * 1000 * 1000)
secondsFromNanoseconds <- function(x) {
  return(round(x/(1000*1000*1000), digits=1))
}
experiment_time_x_axis <- function(p) {
  return(
         p + xlab("Time (seconds)") +
         scale_x_continuous(labels=secondsFromNanoseconds, breaks=breaksFromZero)
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

# Control Plane Latency by Percentile
controlplane = read_csv(paste(filename, "user_data.csv", sep="")) %>%
  select(`user id`, `nanoseconds to first success`, `nanoseconds to last error`)
first_values = quantile(controlplane$`nanoseconds to first success`, quantiles)
last_values = quantile(controlplane$`nanoseconds to last error`, quantiles)
controlplane = tibble(quantiles = mylabels, `time to first success` = first_values, `time to last error` = last_values)
gathered.controlplane <- gather(controlplane, event, latency, -quantiles)
colors <- c("time to last error"="black", "time to first success"="gray85")
ggplot(gathered.controlplane, aes(x=quantiles, y=latency)) +
  labs(title="Control Plane Latency by Percentile") +
  ylab("Latency (s)") +
  xlab("Percentile") +
  geom_line(mapping = aes(group=event, color=event)) +
  geom_point(mapping = aes(size=1, stroke=0)) + scale_size_identity() +
  # add line for goal
  geom_hline(yintercept = fiveSecondsInNanoseconds, color="#e41a1c", linetype=2) +
  geom_text(mapping = aes(y=fiveSecondsInNanoseconds, x="p68", label="GOAL 5sec at p95"), size=2, vjust=1.5, hjust=1, color="grey25") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  scale_x_discrete(limits=mylabels) +
  scale_colour_manual(values = colors)  +
  our_theme() %+replace%
    theme(legend.position="bottom")
ggsave(paste(filename, "controlplane.svg", sep=""), width=7, height = 3.5)

# Timestamp vs Avg Latency (ms) for very large numbers of runs
dataload = read_csv(paste(filename, "dataload.csv", sep=""))
max.dataload <- select(dataload, runID, Name, `Max. latency`,`99% Latency`)
gathered.dataload <- gather(max.dataload, key, milliseconds, -Name, -runID)
overtime.max <- ggplot(gathered.dataload) +
  labs(title = "Dataplane Latency over Time (ms)", subtitle="Notice that the y-axis scales differ.") +
  ylab("Latency (ms)") +
  lines() + lineLabels() +
  # add line for goal
  geom_hline(yintercept = 20, color="gray75", linetype=2) +
  geom_text(mapping = aes(y=20, x=fiveSecondsInNanoseconds * 14, label="GOAL 20ms added latency"), size=2, vjust=1.5, hjust=1, color="grey25") +
  facet_wrap(vars(key), ncol=1, scales="free_y") +
  geom_line(mapping = aes(x=Name,y=milliseconds,group=runID), color="gray15", alpha=0.15) +
  stat_summary_bin(aes(x=Name, y=milliseconds, colour="max"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(aes(x=Name, y=milliseconds, colour="median"), fun.y = "median", bins=100, geom="line") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")
overtime.max <- experiment_time_x_axis(overtime.max)

ggsave(paste(filename, "dataload_time.svg", sep=""))

quantiles = c(0.68, 0.90, 0.99, 0.999, 0.9999, 0.99999, 1)
mylabels = c("p68", "p90", "p99", "p999", "p9999", "p99999", "max")

# Latency (ms) by Percentile
dataload = read_csv(paste(filename, "rawlatencies.txt", sep=""))
values = quantile(dataload$latency, quantiles)
dataload = tibble(mylabels, values)
ggplot(dataload, aes(x=mylabels, y=values)) +
  labs(title = "Dataplane Latency (ms) by Percentile") +
  # add line for goal
  geom_hline(yintercept = 20, color="gray75", linetype=2) +
  geom_text(mapping = aes(y=20, x="p68", label="GOAL 20ms added latency"), size=2, vjust=-0.5, hjust=0.35, color="grey25") +
  geom_line(mapping = aes(group="not the default")) +
  geom_point(mapping = aes(size=1, stroke=0)) + scale_size_identity() +
  scale_x_discrete(limits = mylabels) +
  ylab("Latency (ms)") +  xlab("Percentile") +
  our_theme()

ggsave(paste(filename, "dataload_percentile.svg", sep=""), width=7, height=3.5)

# Sidecar memory usage for large numbers of runs
sidecar = read_csv(paste(filename, "sidecarstats.csv", sep=""))
experiment_time_x_axis(ggplot(sidecar) +
  labs(title = "Envoy Sidecar Memory Usage Over Time") +
  ylab("Memory (mb)") +
  lines() + lineLabels() +
  geom_line(mapping = aes(x=timestamp, y=memory, group=podname), color="gray15", alpha=0.15) +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "max"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "median"), fun.y = "median", bins=100, geom="line") +
  scale_y_continuous(labels=mb_from_bytes) +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(strip.placement = "outside", legend.position="bottom"))
ggsave(paste(filename, "sidecar.svg", sep=""), height=3.5)


# Gateway memory usage for large number of runs
gateway = read_csv(paste(filename, "gatewaystats.csv", sep=""))
experiment_time_x_axis(ggplot(gateway) +
  labs(title = "Gateway Memory Usage over Time") +
  ylab("Memory (mb)") +
  lines() + lineLabels() +
  geom_line(mapping = aes(x=timestamp, y=memory, group=podname), color="gray15", alpha=0.15) +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "max"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(aes(x=timestamp,y=memory, colour = "median"), fun.y = "median", bins=100, geom="line") +
  scale_y_continuous(labels=mb_from_bytes) +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(strip.placement = "outside", legend.position="bottom"))
ggsave(paste(filename, "gateway.svg", sep=""), height=3.5)

pilotdata = read_csv(paste(filename, "howmanypilots.csv", sep=""))
experiment_time_x_axis(ggplot(pilotdata, aes(x=stamp,y=count)) +
  labs(title = "Number of Pilots over time") +
  lines() + lineLabels() +
  geom_line(mapping=aes(x=stamp,y=count, group=runID), color="gray15", alpha=0.15, show.legend=FALSE) +
  stat_summary_bin(fun.y = "max", aes(colour = "max"), bins=100, geom="line")  +
  stat_summary_bin(fun.y = "median", aes(colour = "median"), bins=100, geom="line")  +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom")
)
ggsave(paste(filename, "howmanypilots.svg", sep=""), width=7, height=3.5)

dataload = read_csv(paste(filename, "nodemon.csv", sep=""), col_types=cols(cpupercent=col_number(), memorypercent=col_number())) %>%
            select(runID, timestamp, nodename, cpupercent, memorypercent) %>%
            gather(metric, percent, -timestamp, -runID, -nodename)
experiment_time_x_axis(ggplot(dataload) +
  labs(title = "Node Utilization") +
  lines() + lineLabels() +
  geom_hline(yintercept = 100, color="grey45") +
  facet_wrap(vars(metric), ncol=1) +
  geom_line(mapping=aes(x=timestamp, y=percent, group=interaction(runID, nodename)), color="gray15", alpha=0.15, show.legend=FALSE) +
  stat_summary_bin(aes(x=timestamp, y=percent, colour="max"),fun.y="max", bins=100, geom="line") +
  stat_summary_bin(aes(x=timestamp, y=percent, colour="median"),fun.y="median", bins=100, geom="line") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="none", axis.title.x=element_blank(), axis.text.x=element_blank()))
ggsave(paste(filename, "nodemon.svg", sep=""), width=7, height=3.5)

memstats = read_csv(paste(filename, "memstats.csv", sep="")) %>% mutate(memory = (used/total) * 1000) %>% select(runID, stamp, memory)
cpustats = read_csv(paste(filename, "cpustats.csv", sep="")) %>% filter(cpuid == "all") %>% mutate(cpu = (100 - idle)) %>% select(runID, stamp, cpuid, cpu)
clientstats = full_join(memstats, cpustats) %>% gather("metric", "percent", -runID, -cpuid, -stamp)

cpu = experiment_time_x_axis(ggplot(clientstats, aes(x=stamp, y=percent)) +
  labs(title = "Client Utilization") +
  ylab("Utilization %") +
  lines() + lineLabels() +
  geom_hline(yintercept = 100, color="grey45") +
  facet_wrap(vars(metric), ncol=1, scales="free_y") +
  geom_line(aes(group=interaction(runID, cpuid)), color="gray15", alpha=0.15) +
  stat_summary_bin(aes(colour="max"),fun.y="max", geom="line", bins=100) +
  stat_summary_bin(aes(colour="median"),fun.y="median", bins=100, geom="line") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="none", axis.title.x=element_blank(), axis.text.x=element_blank()))

ggsave(paste(filename, "resources.svg", sep=""), width=7, height=3.5)

ifstats = read_csv(paste(filename, "ifstats.csv", sep="")) %>% gather("direction", "rate", -runID, -stamp) %>% mutate(rate = rate / 1024)
experiment_time_x_axis(ggplot(ifstats) +
  labs(title = "Client Network Usage") +
  ylab("Speed (mb/s)") +
  lines() + lineLabels() +
  facet_wrap(vars(direction), ncol=1, scales="free_y") +
  geom_line(mapping=aes(x=stamp,y=rate,group=runID), color="grey15", alpha=0.15) +
  stat_summary_bin(aes(x=stamp,y=rate, colour="max"),fun.y="max", geom="line", bins=100) +
  stat_summary_bin(aes(x=stamp,y=rate, colour="median"),fun.y="median", bins=100, geom="line") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="none"))
ggsave(paste(filename, "ifstats.svg", sep=""), width=7, height=3.5)

print("All done!")
