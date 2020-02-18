require "sqlite3"

puts "here we go"

folders = `ls | grep gabe`.split("\n")

`rm /tmp/mydb`

%x(
sqlite3 "/tmp/mydb" << EOF
.mode csv
.separator ',' "\\\\n"
.import "#{folders[0]}/nodes4pods.csv" "nodes4pods"
.import "#{folders[0]}/nodemon.csv" "nodemon0"
.import "#{folders[0]}/importanttimes.csv" "itimes0"
.import "#{folders[1]}/nodes4pods.csv" "nodes4pods"
.import "#{folders[1]}/nodemon.csv" "nodemon1"
.import "#{folders[1]}/importanttimes.csv" "itimes1"
.import "#{folders[2]}/nodes4pods.csv" "nodes4pods"
.import "#{folders[2]}/nodemon.csv" "nodemon2"
.import "#{folders[2]}/importanttimes.csv" "itimes2"

create table loaded as
  select * from nodemon0 where timestamp > (select stamp from itimes0 where event = "GENERATE CP LOAD") and timestamp < (select stamp from itimes0 where event = "CP LOAD COMPLETE")
  union
  select * from nodemon1 where timestamp > (select stamp from itimes1 where event = "GENERATE CP LOAD") and timestamp < (select stamp from itimes1 where event = "CP LOAD COMPLETE")
  union
  select * from nodemon2 where timestamp > (select stamp from itimes2 where event = "GENERATE CP LOAD") and timestamp < (select stamp from itimes2 where event = "CP LOAD COMPLETE");

create table idle as
  select * from nodemon0 where timestamp > (select stamp from itimes0 where event = "CP LOAD COMPLETE") and timestamp < (select stamp from itimes0 where event = "TEST COMPLETE")
  union
  select * from nodemon1 where timestamp > (select stamp from itimes1 where event = "CP LOAD COMPLETE") and timestamp < (select stamp from itimes1 where event = "TEST COMPLETE")
  union
  select * from nodemon2 where timestamp > (select stamp from itimes2 where event = "CP LOAD COMPLETE") and timestamp < (select stamp from itimes2 where event = "TEST COMPLETE")
EOF
)

db = SQLite3::Database.new "/tmp/mydb"

pilot_idle = db.execute <<-SQL
  select
    type,
    max(percent*1.0) ma
  from idle
    left join nodes4pods on node = nodename
  where pod like "%pilot%" group by type order by type;
SQL

pilot_load = db.execute <<-SQL
  select
    type,
    max(percent*1.0) ma
  from loaded
    left join nodes4pods on node = nodename
  where pod like "%pilot%" group by type order by type;
SQL


gateway_idle = db.execute <<-SQL
  select
    type,
    max(percent*1.0) ma
  from idle
    left join nodes4pods on node = nodename
  where pod like "%gateway%" group by type order by type;
SQL

gateway_load = db.execute <<-SQL
  select
    type,
    max(percent*1.0) ma
  from loaded
    left join nodes4pods on node = nodename
  where pod like "%gateway%" group by type order by type;
SQL


puts pilot_load.inspect

puts "pilot idle\tpilot load\tig idle\t\tig load"
puts "cpu\tram\tcpu\tram\tcpu\tram\tcpu\tram\t"
arr = []
[pilot_idle, pilot_load, gateway_idle, gateway_load].each { |x| arr += x.map(&:last) }
arr = arr.map {|n| n.round(2)}
puts arr.join("\t")
puts "pasteable:"
puts arr.join(",")
