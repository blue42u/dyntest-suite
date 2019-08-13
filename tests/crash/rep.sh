#!/bin/bash

REP="$1"
OUT="$2"
shift 2

printf "=== %s\nSUMMARY: %0${#REP}d / %d passed.\n" "$*" 0 $REP > "$OUT"

GOOD=0
BAD=0
TOTAL=0
for ((i=0; i<"$REP"; i++)); do
  # In our case, we assume the process will crash when it segfaults rather than
  # using the output to check. Not quite right, but close enough.
  TOTAL=$((TOTAL+1))
  if catchsegv "$@" >> "$OUT" 2>> "$OUT" 3>> "$OUT"
  then GOOD=$((GOOD+1))
  else
    BAD=$((BAD+1))
    if [ $BAD -ge 5 ]; then break; fi
  fi
done

printf "SUMMARY: %d / %d passed, %s lines of trace.\n" $GOOD $TOTAL \
  $((`wc -l < "$OUT"` - 2)) >&2

printf "=== %s\nSUMMARY: %${#REP}d / %${#REP}d passed.\n" "$*" $GOOD $TOTAL \
  | dd status=none conv=notrunc bs=1 of="$OUT"
