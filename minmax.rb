require "sqlite3"

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

create table nodemon as
  select * from nodemon0 where timestamp > (select stamp from itimes0 where event = "GENERATE CP LOAD")
  union
  select * from nodemon1 where timestamp > (select stamp from itimes1 where event = "GENERATE CP LOAD")
  union
  select * from nodemon2 where timestamp > (select stamp from itimes2 where event = "GENERATE CP LOAD");
EOF
)

db = SQLite3::Database.new "/tmp/mydb"

pilot = db.execute <<-SQL
  select
    "pilot",
    type,
    min(percent*1.0) mi,
    max(percent*1.0) ma,
    avg(percent*1.0) av
  from nodemon
    left join nodes4pods on node = nodename
  where pod like "%pilot%" group by type;
SQL


ig = db.execute <<-SQL
  select
    "ingress",
    type,
    min(percent*1.0) mi,
    max(percent*1.0) ma,
    avg(percent*1.0) av
  from nodemon
    left join nodes4pods on node = nodename
  where pod like "%ingress%" group by type;
SQL

puts "pilot idle\tpilot load\tig idle\t\tig load"
puts "cpu\tram\tcpu\tram\tcpu\tram\tcpu\tram\t"
arr = [
  (pilot[0][2] * 10).round(2), # idle cpu
  (pilot[1][2] * 10).round(2), # idle ram
  (pilot[0][3] * 10).round(2), # loaded cpu
  (pilot[1][3] * 10).round(2), # loaded ram
  (ig[0][2] * 10).round(2), # idle cpu
  (ig[1][2] * 10).round(2), # idle ram
  (ig[0][3] * 10).round(2), # loaded cpu
  (ig[1][3] * 10).round(2), # loaded ram
]
puts arr.join("\t")
puts "pasteable:"
puts arr.join(",")
