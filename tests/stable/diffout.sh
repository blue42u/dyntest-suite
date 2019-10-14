#!/bin/bash

iid="$1"
tid="$2"
ref="$3"
rone="$4"
shift 4


echo "Test $tid.$iid:"

# First handle the serial run
serialdiff=
if [ "`head -1 "$rone"`" = "==FAILURE==" ]; then
  printf '  01: FAILED (subprocess error)\n'
elif cmp -s "$ref" "$rone"; then
  printf '  01: OK\n'
else
  printf '  01: SUBOPTIMAL (differs from reference)\n'
  serialdiff=yes
fi

# Then the other runs
first=
firstthreads=
for run in "$@"; do
  threads="${run##*run.}"
  threads="${threads%%.clean}"
  if [ "`head -1 "$run"`" = "==FAILURE==" ]; then
    printf '  %02d: FAILED (subprocess error)\n' "$threads"
  elif cmp -s "$ref" "$run"; then
    printf '  %02d: OK\n' "$threads"
  elif cmp -s "$rone" "$run"; then
    printf '  %02d: SUBOPTIMAL\n' "$threads"
  elif [ -z "$first" ]; then
    printf '  %02d: FAILED (diff dumped)\n' "$threads"
    first="$run"
    firstthreads="$threads"
  else
    printf '  %02d: FAILED\n' "$threads"
  fi
done

# Finally, dump a diff
if [ "$first" ]; then
  diff -ZbEU 5 "$rone" "$first"
elif [ "$serialdiff" ]; then
  diff -ZbEU 5 "$ref" "$rone"
fi
echo
