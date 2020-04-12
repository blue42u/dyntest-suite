#!/bin/bash

mode="$1"
iid="$2"
tid="$3"
shift 3

if [ "$mode" = "ref" ]; then
  ref="$1"
  rone="$2"
  shift 2
else
  ref="$1"
  rone="$1"
  shift 1
fi

echo "Test $tid.$iid:"

serialdiff=
if [ "$mode" = "ref" ]; then
  # First handle the serial run
  if cmp --quiet "$rone" failure.txt; then
    printf '  01: FAILED (subprocess error)\n'
  elif cmp -s "$ref" "$rone"; then
    printf '  01: OK\n'
  else
    printf '  01: SUBOPTIMAL (differs from reference)\n'
    serialdiff=yes
  fi
fi

# Then the other runs
first=
for run in "$@"; do
  threads="${run##*run.}"
  threads="${threads%%.clean}"
  if cmp --quiet "$run" failure.txt; then
    printf '  %02d: FAILED (subprocess error)\n' "$threads"
  elif cmp -s "$ref" "$run"; then
    printf '  %02d: OK\n' "$threads"
  elif [ "$mode" = "ref" ] && cmp -s "$rone" "$run"; then
    printf '  %02d: SUBOPTIMAL\n' "$threads"
  elif [ -z "$first" ]; then
    printf '  %02d: FAILED (diff dumped)\n' "$threads"
    first="$run"
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
