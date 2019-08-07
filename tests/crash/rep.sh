#!/bin/bash

REP="$1"
OUT="$2"
shift 2

set -e

printf "SUMMARY: %0${#REP}d / %d sucessful, %0${#REP}d crashes.\n" 0 $REP 0 > "$OUT"

GOOD=0
BAD=0
for ((i=0; i<"$REP"; i++)); do
  # In our case, we assume the process will crash when it segfaults rather than
  # using the output to check. Not quite right, but close enough.
  if catchsegv "$@" >> "$OUT"
  then GOOD=$((GOOD+1))
  else BAD=$((BAD+1))
  fi
done
echo >> "$OUT"

printf "SUMMARY: %${#REP}d / %d sucessful, %${#REP}d crashes.\n" \
  $GOOD $REP $BAD | dd status=none conv=notrunc bs=1 of="$OUT"
