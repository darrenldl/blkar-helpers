#!/bin/bash

if (( $# <= 4 )); then
  echo "Usage : in_file out_prefix data_chunk parity_chunk"
  exit 1
fi

in_file=$1
out_prefix=$2
data_chunk=$3
parity_chunk=$4

sbx_version=17
sbx_block_size=512

file_size=$(ls -l dummy | awk '{ print $5 }')

output=$(rsbx calc --json $file_size --sbx-version $sbx_version --rs-data $data_chunk --rs-parity $parity_chunk)

data_block_count=$(echo $output | jq ".stats.dataOnlyBlockCount")
block_set_size=$[$data_block_count / $data_chunk]

output=$(rsbx encode --json $in_file $out_prefix.$in_file \
  --sbx-version $sbx_version --rs-data $data_chunk --rs-parity $parity_chunk --burst $block_set_size)

if [[ $(echo $output | jq ".error") == "null" ]]; then
  echo "Error occured during encoding"
  exit 1
fi

# split the file
for (( i=0; i < $data_chunk; i++ )); do
  dd if=$out_prefix.$in_file of=$out_prefix.part$i bs=$sbx_block_size skip=$[$i * ($block_set_size + 1)]
done

for (( i=0; i < $parity_chunk; i++ )); do
  dd if=$out_prefix.$in_file of=$out_prefix.part$[$i + $data_chunk] bs=$sbx_block_size skip=$[$i * $block_set_size]
done

