#!/bin/bash

iid="$1"
tid="$2"
ref="$3"
shift 3

first=
firstthreads=

echo "Test $tid.$iid:"
for run in "$@"; do
  threads="${run##*run.}"
  threads="${threads%%.clean}"
  if [ "`head -1 "$run"`" = "==FAILURE==" ]; then
    printf '  %02d: FAILED (subprocess error)\n' "$threads"
  elif cmp -s "$ref" "$run"; then
    printf '  %02d: OK\n' "$threads"
  elif [ -z "$first" ]; then
    printf '  %02d: FAILED (diff dumped)\n' "$threads"
    first="$run"
    firstthreads="$threads"
  else
    printf '  %02d: FAILED\n' "$threads"
  fi
done
if [ "$first" ]; then
  diff -U 1 "$ref" "$first"
fi
echo
