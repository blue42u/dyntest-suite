#!/bin/bash

REP="$1"
OUT="$2"
shift 2

printf "=== %s\nSUMMARY: %0${#REP}d / %d passed.\n" "$*" 0 $REP > "$OUT"

GOOD=0
for ((i=0; i<"$REP"; i++)); do
  # In our case, we assume the process will crash when it segfaults rather than
  # using the output to check. Not quite right, but close enough.
  if catchsegv "$@" >> "$OUT"
  then GOOD=$((GOOD+1))
  fi
done

printf "SUMMARY: %${#REP}d / %d passed, %s lines of trace.\n" $GOOD $REP \
  $((`wc -l < "$OUT"` - 2)) >&2

printf "=== %s\nSUMMARY: %${#REP}d / %d passed.\n" "$*" $GOOD $REP \
  | dd status=none conv=notrunc bs=1 of="$OUT"
