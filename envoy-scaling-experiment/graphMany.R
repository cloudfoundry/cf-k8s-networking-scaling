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


print("Graph Route Statuses")
# timestamp, runID, status, route
routes = read_csv("./route-status.csv", col_types=cols(status=col_factor(), route=col_integer())) %>% drop_na()

print("Graph Configs Sent")
xds = read_csv("./jaeger.csv")
xds = xds %>%
  separate_rows(Routes, convert = TRUE) %>%  # one row per observation of a route being configured
  drop_na() # sometimes route is NA, so drop those

print("Latency between Config Sent and Route Working")
scaleMicroToNano <- function(x, na.rm = FALSE) x * 10^3
configs = xds %>% filter(Type == "RouteConfiguration") %>%
  select(runID, stamp=Timestamp, route=Routes) %>%
  arrange(stamp) %>%
  group_by(runID, route) %>%  slice(1L) %>% ungroup()
observations = routes %>% filter(status == "200") %>%
  select(runID, stamp, route) %>%
  arrange(stamp) %>%
  group_by(runID, route) %>%  slice(1L) %>% ungroup()
halfRoute = max(configs$route) / 2
all.withtimes = left_join(configs, observations, by=c("runID","route")) %>%
  filter(route < halfRoute) %>%
  mutate(time_diff = stamp.y - stamp.x)

values = quantile(all.withtimes$time_diff, quantiles)
cptails = tibble(mylabels, values)
ggplot(cptails, aes(x=mylabels, y=values)) +
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
ggsave(paste(filename, "latency.png", sep=""), width=7, height=4)


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
