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
  if cmp -s "$ref" "$run"; then
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
  diff -d --unchanged-group-format='' \
    --new-group-format='Additional/bogus %dN lines:
%>' \
    --old-group-format='Missing %dn lines:
%<' \
    --changed-group-format='Replaced %n lines (%dn -> %dN):
%<With %dN lines (%dn -> %dN):
%>' \
    --old-line-format='-%L' --new-line-format='+%L' "$ref" "$first"
fi
echo
