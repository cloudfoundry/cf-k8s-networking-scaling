# Istio Scaling Experiment

_Possibly the most expensive static site generator ever._

This repo holds the code for our reproducable istio control plane scaling stress
test.

## Requirements

At this time the known requirements are as follows:

* normal GNU utilities i.e. `tee`, `awk`, `date`, etc. just don't run this on a
  busybox
* curl & wget
* rust (for `cargo build`)
* R (for `Rscript ...`)
* ruby (a somewhat recent version, the one in snap is fine)
* gcloud, logged in and capable of creating clusters
* kubectl
* [kubetpl](https://github.com/shyiko/kubetpl)
* helm
* jq
* ifstat
* mpstat
* apib for load testing, specifically [our
  fork](https://github.com/xanderstrike/apib) that provides raw latency data and
  p68 instead of p50 installed in your path
* Some way to serve HTML from your test machine
  * If it's local you'll just have to open the `index.html`s in your browser
  * `python -m SimpleHTTPServer 80` or `docker run -p 80:80 -v $(pwd):/usr/share/nginx/html jrelva/nginx-autoindex`

If you attempt to run this and come across more requirements please make an
issue.

We have a GCP vm snapshot that runs this script no problem, so if you're in the
pivotal org hit us up and we'll give you a VM that's ready to go.

## Running

0. Download a version of istio and put it somewhere you'll have access to while
   running the experiment. You should not need to modify it.
0. Set up `vars.sh` with your desired experiment design, make sure to point it at
   your istio folder
0. Set up `values.yaml` with your preferred overrides.
0. Execute `./run.sh $name $num`
   * $name is the name of your experiment
   * $num is the number of times to run the test
0. In your web browser, navigate to `experiments/$name` and you'll be able to
   see the results. At the bottom, you can dive into individual tests and
   download the combined csv files.

