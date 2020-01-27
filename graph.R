library(tidyverse)
library(gridExtra)
library(anytime)
options(digits.secs=6)                ## for fractional seconds below
Sys.setenv(TZ=anytime:::getTZ())      ## helper function to try to get TZ

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

breaksFromZero <- seq(from=zeroPoint, to=maxSec, by=10 * 60 * 1000 * 1000 * 1000)

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

print("pilot proxy convergence")
# stamp, count
pilot_proxy_max = read_csv(paste(filename, "100convergence.csv", sep="")) %>%
  add_column(pvalue = "max")
pilot_proxy_p99 = read_csv(paste(filename, "99convergence.csv", sep="")) %>%
  add_column(pvalue = "p99")
pilot_proxy_p90 = read_csv(paste(filename, "90convergence.csv", sep="")) %>%
  add_column(pvalue = "p90")
pilot_proxy_p68 = read_csv(paste(filename, "68convergence.csv", sep="")) %>%
  add_column(pvalue = "p68")
pilot_proxy = bind_rows(pilot_proxy_max, pilot_proxy_p99, pilot_proxy_p90, pilot_proxy_p68)

pilotproxy_plot = experiment_time_x_axis(ggplot(pilot_proxy) +
  labs(title="Proxy-Pilot Convergence Latency over Time") +
  ylab("Latency (s)") +
  lines() +
  geom_line(mapping=aes(x=stamp, y=count, color=pvalue)) +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom"))

pilot_xds = read_csv(paste(filename, "pilot_xds.csv", sep=""))
pilotxds_plot = experiment_time_x_axis(ggplot(pilot_xds, aes(x=stamp, y=count)) +
  labs(title="Pilot XDS over Time") +
  ylab("Count of Envoys Connected") +
  lineLabels() + lines() +
  geom_line(mapping=aes(group=instance), color="black", alpha=0.2) +
  stat_summary_bin(aes(colour="max"), fun.y = "max", bins=100, geom="line") +
  stat_summary_bin(aes(colour="median"), fun.y = "median", bins=100, geom="line") +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom"))

ggsave(paste(filename, "convergence.png", sep=""), arrangeGrob(pilotproxy_plot, pilotxds_plot))

print("Control Plane Latency by Percentile")
controlplane = read_csv(paste(filename, "user_data.csv", sep="")) %>%
  select(`user id`, `start time`, `nanoseconds to first success`, `nanoseconds to last error`) %>%
  extract(`user id`, c("userid","groupid"), "(.+)g(.+)", convert=TRUE)
# stamp, gateway, route -> they're all group 0, so route = httpbin-USERID-g0.example.com
gatewaytouser = read_csv(paste(filename, "endpoint_arrival.csv", sep=""), col_types=cols(stamp=col_number())) %>%
  extract(gateway, "gateway", "istio-ingressgateway-.*-(.+)") %>%
  extract(route, c("userid","groupid"), "httpbin-(.+)-g(.+).example.com", convert=TRUE)
gatewaysbyroute = gatewaytouser %>% group_by(stamp, userid, groupid) %>% summarize(gcount=n()) %>%
  arrange(stamp) %>% group_by(userid, groupid) %>%
  mutate(totalgateways = cumsum(gcount)) %>% select(stamp, userid, groupid, totalgateways)
gatewaygoal = max(gatewaysbyroute$totalgateways) # all the gateways == the most anyone ever has
gateway_startend = gatewaysbyroute %>% group_by(userid, groupid) %>%
  summarize(minGateways = min(totalgateways),
            firstGatewayTime=stamp[which(totalgateways==minGateways)],
            allGatewayTime=stamp[which(totalgateways==gatewaygoal)][1]) %>%
  left_join(controlplane, by=c("userid","groupid")) %>%
  mutate(firstg = firstGatewayTime - `start time`, allg = allGatewayTime - `start time`)

first_values = quantile(gateway_startend$`nanoseconds to first success`, quantiles, na.rm=TRUE)
last_values = quantile(gateway_startend$`nanoseconds to last error`, quantiles, na.rm=TRUE)
first_gs = quantile(gateway_startend$firstg, quantiles, na.rm = TRUE)
last_gs = quantile(gateway_startend$allg, quantiles, na.rm=TRUE) # we do not have max gateway value for some users
controlplane = tibble(quantiles = mylabels, `time to first success` = first_values, `time to last error` = last_values, `time to first gateway` = first_gs, `time to max gateways`=last_gs)
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
ggsave(paste(filename, "controlplane.png", sep=""), width=7, height = 3.5)

print("Errors by User ID")
# stamp,usernum,groupnum,event,status,logfile
userlog = read_csv(paste(filename, "user.log", sep=""), col_types=cols(stamp=col_number(),status=col_factor()))
userstarts = userlog %>% filter(event == "STARTED") %>% select(stamp, usernum, groupnum)
maxUser = max((userlog %>% filter(groupnum == 0))$usernum) + 1
usererrors = userlog %>% filter(event == "FAILURE")%>%
  select(stamp, usernum, groupnum, status) %>%
  left_join(userstarts, by=c("usernum", "groupnum"), suffix=c("Error","Start")) %>%
  mutate(latency = stampError - stampStart, userid = usernum + (maxUser * groupnum)) %>%
  select(stampError, latency, userid, status)

errorLatency = ggplot(usererrors, aes(x=latency, y=userid, color=status)) +
  labs(title = "Distribution of Errors by per UserID latency") +
  xlab("Latency (s)") +
  ylab("User ID") +
  geom_point(alpha=0.2) +
  scale_colour_brewer(palette = "Set1") +
  scale_x_continuous(labels=secondsFromNanoseconds) +
  our_theme() %+replace%
    theme(legend.position="bottom")
errorTime = experiment_time_x_axis(ggplot(usererrors, aes(x=stampError, y=userid, color=status)) +
  labs(title = "Distribution of Errors by per UserID latency") +
  xlab("Latency (s)") +
  ylab("User ID") +
  lineLabels() + lines() + 
  geom_point(alpha=0.2) +
  scale_colour_brewer(palette = "Set1") +
  our_theme() %+replace%
    theme(legend.position="bottom"))
ggsave(paste(filename, "cperrors.png", sep=""), arrangeGrob(errorLatency, errorTime), width=7, height = 7)

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

ggsave(paste(filename, "dataload.png", sep=""), arrangeGrob(overtime, bypercent))

print("Sidecar Memory")
sidecar = read_csv(paste(filename, "sidecarstats.csv", sep=""))
experiment_time_x_axis(ggplot(sidecar) +
  labs(title = "Envoy Sidecar Memory Usage Over Time") +
  ylab("Memory (mb)") + lines() +
  geom_line(mapping = aes(x=timestamp, y=memory, group=podname), alpha=0.25, color="black") +
  scale_y_continuous(labels=mb_from_bytes) +
  our_theme() %+replace%
    theme(strip.background = element_blank(), strip.placement = "outside"))
ggsave(paste(filename, "sidecar.png", sep=""), width=7, height=5)

print("Gateway Memory")
gateway = read_csv(paste(filename, "gatewaystats.csv", sep=""))
experiment_time_x_axis(ggplot(gateway) +
  labs(title = "Gateway Memory Usage over Time") +
  ylab("Memory (mb)") + lines() +
  geom_line(rename(gateway, pod=podname), mapping = aes(x=timestamp, y = memory, group=pod, color=pod), alpha=0.25, color="black") +
  scale_y_continuous(labels=mb_from_bytes) +
  lineLabels() +
  our_theme() %+replace%
    theme(legend.position="none"))
ggsave(paste(filename, "gateway.png", sep=""), width=7, height=3.5)

print("Pilot Count")
dataload = read_csv(paste(filename, "howmanypilots.csv", sep=""))
experiment_time_x_axis(ggplot(dataload) +
  labs(title = "Number of Pilots over time") +
  geom_line(mapping=aes(x=stamp,y=count)) +
  lineLabels() + lines() +
  our_theme())
ggsave(paste(filename, "howmanypilots.png", sep=""), width=7, height=3.5)

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
  mutate(hasIstio = if_else(str_detect(podtypes, "istio"), "with istio", "without istio"))

print("Picking busiest nodes")
busynodenames = nodeusage %>% group_by(nodename) %>% summarize(maxcpu = max(cpu, na.rm=TRUE)) %>% top_n(3,maxcpu)
busynodes = busynodenames %>% left_join(nodeusage) %>% select(timestamp, nodename, cpu, memory, hasIstio)

nodeusage = nodeusage %>% gather(type, percent, -nodename, -timestamp, -hasIstio, -podtypes)
busynodes = busynodes %>% gather(type, percent, -nodename, -timestamp, -hasIstio)

print("Usage by Node")
experiment_time_x_axis(ggplot(nodeusage) +
  labs(title = "Node Utilization", subtitle="100% = utilizing the whole machine") +
  ylab("Utilization %") + ylim(0,100) + lines() +
  facet_wrap(vars(hasIstio, type), ncol=1) +
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

print("Gateway config")
controlplane = read_csv(paste(filename, "user_data.csv", sep="")) %>%
  select(userid=`user id`,start =`start time`) %>%
  extract(userid, c("userid","groupid"), "(.+)g(.+)", convert=TRUE)
maxUserid = max(controlplane$userid) + 1
controlplane = controlplane %>% mutate(uid= maxUserid * groupid + userid)

gatewaysbyroute_fromstart = gatewaysbyroute %>%
  left_join(controlplane, by=c("userid","groupid")) %>%
  mutate(fromstart = stamp - start)

trajectories = ggplot(gatewaysbyroute_fromstart) +
  labs(title = "Gateways per User Routes by time since creation") +
  xlab("Time (seconds)") + scale_x_continuous(labels=secondsFromNanoseconds) +
  scale_colour_distiller(palette="Spectral") +
  geom_line(mapping=aes(x=fromstart, y=totalgateways, group=uid, color=uid), alpha=0.05) +
  our_theme() %+replace%
    theme(legend.position="bottom")

gateway_startend = gateway_startend %>% mutate(uid= maxUserid * groupid + userid)

oneline = ggplot(gateway_startend) +
  labs(title = "Latency by Userid") +
  ylab("Time (seconds)") + scale_y_continuous(labels=secondsFromNanoseconds) +
  scale_colour_brewer(palette = "Set1") +
  geom_line(mapping=aes(x=uid, y=`nanoseconds to first success`, color="First Success"), alpha=0.6) +
  geom_line(mapping=aes(x=uid, y=`nanoseconds to last error`, color="Last Error"), alpha=0.6) +
  geom_line(mapping=aes(x=uid, y=firstg, color="First Gateway"), alpha=0.6) +
  geom_line(mapping=aes(x=uid, y=allg, color="All Gateways"), alpha=0.6) +
  our_theme() %+replace%
    theme(legend.position="bottom")
ggsave(paste(filename, "endpoint_arrival.png", sep=""), arrangeGrob(trajectories, oneline), width=7, height=8)

print("All done.")
