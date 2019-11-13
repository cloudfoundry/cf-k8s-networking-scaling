#!/bin/bash

total=1000
group_size=100

# for ((g=0; n<$groups; g +=

# for ((n=0;n<$1;n++))
# do
#   kubetpl render ../yaml/httpbin.yaml -s NAME=httpbin-$n >> $1-bins.yaml
# done
for ((group = 0 ; group <= 10 ; group++)); do
  for ((count = 0; count <= 100; count++)); do
    # echo "group $group num $count"
    kubetpl render ../yaml/httpbin.yaml -s NAME=httpbin-$group-$count -s NAMESPACE=ns-$group >> 10groupsof100.yaml
  done
done


echo "Done"
echo "===="
