#!/bin/bash

TMPDIRS=()
declare -A OUTPUTS

set -e

trap 'rm -rf "${TMPDIRS[@]}"' EXIT

# Read in each argument and do the transformations nessesary.
CMD=()
for a in "$@"; do
  case "$a" in
  @@*)  # Output file, remember to compress after the fact
    TMP="`mktemp -d`"
    rmdir "$TMP"
    OUTPUTS["$TMP"]="${a#@@}"
    TMPDIRS+=("$TMP")
    CMD+=("$TMP")
    ;;
  @*)  # Input file, decompress now before anything happens
    TMP="`mktemp -d`"
    stat -L "${a#@}" > /dev/null
    LD_PRELOAD= tar -xaf "${a#@}" -C "$TMP"
    TMPDIRS+=("$TMP")
    CMD+=("$TMP")
    ;;
  *)  # Other argument
    CMD+=("$a")
    ;;
  esac
done

# Run the thing to make stuff happen
eval `printf "'%s' " "${CMD[@]}"`
RET=$?

# Tar up all the output files. If any don't exist just don't output that file.
for tmp in "${!OUTPUTS[@]}"; do
  if [ -e "$tmp" ]
  then tar -caf "${OUTPUTS[$tmp]}" -C "$tmp" .
  fi
done

exit $RET
