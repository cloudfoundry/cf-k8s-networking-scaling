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
routes = read_csv("./route-status.csv", col_types=cols(status=col_factor()))
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

ggsave(paste(filename, "routes.png", sep=""), route_status)

print("Graph Configs Sent")
xds = read_delim("./jaeger.csv", ";")
xds = xds %>% separate_rows(Routes, convert = TRUE) # one row per observation of a route being configured
configs_sent =ggplot(xds) +
  labs(title="Config Sent over Time") +
  ylab("Route Number") +
  facet_wrap(vars(Type), ncol=1) +
  geom_point(mapping=aes(x=Date, y=Routes, color=Version), alpha=0.5, size=0.4) +
  scale_size_area() +
  scale_colour_distiller(palette="Spectral") +
  our_theme() %+replace%
    theme(legend.position="bottom")

ggsave(paste(filename, "config.png", sep=""), configs_sent)

print("Latency between Config Sent and Route Working")
scaleMicroToNano <- function(x, na.rm = FALSE) x * 10^3
configs = xds %>% filter(Type == "Cluster") %>%
  select(stamp=Timestamp, route=Routes) %>%
  mutate_at("stamp", scaleMicroToNano) %>%
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

ggplot(all.withtimes) +
  labs(title="Latency from Config Sent to Route returns 200") +
  xlab("Time (seconds)") +
  scale_x_continuous(labels=secondsFromNanoseconds) +
  ylab("Route Number") +
  geom_point(mapping=aes(x=time_diff, y=route)) +
  our_theme() %+replace%
    theme(legend.position="bottom")

ggsave(paste(filename, "latency.png", sep=""))

