library(tidyverse)
library(gridExtra)

options(show.error.locations = TRUE)

filename <- "./"

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

# user_polls = read_csv(paste(filename, "user_poll.csv", sep="")) %>%
#   arrange(stamp) %>%
#   group_by(runID, groupnum) %>%
#   mutate(delta = stamp - lag(stamp, default=stamp[1])) %>%
#   group_by(runID) %>%
#   summarize(med = median(delta), mean=mean(delta), min=min(delta), max(delta))

# print("med")
# print(user_polls$med / 1e6)
# print("mean")
# print(user_polls$mean / 1e6)
# print("min")
# print(user_polls$min)
# print("max")
# print(user_polls$max)

# Control Plane Latency by Percentile
controlplane = read_csv(paste(filename, "user_data.csv", sep="")) %>%
  select(`user id`, `nanoseconds to first success`, `nanoseconds to last error`)
first_values = quantile(controlplane$`nanoseconds to first success`, quantiles)
last_values = quantile(controlplane$`nanoseconds to last error`, quantiles)
controlplane = tibble(quantiles = mylabels, `time to first success` = first_values, `time to last error` = last_values)
gathered.controlplane <- gather(controlplane, event, latency, -quantiles)
colors <- c("time to last error"="black", "time to first success"="gray85")
cplatency = ggplot(gathered.controlplane, aes(x=quantiles, y=latency)) +
  labs(title="Control Plane Latency by Percentile") +
  ylab("Latency (s)") +
  xlab("Percentile") +
  geom_line(mapping = aes(group=event, color=event)) +
  geom_point(mapping = aes(size=1, stroke=0)) + scale_size_identity() +
  # add line for goal
  geom_hline(yintercept = fiveSecondsInNanoseconds, color="#e41a1c", linetype=2) +
  geom_text(mapping = aes(y=fiveSecondsInNanoseconds, x="p68", label="GOAL 5sec at p95"), size=2, vjust=1.5, hjust=1, color="grey25") +
  geom_text(vjust = 0, nudge_y = 0.5, aes(label = secondsFromNanoseconds(latency))) +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  scale_x_discrete(limits=mylabels) +
  scale_colour_manual(values = colors)  +
  our_theme() %+replace%
    theme(legend.position="none")
zoomed = cplatency + coord_cartesian(ylim=c(0,fiveSecondsInNanoseconds * 6)) + # zoom into the first 30s of data
  labs(title=NULL, subtitle="zoomed to 0-30s") +
  our_theme() %+replace%
    theme(legend.position="bottom")

# Control Plane Latency by User ID
controlplane = read_csv(paste(filename, "user_data.csv", sep="")) %>%
  select(runID, userid=`user id`,
         `time to first success`=`nanoseconds to first success`,
         `time to last error`=`nanoseconds to last error`,
         `start time`) %>%
  extract(userid, c("userid","groupid"), "(.+)g(.+)", convert=TRUE)
# stamp, gateway, route -> they're all group 0, so route = httpbin-USERID-g0.example.com
gatewaytouser = read_csv(paste(filename, "envoy_endpoint_arrival.csv", sep=""), col_types=cols(stamp=col_number())) %>%
  extract(gateway, "gateway", "istio-ingressgateway-.*-(.+)") %>%
  extract(route, c("userid","groupid"), "httpbin-(.+)-g(.+).example.com", convert=TRUE)
gatewaysbyroute = gatewaytouser %>% group_by(stamp, runID, userid, groupid) %>% summarize(gcount=n()) %>%
  group_by(runID,userid, groupid) %>% mutate(totalgateways = cumsum(gcount)) %>%
  select(stamp, runID, userid, groupid, totalgateways)
gatewaygoal = max(gatewaysbyroute$totalgateways) # all the gateways == the most anyone ever has
gateway_startend = gatewaysbyroute %>% group_by(runID,userid, groupid) %>%
  summarize(minGateways = min(totalgateways),
            firstGatewayTime=stamp[which(totalgateways==minGateways)],
            allGatewayTime=stamp[which(totalgateways==gatewaygoal)][1]) %>%
  left_join(controlplane, by=c("userid","groupid","runID")) %>%
  mutate(firstg = firstGatewayTime - `start time`, allg = allGatewayTime - `start time`) %>%
  select(runID, userid, groupid,
         `first success`=`time to first success`,
         `last error`=`time to last error`,
         `first gateway`=firstg,
         `last gateway`=allg) %>%
  gather(event, latency, -userid, -groupid, -runID)
