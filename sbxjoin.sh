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

echo "Decoding parts"

for file in $in_prefix.part*.sbx; do
  echo "  Decoding $file"

  output=$(rsbx sort --json $file $file.sorted)
  error=$(echo $output | jq -r ".error")
  if [[ $error != null ]]; then
    echo "    Error occured during sorting"
    echo "    $error"
    exit 1
  fi

  output=$(rsbx repair --json $file.sorted)
  error=$(echo $output | jq -r ".error")
  if [[ $error != null ]]; then
    echo "    Error occured during repairing"
    echo "    $error"
    exit 1
  fi

  output=$(rsbx decode --json $file.sorted)
  if [[ $error != "null" ]]; then
    echo "    Error occured during encoding"
    echo "    $error"
    exit 1
  fi

  recorded_hash=$(echo $output | jq -r ".stats.recordedHash")
  output_hash=$(echo $output | jq -r ".stats.hashOfOutputFile")

  if [[ $recorded_hash != $output_hash ]]; then
    echo "    Error : hash mismatch for $file"
    exit 1
  fi

  rm $file.sorted
done

echo "Concatenating parts"
for file in $in_prefix.part*; do
  if [[ $file == *.sbx ]]; then
    continue
  fi

  echo "  Adding $file to final container"

  cat $file >> $out_container
  rm $file
done

echo "Sorting container"
output=$(rsbx sort --json $out_container $out_container.sorted)
error=$(echo $output | jq -r ".error")
if [[ $error != null ]]; then
  echo "  Error occured during sorting"
  echo "  $error"
  exit 1
fi

mv $out_container.sorted $out_container

echo "Repairing container"
output=$(rsbx repair --json $out_container)
error=$(echo $output | jq -r ".error")
if [[ $error != null ]]; then
  echo "  Error occured during repairing"
  echo "  $error"
  exit 1
fi
repairs_failed=$(echo $output | jq -r ".stats.numberOfBlocksFailedToRepairData")
if (( $repairs_failed > 0 )); then
  echo "  Failed to repair container"
  echo "  The decoded data will have missing data"
fi

echo "Decoding container"
output=$(rsbx decode --json $out_container $out_file)
error=$(echo $output | jq -r ".error")
if [[ $error != null ]]; then
  echo "  Error occured during decoding"
  echo "  $error"
  exit 1
fi

recorded_hash=$(echo $output | jq -r ".stats.recordedHash")
output_hash=$(echo $output | jq -r ".stats.hashOfOutputFile")

echo "Checking hash"
if [[ $recorded_hash != $output_hash ]]; then
  echo "  Error : Output file hash mismatch"
  echo "  Recorded    hash : $recorded_hash"
  echo "  Output file hash : $output_hash"
  exit 1
fi

# clean up
echo "Cleaning up"
rm -rf $out_container

