#!/bin/bash

if (( $# < 2 )); then
  echo "Usage : in_prefix out_file"
  exit 1
fi

in_prefix=$1
out_file=$2

sbx_version=17
sbx_block_size=512

out_container=$in_prefix.$out_file.tmp
rm -rf $out_container

echo "Concatenating parts"
for file in $in_prefix.part*; do
  cat $file >> $out_container
done

echo "Sorting container"
output=$(rsbx sort --json $out_container $out_container.sorted)
error=$(echo $output | jq -r ".error")
if [[ $error != null ]]; then
  echo "Error occured during sorting"
  echo $error
  exit 1
fi

mv $out_container.sorted $out_container

echo "Repairing container"
output=$(rsbx repair --json $out_container)
error=$(echo $output | jq -r ".error")
if [[ $error != null ]]; then
  echo "Error occured during repairing"
  echo $error
  exit 1
fi

echo "Decoding container"
output=$(rsbx decode --json $out_container $out_file)
error=$(echo $output | jq -r ".error")
if [[ $error != null ]]; then
  echo "Error occured during repairing"
  echo $error
  exit 1
fi

recorded_hash=$(echo $output | jq -r ".stats.recordedHash")
output_hash=$(echo $output | jq -r ".stats.hashOfOutputFile")

if [[ $recorded_hash != $output_hash ]]; then
  echo "Error : Output file hash mismatch"
  exit 1
fi

# clean up
rm -rf $out_container
