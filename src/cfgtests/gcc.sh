#!/bin/bash

## GCC wrapper script to generate RTL blobs.

BINARY=1
OUTPUT=
ARGS=()
for a in "$@"; do
  # Any of -c, -E or -S and its not a binary output.
  if [[ "$a" =~ \-[cES] ]]; then BINARY=
  # Log the output file, so we can do things to it
  elif [[ "$a" == -o ]]; then OUTPUT=NEXT
  elif [[ "$OUTPUT" == NEXT ]]; then OUTPUT="$a"
  # Remove any prefix remappings, we want full paths in the debug info
  elif [[ "$a" =~ \-f[[:alpha:]]*\-prefix\-map=.* ]]; then continue
  # Remove any LTO flags, it messes with the RTL hunts
  elif [[ "$a" == -flto ]]; then continue
  fi
  ARGS+=("$a")
done

# Call the real GCC
"`realpath "$0"`".real "${ARGS[@]}" \
  -g -fdump-rtl-dfinish \
  -fno-eliminate-unused-debug-symbols

# Copy out the binary, so we have it all in one bundle
if [ $BINARY ]; then
  echo "In wrapper" >&2
  cp "$OUTPUT" /rtldumps/
fi

# Copy out any dfinish files, so they don't get removed
for a in "$@"; do
  while :; do
    if [ "$a" = "${a#../}" ]; then break; fi
    a="${a#../}"
  done
  f="$a".318r.dfinish
  if [ -e "$f" ]; then
    rf="`realpath -e "$f"`"
    echo "$f" '->' /rtldumps/"$rf" >&2
    mkdir -p /rtldumps/"`dirname "$rf"`"
    mv "$f" /rtldumps/"$rf"
  fi
done
