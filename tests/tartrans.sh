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
    tar -xf "${a#@}" -C "$TMP"
    TMPDIRS+=("$TMP")
    CMD+=("$TMP")
    ;;
  *)  # Other argument
    CMD+=("$a")
    ;;
  esac
done

# Run the thing to make stuff happen
eval "${CMD[@]}"

# Tar up all the output files
for tmp in "${!OUTPUTS[@]}"; do
  tar -cf "${OUTPUTS[$tmp]}" -C "$tmp" .
done
