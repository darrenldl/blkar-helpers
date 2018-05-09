#!/bin/bash

if (( $# < 4 )); then
  echo "Usage : in_file out_prefix data_chunk parity_chunk"
  exit 1
fi

in_file=$1
out_prefix=$2
data_chunk=$3
parity_chunk=$4

sbx_version=17
sbx_block_size=512

file_size=$(ls -l $in_file | awk '{ print $5 }')

output=$(rsbx calc --json $file_size --sbx-version $sbx_version --rs-data $data_chunk --rs-parity $parity_chunk)

data_block_count=$(echo $output | jq -r ".stats.dataOnlyBlockCount")
block_set_size=$[$data_block_count / $data_chunk]

output=$(rsbx encode --json $in_file $out_prefix.$in_file.tmp \
  --sbx-version $sbx_version --rs-data $data_chunk --rs-parity $parity_chunk --burst $block_set_size)
error=$(echo $output | jq -r ".error")
if [[ $error != "null" ]]; then
  echo "Error occured during encoding"
  echo $error
  exit 1
fi

# split the file
for (( i=0; i < $data_chunk; i++ )); do
  dd if=$out_prefix.$in_file.tmp of=$out_prefix.part$i \
    bs=$sbx_block_size skip=$[$i * ($block_set_size + 1)] count=$[$block_set_size + 1] &>/dev/null
done

skip_base=$[$data_chunk * ($block_set_size + 1)]

for (( i=0; i < $parity_chunk; i++ )); do
  chunk_index=$[$i + $data_chunk]
  dd if=$out_prefix.$in_file.tmp of=$out_prefix.part$chunk_index \
    bs=$sbx_block_size skip=$[$i * $block_set_size + $skip_base] count=$block_set_size &>/dev/null
done

# clean up
rm $out_prefix.$in_file.tmp

