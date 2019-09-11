#!/bin/bash

TMPDIRS=()
declare -A OUTPUTS

set -e

trap 'rm -rf "${TMPDIRS[@]}"' EXIT

# Special: If the first argument is a number, its a repcount.
REPS=1
if [[ "$1" =~ ^[0123456789]+$ ]]; then
  REPS="$1"
  shift 1
fi

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
    LD_PRELOAD= tar -xf "${a#@}" -C "$TMP"
    TMPDIRS+=("$TMP")
    CMD+=("$TMP")
    ;;
  *)  # Other argument
    CMD+=("$a")
    ;;
  esac
done

# Run the thing to make stuff happen
for i in {1.."$REPS"}; do eval "${CMD[@]}"; done

# Tar up all the output files
for tmp in "${!OUTPUTS[@]}"; do
  tar -cf "${OUTPUTS[$tmp]}" -C "$tmp" .
done
