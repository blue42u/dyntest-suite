#!/bin/bash

OUT="$1"
shift 1

TMPDIR="`mktemp -d`"

set -e

trap 'rm -rf "${TMPDIR}"' EXIT

CMD=()
for a in "$@"; do
  case "$a" in
  ??LOG??)  # Log file argument
    CMD+=("--log-file=${TMPDIR}/log.%p")
    ;;
  *)
    CMD+=("$a")
    ;;
  esac
done

eval `printf "'%s' " "${CMD[@]}"`
RET=$?

cat "${TMPDIR}"/* > "$OUT"

exit $RET