maxuserid = max(gateway_startend$userid) + 1
gateway_startend = gateway_startend %>% mutate(uid = maxuserid * groupid + userid)
cplatency.time <- ggplot(gateway_startend, aes(x=uid, y=latency)) +
  labs(title="Control Plane Latency by User ID") +
  ylab("Latency (s)") + xlab("User ID") +
  scale_y_continuous(labels=secondsFromNanoseconds) +
  # add line for goal
  geom_hline(yintercept = fiveSecondsInNanoseconds, color="#e41a1c", linetype=2) +
  geom_text(mapping = aes(y=fiveSecondsInNanoseconds, x=0, label="GOAL 5sec at p95"), size=2, vjust=1.5, hjust=-0.5, color="grey25") +
  facet_wrap(vars(event), ncol=1) +
  geom_line(color="black", alpha=0.25) +
  stat_summary_bin(aes(colour="max"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(aes(colour="median"), fun.y = "median", bins=100, geom="line") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace% theme(legend.position="bottom")

ggsave(paste(filename, "controlplane.png", sep=""), arrangeGrob(arrangeGrob(cplatency, zoomed), cplatency.time), height=15, width=7)

print("Timestamp vs Avg Latency (ms) for very large numbers of runs")
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
  our_theme() %+replace% theme(legend.position="none")
overtime.max <- experiment_time_x_axis(overtime.max)
overtime.zoomed <- overtime.max + coord_cartesian(ylim=c(0,50)) + # zoom into the first 50ms of data
  labs(title=NULL, subtitle="Both zoomed to 0-50ms") +
    our_theme() %+replace% theme(legend.position="bottom")
ggsave(paste(filename, "dataload_time.png", sep=""), arrangeGrob(overtime.max, overtime.zoomed), width=7, height=10)

quantiles = c(0.68, 0.90, 0.99, 0.999, 0.9999, 0.99999, 1)
mylabels = c("p68", "p90", "p99", "p999", "p9999", "p99999", "max")

print("Latency (ms) by Percentile")
dataload = read_csv(paste(filename, "rawlatencies.txt", sep=""))
values = quantile(dataload$latency, quantiles)
dataload = tibble(mylabels, values)
dataplane.max <- ggplot(dataload, aes(x=mylabels, y=values)) +
  labs(title = "Dataplane Latency (ms) by Percentile") +
  # add line for goal
  geom_hline(yintercept = 20, color="gray75", linetype=2) +
  geom_text(mapping = aes(y=20, x="p68", label="GOAL 20ms added latency"), size=2, vjust=-0.5, hjust=0.35, color="grey25") +
  geom_line(mapping = aes(group="not the default")) +
  geom_point(mapping = aes(size=1, stroke=0)) + scale_size_identity() +
  scale_x_discrete(limits = mylabels) +
  ylab("Latency (ms)") +  xlab("Percentile") +
  our_theme() %+replace% theme(legend.position="none")
dataplane.zoomed <- dataplane.max +
  labs(title=NULL, subtitle="zoomed to 0-50ms") +
    our_theme() %+replace% theme(legend.position="bottom")
dataplane.zoomed <- dataplane.zoomed + coord_cartesian(ylim=c(0,50))
ggsave(paste(filename, "dataload_percentile.png", sep=""), arrangeGrob(dataplane.max, dataplane.zoomed), width=7, height=7)

# print("Sidecar memory usage for large numbers of runs")
# sidecar = read_csv(paste(filename, "sidecarstats.csv", sep=""))
# experiment_time_x_axis(ggplot(sidecar) +
#   labs(title = "Envoy Sidecar Memory Usage Over Time") +
#   ylab("Memory (mb)") +
#   lines() + lineLabels() +
#   # add line for goal
#   geom_hline(yintercept = bytes_from_mb(100), color="gray75", linetype=2) +
#   geom_line(mapping = aes(x=timestamp, y=memory, group=interaction(runID,podname)), color="gray15", alpha=0.15) +
#   stat_summary_bin(aes(x=timestamp,y=memory, colour = "max"), fun.y = "max", bins=100, geom="line") +
#   stat_summary_bin(aes(x=timestamp,y=memory, colour = "median"), fun.y = "median", bins=100, geom="line") +
#   geom_text(mapping = aes(y=bytes_from_mb(100), x=0, label="GOAL 100MB added per pod"), size=2, vjust=-0.6, hjust=0.15, color="grey25") +
#   scale_y_continuous(labels=mb_from_bytes) +
#   scale_colour_brewer(palette = "Set1") +
#   our_theme() %+replace%
#     theme(strip.placement = "outside", legend.position="bottom"))
# ggsave(paste(filename, "sidecar.png", sep=""), height=3.5)


# print("Gateway memory usage for large number of runs")
# gateway = read_csv(paste(filename, "gatewaystats.csv", sep=""))
# experiment_time_x_axis(ggplot(gateway) +
#   labs(title = "Gateway Memory Usage over Time") +
#   ylab("Memory (mb)") +
#   lines() + lineLabels() +
#   # add line for goal
#   geom_hline(yintercept = bytes_from_mb(2000), color="gray75", linetype=2) +
#   geom_line(mapping = aes(x=timestamp, y=memory, group=interaction(runID,podname)), color="gray15", alpha=0.15) +
#   stat_summary_bin(aes(x=timestamp,y=memory, colour = "max"), fun.y = "max", bins=100, geom="line") +
#   stat_summary_bin(aes(x=timestamp,y=memory, colour = "median"), fun.y = "median", bins=100, geom="line") +
#   geom_text(mapping = aes(y=bytes_from_mb(2000), x=0, label="GOAL 2GB added per ingressgateway"), size=2, vjust=-0.6, hjust=0.12, color="grey25") +
#   scale_y_continuous(labels=mb_from_bytes) +
#   scale_colour_brewer(palette = "Set1") +
#   our_theme() %+replace%
#     theme(strip.placement = "outside", legend.position="bottom"))
# ggsave(paste(filename, "gateway.png", sep=""), height=3.5)

print("Number of Pilots over time")
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
ggsave(paste(filename, "howmanypilots.png", sep=""), width=7, height=3.5)

print("Node Utilization")
dataload = read_csv(paste(filename, "nodemon.csv", sep=""), col_types=cols(percent=col_number()))
experiment_time_x_axis(ggplot(dataload) +
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

print("Client Utilization")
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

print("Client Network Utilization")
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
